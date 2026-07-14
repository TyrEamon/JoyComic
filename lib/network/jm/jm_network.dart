/// 禁漫网络请求单例。
///
/// 端点与解析对齐禁漫 API：登录（表单 + 选域名探测）、搜索、专辑详情、
/// 章节内文图（图片经分段重组还原）、收藏切换等。响应体中的 `data` 字段为
/// base64 编码的 AES-ECB 密文，由 [convertData] 用 `md5(时间戳+数据盐)`
/// 作密钥解密后得到 JSON。
library jm_network;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../res.dart';
import '../json_value.dart';
import '../../foundation/log.dart';
import 'jm_headers.dart';
import 'jm_image.dart';
import 'jm_models.dart';
import 'jm_parsing.dart';
import '../source_state.dart';

export 'jm_models.dart';

/// 禁漫内置 API 兜底 CDN（失败时自动轮询切换）。
///
/// 合并两类候选：抗封能力更强的 CDN 代理域名在前，原网页域名 `jmcomic*`
/// 在后作为兜底。候选顺序即轮询顺序；登录后 `/setting` 拉取到的
/// `main_web_host` 及用户测速首选域名会在更前方优先使用。
const jmBuiltInDomains = <String>[
  'www.cdnhjk.net',
  'www.cdngwc.cc',
  'www.cdngwc.net',
  'www.cdngwc.club',
  'www.cdnutc.me',
  'jmcomic1.cc',
  'jmcomic2.me',
  'jmcomic3.pw',
  'jmcomic4.win',
];

/// 可切换的图床候选域名列表（章节图与封面所在 host）。
///
/// 仅作兜底初值：实际生效域名以登录后 `/setting` 返回的 `img_host` 及用户
/// 在 [selectShunt] 中测速选中者为准，写入 [JmState] 持久化。
const jmBuiltInImgUrls = <String>[
  'https://cdn-msp.18comic.vip',
  'https://cdn-msp3.jmapiproxy1.cc',
  'https://cdn-msp.jmapiproxy3.cc',
  'https://cdn-msp2.jmapiproxy2.cc',
  'https://cdn-msp3.jmapiproxy3.cc',
];

/// 快速通道的 shunt key（对端 `express=on` 快速图床分流项）。
const jmExpressShuntKey = 0;

/// 禁漫所有漫画当前通用的 scramble 常量。
///
/// 服务端的图片分段阈值对所有作品一致，故此处作为统一常量参与分段数推算。
const jmScrambleId = '220980';

class JmHomeSection {
  final String key;
  final String title;
  final String? categoryParam;
  final List<JmComicBrief> comics;

  const JmHomeSection({
    required this.key,
    required this.title,
    required this.comics,
    this.categoryParam,
  });
}

/// JM 分类接口在没有显式分页元数据时使用的稳定协议页大小。
const jmCategoryProtocolPageSize = 20;

/// Parses the category payload while preserving missing parent identifiers.
/// The source adapter/normalizer is responsible for dropping unroutable entries.
List<JmCategory> parseJmCategories(Object? value) {
  final data = jsonMap(value);
  if (data['categories'] is! List) return const [];
  final categories = <JmCategory>[];
  for (final rawCategory in jsonList(data['categories'])) {
    if (rawCategory is! Map) continue;
    final category = jsonMap(rawCategory);
    final name = jsonString(category['name'] ?? category['title']).trim();
    final slug = jsonString(
      category['slug'] ?? category['id'] ?? category['key'],
    ).trim();
    if (name.isEmpty) continue;

    final subCategories = <JmSubCategory>[];
    for (final rawSubCategory in jsonList(category['sub_categories'])) {
      if (rawSubCategory is! Map) continue;
      final subCategory = jsonMap(rawSubCategory);
      final cid = jsonString(
        subCategory['CID'] ??
            subCategory['cid'] ??
            subCategory['id'] ??
            subCategory['key'] ??
            subCategory['slug'],
      ).trim();
      final subName = jsonString(
        subCategory['name'] ?? subCategory['title'],
      ).trim();
      final subSlug = jsonString(subCategory['slug']).trim();
      if (cid.isEmpty || subName.isEmpty) continue;
      subCategories.add(JmSubCategory(cid, subName, subSlug));
    }
    categories.add(JmCategory(name, slug, subCategories));
  }
  return categories;
}

/// Computes the last page without treating a short final page as page size.
/// An empty response page means there is no more content after [currentPage].
int? jmCategoryMaxPage({
  required int total,
  required int currentPage,
  required int itemCount,
  int? pageSize,
  int? pageCount,
}) {
  final page = currentPage < 1 ? 1 : currentPage;
  if (pageCount != null && pageCount > 0) {
    return pageCount < page ? page : pageCount;
  }
  if (itemCount == 0) return page;
  if (total <= 0) return null;
  final size = pageSize != null && pageSize > 0
      ? pageSize
      : jmCategoryProtocolPageSize;
  final calculated = (total + size - 1) ~/ size;
  return calculated < page ? page : calculated;
}

/// 禁漫网络请求类。
class JmNetwork {
  JmNetwork._create();
  static JmNetwork? _cache;
  factory JmNetwork() => _cache ??= JmNetwork._create();

  /// 由源注册流程注入状态门面。
  JmState? state;

  /// 禁漫 cookie 有效期极短，无需持久化。
  final cookieJar = CookieJar(ignoreExpires: true);

  bool _performingLogin = false;

  String get baseUrl =>
      state?.apiBaseUrl ?? 'https://${jmBuiltInDomains.first}';

  /// 兜底域名轮询候选，优先级：
  /// `用户首选(preferredDomain) > 当前主源(apiBaseUrl) > 内置兜底池`。
  ///
  /// 用户在测速选源中选中的接口域名置顶；其后接 [JmState.apiBaseUrl] 的 host
  /// （登录探测或 setting 返回的主站），剩余内置候选兜底轮询。
  List<String> get _domainCandidates {
    final pool = <String>[...jmBuiltInDomains];
    void lift(String raw) {
      final clean = raw.replaceAll(RegExp(r'^https?://'), '').split('/').first;
      if (clean.isEmpty) return;
      pool.remove(clean);
      pool.insert(0, clean);
    }

    // 先 lift 主源到最前，再 lift preferredDomain（后者覆盖到最前）。
    lift(state?.apiBaseUrl ?? '');
    lift(state?.preferredDomain ?? '');
    return pool;
  }

  // ============================ 通用 GET / POST ============================

  /// 带域名轮询的请求执行：传入 [attempt] 取单域名执行一次。
  ///
  /// 成功或业务级错误返回 Res；底层失败（DioException / 空响应体 / 解析异常）
  /// 返回 null 以触发外层切换域名重试。401（登录失效）属业务级错误，
  /// 直接返回 Res 由上层处理重登，不参与轮询。
  /// 注意：合法的空结果（如 `data` 为空 List）属正常返回，不触发轮询。
  Future<Res<dynamic>?> _doGet(
    String url,
    int time, {
    bool isRetry = false,
  }) async {
    final options = buildApiOptions(time, byte: true);
    options.validateStatus = (i) => i == 200 || i == 401;
    final dio = Dio(options);
    dio.interceptors.add(CookieManager(cookieJar));
    try {
      final res = await dio.get<List<int>>(url);
      if (res.data == null) return null; // 无响应体→换域名
      final body = utf8.decode(res.data!);
      if (res.statusCode == 401) {
        final errorJson = jsonMap(const JsonDecoder().convert(body));
        final msg = jsonString(errorJson['errorMsg'], fallback: 'Error');
        if (msg == '請先登入會員' && state?.username != null && !isRetry) {
          final ok = await state!.reLogin();
          if (ok) return get(url, isRetry: true);
        }
        return Res(null, errorMessage: '$msg');
      }
      final json = const JsonDecoder().convert(body);
      final data = json is Map ? json['data'] : null;
      // 空列表属业务级响应（漫画不存在 / 无搜索结果），按原版返回错误，
      // 不触发域名轮询——后者只针对连接级失败（DioException / 无响应体）。
      if (data is List && data.isEmpty) {
        return const Res(null, errorMessage: 'Empty data');
      }
      // data 为 base64 密文串时解密；否则（如已是数组/对象）直接返回 json。
      if (data is String && data.isNotEmpty) {
        final decoded = convertData(data, '$time$jmDataSecret');
        return Res(const JsonDecoder().convert(decoded));
      }
      return Res<dynamic>(json);
    } on DioException {
      return null; // 网络/超时→换域名
    } catch (e) {
      return null; // 解析异常→换域名
    }
  }

  Future<Res<dynamic>?> _doPost(String url, String data, int time) async {
    final options = buildApiOptions(time, post: true, byte: true);
    final dio = Dio(options);
    dio.interceptors.add(CookieManager(cookieJar));
    try {
      final res = await dio.post<List<int>>(
        url,
        data: data,
        options: Options(validateStatus: (i) => i == 200 || i == 401),
      );
      if (res.data == null) return null;
      final body = utf8.decode(res.data!);
      final decoded = const JsonDecoder().convert(body);
      if (decoded is! Map) return null;
      final json = jsonMap(decoded);
      if (res.statusCode == 401) {
        final msg = jsonString(json['errorMsg'], fallback: 'Unknown Error');
        return Res(null, errorMessage: msg);
      }
      final enc = json['data'];
      if (enc is String && enc.isNotEmpty) {
        final decrypted = convertData(enc, '$time$jmDataSecret');
        return Res(const JsonDecoder().convert(decrypted));
      }
      return Res<dynamic>(json);
    } on DioException {
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 替换 url 的 host 为 [domain]，保留 path/query。
  String _urlWithDomain(String url, String domain) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;
    return uri.replace(scheme: 'https', host: domain).toString();
  }

  /// 按候选域名依次尝试请求 [url]，首个成功者（非空 Res）返回；
  /// 全部失败则返回最后一个错误 Res。最多轮询 [_domainCandidates] 个域名。
  Future<Res<dynamic>> _withDomainFailover(
    String url,
    Future<Res<dynamic>?> Function(String, int) attempt,
  ) async {
    final candidates = _domainCandidates;
    Res<dynamic>? last = const Res(null, errorMessage: '所有域名均不可用');
    for (final d in candidates) {
      // 发起请求前等待正在进行的登录完成，避免并发登录踩 cookie。
      while (_performingLogin) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      final time = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final res = await attempt(_urlWithDomain(url, d), time);
      if (res != null) {
        Log.d('JM OK', '$url (domain: $d)');
        return res;
      }
      Log.w('JM failover: $url', error: 'domain: $d');
      last = res ?? last;
    }
    return last!;
  }

  Future<Res<dynamic>> get(String url, {bool isRetry = false}) async {
    final res = await _withDomainFailover(
      url,
      (u, t) => _doGet(u, t, isRetry: isRetry),
    );
    return res;
  }

  Future<Res<dynamic>> post(String url, String data) async {
    final res = await _withDomainFailover(url, (u, t) => _doPost(u, data, t));
    return res;
  }

  // ============================ 域名探测 / setting 拉取 / 测速选源 ============================

  /// 在候选域名中并发探测可用者：对 `/login` post `&`，返回 401 视作可用。
  ///
  /// 登录前用于快速锁定一个可用接口域名写入 [JmState.apiBaseUrl]。
  Future<int?> selectDomain(List<String> domains) async {
    final time = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final dio = Dio(buildApiOptions(time, post: true));
    dio.options.validateStatus = (_) => true;
    final completer = Completer<int?>();
    var passed = false;
    for (final d in domains) {
      () async {
        try {
          final res = await dio.post('https://$d/login', data: '&');
          if (res.statusCode == 401 && !passed) {
            passed = true;
            completer.complete(domains.indexOf(d));
          }
        } catch (_) {}
      }();
    }
    return completer.future;
  }

  /// 拉取禁漫 `/setting`，解析动态分流项与图床域名。
  ///
  /// 成功后把 `app_shunts` 写入 [JmState.shunts]、`img_host`→[JmState.imageBaseUrl]、
  /// `main_web_host`→[JmState.apiBaseUrl]（主接入域），并返回解析后的 JSON。
  /// 响应解密复用 [get]，无需重复实现 AES 逻辑。
  Future<Res<Map<String, dynamic>>> fetchSetting() async {
    final res = await get('$baseUrl/setting');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    final rawJson = res.data;
    if (rawJson is! Map) {
      return const Res(null, errorMessage: 'setting 解析失败');
    }
    final json = jsonMap(rawJson);

    final shunts = <JmShunt>[];
    for (final rawShunt in jsonList(json['app_shunts'])) {
      if (rawShunt is! Map) continue;
      final shunt = jsonMap(rawShunt);
      final key = jsonInt(shunt['key'], fallback: -1);
      if (key < 0) continue;
      shunts.add(JmShunt(key: key, title: jsonString(shunt['title'])));
    }
    state?.setShunts(shunts);

    final imgHost = jsonString(json['img_host']);
    final cleanImg = imgHost.replaceAll(RegExp(r'^https?://'), '');
    if (cleanImg.isNotEmpty) {
      state?.setImageBaseUrl('https://$cleanImg');
    }
    final mainWeb = jsonString(json['main_web_host']);
    if (mainWeb.isNotEmpty) {
      state?.setApiBaseUrl('https://$mainWeb');
    }
    return Res(json);
  }

  /// 获取某个 shunt（分流）对应的图床域名。
  ///
  /// key=[jmExpressShuntKey]（0）走 `?express=on` 快速通道，key≥1 走
  /// `?app_img_shunt=${key}`。响应经 [get] 自动解密。
  Future<String?> getShuntImgHost(int key) async {
    final qs = key == jmExpressShuntKey ? 'express=on' : 'app_img_shunt=$key';
    final res = await get('$baseUrl/setting?$qs');
    if (res.error || res.data is! Map) return null;
    final host = jsonString(jsonMap(res.data)['img_host']);
    final clean = host.replaceAll(RegExp(r'^https?://'), '');
    return clean.isEmpty ? null : clean;
  }

  /// 测试某图床延迟（HEAD `/favicon.ico`，8s 超时）。失败返回 -1。
  Future<int> testImgHostLatency(String host) async {
    final clean = host.replaceAll(RegExp(r'^https?://'), '');
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (_) => true,
      ),
    );
    final sw = Stopwatch()..start();
    try {
      await dio.head('https://$clean/favicon.ico');
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  /// Tests a JM API domain with a lightweight HEAD request and a ranged GET
  /// fallback. The measured value is real elapsed wall-clock time; -1 means
  /// timeout or an unreachable/server-failing endpoint.
  Future<int> testApiDomainLatency(
    String domain, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final raw = domain.trim();
    if (raw.isEmpty) return -1;
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null || uri.host.isEmpty) return -1;
    final endpoint = uri.replace(path: '/', query: null, fragment: null);
    final dio = Dio(
      BaseOptions(
        connectTimeout: timeout,
        sendTimeout: timeout,
        receiveTimeout: timeout,
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    );
    final stopwatch = Stopwatch()..start();
    try {
      Response<dynamic> response;
      try {
        response = await dio.headUri(endpoint);
      } on DioException {
        response = await dio.getUri(
          endpoint,
          options: Options(
            headers: const <String, String>{'Range': 'bytes=0-0'},
          ),
        );
      }
      if (response.statusCode == 405 || response.statusCode == 501) {
        response = await dio.getUri(
          endpoint,
          options: Options(
            headers: const <String, String>{'Range': 'bytes=0-0'},
          ),
        );
      }
      final status = response.statusCode;
      return status != null && status < 500
          ? stopwatch.elapsedMilliseconds
          : -1;
    } on DioException {
      return -1;
    } finally {
      stopwatch.stop();
      dio.close(force: true);
    }
  }

  /// 测速所有 shunt（app_shunts + express 快速通道）。
  ///
  /// [shunts] 为服务端原始分流项；返回值含 express（key=0）。每项含
  /// 延迟与对应图床 host；失败项 latency=-1。
  Future<List<JmShuntSpeed>> testAllShunts(List<JmShunt> shunts) async {
    final all = <JmShunt>[
      if (!shunts.any((s) => s.key == jmExpressShuntKey))
        const JmShunt(key: jmExpressShuntKey, title: '快速通道'),
      ...shunts,
    ];
    final results = <JmShuntSpeed>[];
    for (final s in all) {
      try {
        final host = await getShuntImgHost(s.key);
        final latency = host == null ? -1 : await testImgHostLatency(host);
        results.add(
          JmShuntSpeed(
            key: s.key,
            title: s.title,
            latency: latency,
            imgHost: host ?? '',
          ),
        );
      } catch (_) {
        results.add(
          JmShuntSpeed(key: s.key, title: s.title, latency: -1, imgHost: ''),
        );
      }
    }
    return results;
  }

  /// 从测速结果中选最快者（latency≥0 中最小）。无可用者返回 null。
  JmShuntSpeed? pickFastest(List<JmShuntSpeed> results) {
    final valid = results.where((r) => r.latency >= 0).toList();
    if (valid.isEmpty) return null;
    valid.sort((a, b) => a.latency - b.latency);
    return valid.first;
  }

  /// 切换到指定 shunt：持久化 key 并同步图床域名。
  ///
  /// 拉取该 shunt 的图床 host 写入 [JmState]。接口域名（[JmState.preferredDomain]）
  /// 由测速选源 UI 另行设置，此处只切图床，避免误把图床域名当作 API 接入域。
  Future<bool> selectShunt(int key) async {
    state?.setSelectedShuntKey(key);
    try {
      final imgHost = await getShuntImgHost(key);
      if (imgHost != null && imgHost.isNotEmpty) {
        state?.setImageBaseUrl('https://$imgHost');
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// 兼容旧调用：按 index 切图床（走 `app_img_shunt`）。
  Future<void> updateImgUrl(int index) async {
    final host = await getShuntImgHost(index);
    if (host != null && host.isNotEmpty) {
      state?.setImageBaseUrl('https://$host');
    }
  }

  // ============================ 业务端点 ============================

  /// 登录（表单 URL 编码）。
  Future<Res<bool>> login(String account, String pwd) async {
    _performingLogin = true;
    try {
      final res = await post(
        '$baseUrl/login',
        'username=${Uri.encodeComponent(account)}&password=${Uri.encodeComponent(pwd)}',
      );
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return const Res(true);
    } finally {
      _performingLogin = false;
    }
  }

  /// 搜索。
  /// [keyword] 关键词；[page] 页码；[order] 排序（'mr'=最新/ 'mp'=最多/ 'mv'=评分）。
  Future<Res<List<JmComicBrief>>> search(
    String keyword,
    int page,
    String order,
  ) async {
    var kw = keyword.trim().replaceAll('  ', ' ');
    kw = Uri.encodeComponent(kw).replaceAll('%20', '+');
    String url;
    if (page != 1) {
      url = '$baseUrl/search?&search_query=$kw&o=$order&page=$page';
    } else {
      url = '$baseUrl/search?&search_query=$kw&o=$order';
    }
    final res = await get(url);
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    final rawData = res.data;
    if (rawData is! Map) {
      return const Res(null, errorMessage: '搜索结果解析失败');
    }
    final data = jsonMap(rawData);
    final comics = <JmComicBrief>[];
    for (final rawComic in jsonList(data['content'])) {
      if (rawComic is! Map) continue;
      final comic = JmComicBrief.fromJson(jsonMap(rawComic));
      if (comic.id.isEmpty) continue;
      comics.add(comic);
    }
    return Res(comics);
  }

  /// 获取一级分类及其子分类。
  Future<Res<List<JmCategory>>> getCategories() async {
    final res = await get('$baseUrl/categories');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    if (res.data is! Map) {
      return const Res(null, errorMessage: '分类解析失败');
    }
    final data = jsonMap(res.data);
    if (data['categories'] is! List) {
      return const Res(null, errorMessage: '分类解析失败');
    }
    return Res(parseJmCategories(data));
  }

  /// 获取分类漫画，排序值由源适配层映射为服务端 order。
  Future<Res<List<JmComicBrief>>> getCategoryComics(
    String category,
    String order,
    int page,
  ) async {
    final uri = Uri.parse('$baseUrl/categories/filter').replace(
      queryParameters: {'o': order, 'c': category, 'page': page.toString()},
    );
    final res = await get(uri.toString());
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    if (res.data is! Map) {
      return const Res(null, errorMessage: '分类漫画解析失败');
    }
    final data = jsonMap(res.data);
    if (data['content'] is! List) {
      return const Res(null, errorMessage: '分类漫画解析失败');
    }
    final content = jsonList(data['content']);
    final comics = <JmComicBrief>[];
    for (final rawComic in content) {
      if (rawComic is! Map) continue;
      final comic = JmComicBrief.fromJson(jsonMap(rawComic));
      if (comic.id.isEmpty) continue;
      comics.add(comic);
    }

    final total = jsonInt(data['total']);
    final rawPageSize = jsonInt(
      data['page_size'] ?? data['pageSize'] ?? data['per_page'],
    );
    final rawPageCount = jsonInt(
      data['page_count'] ??
          data['pageCount'] ??
          data['total_page'] ??
          data['totalPage'],
    );
    final maxPage = jmCategoryMaxPage(
      total: total,
      currentPage: page,
      itemCount: content.length,
      pageSize: rawPageSize > 0 ? rawPageSize : null,
      pageCount: rawPageCount > 0 ? rawPageCount : null,
    );
    return Res(comics, subData: maxPage);
  }

  /// 获取首页分区。
  Future<Res<List<JmHomeSection>>> getHomeSections() async {
    final res = await get('$baseUrl/promote?page=0');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    if (res.data is! List) {
      return const Res(null, errorMessage: '首页分区解析失败');
    }
    final sections = <JmHomeSection>[];
    for (final rawSection in jsonList(res.data)) {
      if (rawSection is! Map) continue;
      final section = jsonMap(rawSection);
      final title = jsonString(section['title']).trim();
      final type = jsonString(section['type']);
      final id = jsonString(section['id']).trim();
      final slug = jsonString(section['slug']).trim();
      final key = (type == 'category_id' && slug.isNotEmpty ? slug : id).trim();
      if (title.isEmpty) continue;

      final comics = <JmComicBrief>[];
      for (final rawComic in jsonList(section['content'])) {
        if (rawComic is! Map) continue;
        final comic = JmComicBrief.fromJson(jsonMap(rawComic));
        if (comic.id.isEmpty) continue;
        comics.add(comic);
      }
      sections.add(
        JmHomeSection(
          key: key.isEmpty ? title : key,
          title: title,
          categoryParam: type == 'promote' || key.isEmpty ? null : key,
          comics: comics,
        ),
      );
    }
    return Res(sections);
  }

  /// 专辑（漫画）详情。
  Future<Res<JmComicInfo>> getComicInfo(String id) async {
    final res = await get('$baseUrl/album?id=$id');
    if (res.error) {
      if (res.errorMessage?.contains('Empty data') ?? false) {
        return Res(null, errorMessage: '漫画不存在: id = $id');
      }
      return Res(null, errorMessage: res.errorMessage);
    }
    final info = parseJmComicInfoResponse(res.data, id: id);
    return info == null ? const Res(null, errorMessage: '漫画详情解析失败') : Res(info);
  }

  /// 章节内文图文件名列表（图片重组用 scrambleId 与 bookId 由调用方推算）。
  Future<Res<List<String>>> getChapter(String id) async {
    final res = await get('$baseUrl/chapter?&id=$id');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    final rawData = res.data;
    if (rawData is! Map) {
      return const Res(null, errorMessage: '章节内容解析失败');
    }
    final images = <String>[];
    for (final image in jsonStringList(jsonMap(rawData)['images'])) {
      images.add(getJmImageUrl(image, id));
    }
    return Res(images);
  }

  /// 点赞。
  Future<Res<bool>> likeComic(String id) async {
    final res = await post('$baseUrl/like', 'id=$id');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    return const Res(true);
  }

  /// 获取热门搜索词。
  ///
  /// 响应为 JSON 字符串数组，如 `["校园","恋爱","同人"]`。
  Future<Res<List<String>>> getHotTags() async {
    final res = await get('$baseUrl/hot_tags');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    return Res(jsonStringList(res.data));
  }
  // ============================ 收藏相关 ============================

  /// 获取收藏列表。
  ///
  /// [o] 排序：'mr' 最新 / 'mp' 最多。
  /// [folderId] 文件夹 id，'0' 为"全部"。
  Future<Res<List<JmComicBrief>>> fetchFavorites({
    int page = 1,
    String o = 'mr',
    String folderId = '0',
  }) async {
    final res = await get(
      '$baseUrl/favorite?page=$page&o=$o&folder_id=$folderId',
    );
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    final rawData = res.data;
    if (rawData is! Map) return Res(<JmComicBrief>[]);
    final comics = <JmComicBrief>[];
    for (final rawComic in jsonList(jsonMap(rawData)['list'])) {
      if (rawComic is! Map) continue;
      final comic = JmComicBrief.fromJson(jsonMap(rawComic));
      if (comic.id.isEmpty) continue;
      comics.add(comic);
    }
    return Res(comics);
  }

  /// 切换收藏（已收藏则取消，未收藏则添加）。
  Future<Res<bool>> toggleFavorite(String albumId) async {
    final res = await get('$baseUrl/favorite?aid=$albumId');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    return const Res(true);
  }

  /// 获取收藏文件夹列表。
  Future<Res<List<Map<String, dynamic>>>> fetchFavoriteFolders() async {
    final res = await get('$baseUrl/favorite_folder');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    final folders = <Map<String, dynamic>>[];
    for (final rawFolder in jsonList(res.data)) {
      if (rawFolder is! Map) continue;
      folders.add(jsonMap(rawFolder));
    }
    return Res(folders);
  }

  /// 登出。
  Future<void> logout() async => cookieJar.deleteAll();

  // ============================ 评论相关 ============================

  /// 获取评论原始数据。
  ///
  /// [id] 漫画 id，[page] 页码，[mode] 评论模式（默认 'manhua'）。
  /// 返回解析后的行数据列表，每个 map 含：id / avatar / userName / content / time / replyCount。
  Future<Res<List<Map<String, dynamic>>>> getComment(
    String id,
    int page, [
    String mode = 'manhua',
  ]) async {
    final res = await get('$baseUrl/forum?mode=$mode&aid=$id&page=$page');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    final rawData = res.data;
    if (rawData is! Map) {
      return const Res(null, errorMessage: '评论解析失败');
    }
    final data = jsonMap(rawData);
    final comments = <Map<String, dynamic>>[];
    for (final rawComment in jsonList(data['list'])) {
      if (rawComment is! Map) continue;
      final comment = jsonMap(rawComment);
      final replies = jsonList(comment['replys']);
      final rawReplyCount =
          comment['replyCount'] ??
          comment['reply_count'] ??
          comment['comments'];
      final commentId = jsonString(comment['CID'] ?? comment['id']);
      comments.add(<String, dynamic>{
        'id': commentId.isEmpty ? null : commentId,
        'avatar': comment['photo'] == null
            ? null
            : getJmAvatarUrl(jsonString(comment['photo'])),
        'userName': jsonString(comment['username']),
        'content': _stripHtml(jsonString(comment['content'])),
        'time': comment['addtime'] == null
            ? null
            : jsonString(comment['addtime']),
        'replyCount': jsonInt(rawReplyCount, fallback: replies.length),
      });
    }
    return Res(comments, subData: jsonInt(data['total']));
  }

  /// 简易 HTML 标签剥离。
  String _stripHtml(String input) =>
      input.replaceAll(RegExp(r'<[^>]*>'), '').trim();
}

/// 单个 shunt 的测速结果。
class JmShuntSpeed {
  /// 分流 key（0 为 express 快速通道）。
  final int key;

  /// 分流展示名。
  final String title;

  /// 测得延迟（ms）；-1 表示失败/超时。
  final int latency;

  /// 该 shunt 对应的图床 host（失败为空串）。
  final String imgHost;

  const JmShuntSpeed({
    required this.key,
    required this.title,
    required this.latency,
    required this.imgHost,
  });

  bool get available => latency >= 0;

  @override
  String toString() => 'JmShuntSpeed($key:$title ${latency}ms [$imgHost])';
}
