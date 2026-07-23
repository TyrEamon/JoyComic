/// 禁漫网络请求单例。
///
/// 端点与解析对齐禁漫 API：登录（表单 + 选域名探测）、搜索、专辑详情、
/// 章节内文图（图片经分段重组还原）、收藏切换等。响应体中的 `data` 字段为
/// base64 编码的 AES-ECB 密文，由 [convertData] 用 `md5(时间戳+数据盐)`
/// 作密钥解密后得到 JSON。
library;

import 'dart:async';
import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../../comic_source/detail_models.dart';
import '../../foundation/detail_text.dart';
import '../../foundation/log.dart';
import '../../foundation/source_credential_store.dart';
import '../json_value.dart';
import '../res.dart';
import '../source_state.dart';
import 'jm_endpoint_health.dart';
import 'jm_headers.dart';
import 'jm_image.dart';
import 'jm_models.dart';
import 'jm_parsing.dart';
import 'jm_request_cache.dart';
import 'jm_video_models.dart';

export 'jm_models.dart';
export 'jm_video_models.dart';

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
  'https://cdn-msp3.jmapiproxy1.cc',
  'https://cdn-msp.jmapiproxy3.cc',
  'https://cdn-msp2.jmapiproxy2.cc',
  'https://cdn-msp3.jmapiproxy3.cc',
  'https://cdn-msp.18comic.vip',
];

/// 快速通道的 shunt key（对端 `express=on` 快速图床分流项）。
const jmExpressShuntKey = 0;

/// 禁漫所有漫画当前通用的 scramble 常量。
///
/// 服务端的图片分段阈值对所有作品一致，故此处作为统一常量参与分段数推算。
const jmScrambleId = '220980';

/// 首页运营分区「禁漫去碼&全彩化」的 promote id。
///
/// 来源：`GET /promote?page=0` 中 `title=禁漫去碼&全彩化`、`type=promote` 的条目。
/// 完整分页列表走 [JmNetwork.getPromoteList]。
const jmPremiumPromoteId = '30';

/// 与 [jmPremiumPromoteId] 对应的展示标题（繁体与官方首页一致）。
const jmPremiumPromoteTitle = '禁漫去碼&全彩化';

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

/// Stable page size of the JM forum comment endpoint.
const jmCommentProtocolPageSize = 20;

Res<CommentPageData> parseJmCommentPage(Object? value, {required int page}) {
  if (value is! Map || page < 1) return _jmCommentParseFailure();
  final data = jsonMap(value);
  if (data['list'] is! List || !data.containsKey('total')) {
    return _jmCommentParseFailure();
  }
  final totalComments = _parseJmCommentInteger(data['total']);
  if (totalComments == null || totalComments < 0) {
    return _jmCommentParseFailure();
  }

  var resolvedPage = page;
  if (data.containsKey('page')) {
    final parsedPage = _parseJmCommentInteger(data['page']);
    if (parsedPage == null || parsedPage < 1) {
      return _jmCommentParseFailure();
    }
    resolvedPage = parsedPage;
  }

  int? explicitTotalPages;
  for (final key in const <String>[
    'pages',
    'page_count',
    'pageCount',
    'total_page',
    'totalPage',
  ]) {
    if (!data.containsKey(key)) continue;
    final parsedTotalPages = _parseJmCommentInteger(data[key]);
    if (parsedTotalPages == null ||
        parsedTotalPages < 1 ||
        (explicitTotalPages != null &&
            explicitTotalPages != parsedTotalPages)) {
      return _jmCommentParseFailure();
    }
    explicitTotalPages = parsedTotalPages;
  }

  int? explicitPageSize;
  for (final key in const <String>['page_size', 'pageSize', 'per_page']) {
    if (!data.containsKey(key)) continue;
    final parsedPageSize = _parseJmCommentInteger(data[key]);
    if (parsedPageSize == null ||
        parsedPageSize < 1 ||
        (explicitPageSize != null && explicitPageSize != parsedPageSize)) {
      return _jmCommentParseFailure();
    }
    explicitPageSize = parsedPageSize;
  }
  final pageSize = explicitPageSize ?? jmCommentProtocolPageSize;

  final rawComments = jsonList(data['list']);
  if (rawComments.any(
    (comment) => comment is! Map || !_hasValidJmReplies(jsonMap(comment)),
  )) {
    return _jmCommentParseFailure();
  }
  final comments = <Comment>[
    for (final rawComment in rawComments) _parseJmComment(jsonMap(rawComment)),
  ];
  if (comments.length > totalComments) return _jmCommentParseFailure();

  final calculatedTotalPages = totalComments == 0
      ? 1
      : (totalComments + pageSize - 1) ~/ pageSize;
  final totalPages = explicitTotalPages ?? calculatedTotalPages;
  if (resolvedPage > totalPages) return _jmCommentParseFailure();

  return Res<CommentPageData>(
    CommentPageData(
      comments: comments,
      page: resolvedPage,
      totalPages: totalPages,
      totalComments: totalComments,
    ),
  );
}

Res<CommentPageData> _jmCommentParseFailure() =>
    const Res<CommentPageData>(null, errorMessage: '评论解析失败');

int? _parseJmCommentInteger(Object? value) {
  if (value is int) return value;
  if (value is num) {
    if (!value.isFinite || value != value.truncateToDouble()) return null;
    return value.toInt();
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

bool _hasValidJmReplies(Map<String, dynamic> comment) {
  for (final key in const <String>['replys', 'replies']) {
    if (!comment.containsKey(key) || comment[key] == null) continue;
    final value = comment[key];
    if (value is! List) return false;
    for (final rawReply in value) {
      if (rawReply is! Map || !_hasValidJmReplies(jsonMap(rawReply))) {
        return false;
      }
    }
  }
  return true;
}

Comment _parseJmComment(Map<String, dynamic> comment) {
  final rawReplies = comment['replys'] ?? comment['replies'];
  final replies = <Comment>[
    for (final rawReply in jsonList(rawReplies))
      if (rawReply is Map) _parseJmComment(jsonMap(rawReply)),
  ];
  final rawReplyCount =
      comment['replyCount'] ?? comment['reply_count'] ?? comment['comments'];
  final commentId = jsonString(comment['CID'] ?? comment['id']).trim();
  final photo = jsonString(comment['photo']).trim();
  final time = jsonString(comment['addtime']).trim();

  return Comment.snapshot(
    jsonString(comment['username']),
    photo.isEmpty ? null : getJmAvatarUrl(photo),
    normalizeDetailText(jsonString(comment['content'])),
    time.isEmpty ? null : time,
    rawReplyCount == null
        ? replies.length
        : jsonInt(rawReplyCount, fallback: replies.length),
    commentId.isEmpty ? null : commentId,
    jsonInt(comment['likeCount'] ?? comment['likesCount'] ?? comment['likes']),
    jsonBool(comment['isLiked'] ?? comment['liked']),
    replies,
  );
}

typedef JmDioFactory = Dio Function(BaseOptions options);
typedef JmGetRequest = Future<Res<dynamic>> Function(String url);
typedef JmPostRequest = Future<Res<dynamic>> Function(String url, String data);

class JmLoginProfile {
  const JmLoginProfile({
    required this.name,
    this.id,
    this.nickname,
    this.level,
    this.photo,
  });

  final String name;
  final String? id;
  final String? nickname;
  final String? level;
  final String? photo;
}

/// 禁漫网络请求类。
class JmNetwork {
  JmNetwork._create({
    JmDioFactory? dioFactory,
    JmGetRequest? getRequest,
    JmPostRequest? postRequest,
    SourceCredentialStore? credentialStore,
    JmEndpointHealth? endpointHealth,
    JmRequestCache? requestCache,
  }) : _dioFactory = dioFactory ?? Dio.new,
       _getRequest = getRequest,
       _postRequest = postRequest,
       _credentialStore = credentialStore ?? SourceCredentialStore(),
       _endpointHealth = endpointHealth ?? JmEndpointHealth(),
       _cacheInjectedRequests = getRequest == null || requestCache != null,
       _requestCache = requestCache ?? JmRequestCache();

  static JmNetwork? _cache;

  factory JmNetwork({
    JmDioFactory? dioFactory,
    JmGetRequest? getRequest,
    JmPostRequest? postRequest,
    SourceCredentialStore? credentialStore,
    JmEndpointHealth? endpointHealth,
    JmRequestCache? requestCache,
  }) {
    if (dioFactory == null &&
        getRequest == null &&
        postRequest == null &&
        credentialStore == null &&
        endpointHealth == null &&
        requestCache == null) {
      return _cache ??= JmNetwork._create();
    }
    return JmNetwork._create(
      dioFactory: dioFactory,
      getRequest: getRequest,
      postRequest: postRequest,
      credentialStore: credentialStore,
      endpointHealth: endpointHealth,
      requestCache: requestCache,
    );
  }

  final JmDioFactory _dioFactory;
  final JmGetRequest? _getRequest;
  final JmPostRequest? _postRequest;
  final SourceCredentialStore _credentialStore;
  final JmEndpointHealth _endpointHealth;
  final bool _cacheInjectedRequests;
  final JmRequestCache _requestCache;

  SourceCredentialStore get credentialStore => _credentialStore;
  JmLoginProfile? _lastLoginProfile;
  JmLoginProfile? get lastLoginProfile => _lastLoginProfile;
  static const int _inlinePageCacheLimit = 64;

  // Dart map literals preserve insertion order; cache hits remove/reinsert for LRU.
  final Map<String, List<String>> _inlinePagesByComicId =
      <String, List<String>>{};

  /// 由源注册流程注入状态门面。
  JmState? state;

  /// 禁漫 cookie 有效期极短，无需持久化。
  final cookieJar = CookieJar(ignoreExpires: true);

  static final Object _authOperationZoneKey = Object();

  Future<void> _authQueue = Future<void>.value();
  Future<bool>? _reLoginFuture;
  int _authGeneration = 0;

  bool get _ownsAuthenticationOperation =>
      identical(Zone.current[_authOperationZoneKey], this);

  Future<T> runAuthenticationOperation<T>(Future<T> Function() operation) {
    if (_ownsAuthenticationOperation) return operation();

    final previous = _authQueue;
    final turn = Completer<void>();
    _authQueue = turn.future;
    return () async {
      await previous;
      try {
        return await runZoned<Future<T>>(
          operation,
          zoneValues: <Object, Object>{_authOperationZoneKey: this},
        );
      } finally {
        turn.complete();
      }
    }();
  }

  Future<void> _waitForAuthenticationOperations() async {
    if (_ownsAuthenticationOperation) return;
    await _authQueue;
  }

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
    required int requestAuthGeneration,
  }) async {
    final options = buildApiOptions(time, byte: true, avs: state?.avs ?? '');
    options.validateStatus = (i) => i == 200 || i == 401;
    final dio = _dioFactory(options);
    dio.interceptors.add(CookieManager(cookieJar));
    try {
      final res = await dio.get<List<int>>(url);
      if (res.data == null) return null; // 无响应体→换域名
      final body = utf8.decode(res.data!);
      if (res.statusCode == 401) {
        final errorJson = jsonMap(const JsonDecoder().convert(body));
        final msg = jsonString(errorJson['errorMsg'], fallback: 'Error');
        if (msg == '請先登入會員' &&
            await _tryReLogin(
              url,
              isRetry: isRetry,
              requestAuthGeneration: requestAuthGeneration,
            )) {
          return get(url, isRetry: true);
        }
        return Res(null, errorMessage: msg);
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

  Future<Res<dynamic>?> _doPost(
    String url,
    String data,
    int time, {
    bool includeAvs = true,
    bool isRetry = false,
    required int requestAuthGeneration,
  }) async {
    final options = buildApiOptions(
      time,
      post: true,
      byte: true,
      avs: includeAvs ? state?.avs ?? '' : '',
    );
    final dio = _dioFactory(options);
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
        if (msg == '請先登入會員' &&
            await _tryReLogin(
              url,
              isRetry: isRetry,
              requestAuthGeneration: requestAuthGeneration,
            )) {
          return post(url, data, includeAvs: includeAvs, isRetry: true);
        }
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
  bool _isAuthRequest(String url) => Uri.tryParse(url)?.path == '/login';

  Future<bool> _tryReLogin(
    String url, {
    required bool isRetry,
    required int requestAuthGeneration,
  }) async {
    if (_isAuthRequest(url)) return false;
    if (requestAuthGeneration != _authGeneration) return !isRetry;
    if (_ownsAuthenticationOperation) {
      await _clearAuthentication();
      return false;
    }
    if (state?.username != null && !isRetry) {
      try {
        final ok = await _singleFlightReLogin();
        if (ok) return true;
      } catch (_) {
        // Authentication restoration failures are not transport failures.
      }
    }
    await _clearAuthentication();
    return false;
  }

  Future<bool> _singleFlightReLogin() {
    final current = _reLoginFuture;
    if (current != null) return current;

    final completer = Completer<bool>();
    final future = completer.future;
    _reLoginFuture = future;
    () async {
      try {
        final generationBefore = _authGeneration;
        final ok = await runAuthenticationOperation(state!.reLogin);
        if (ok && _authGeneration == generationBefore) _authGeneration++;
        completer.complete(ok);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (identical(_reLoginFuture, future)) _reLoginFuture = null;
      }
    }();
    return future;
  }

  String _urlWithDomain(String url, String domain) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) return url;
    return uri.replace(scheme: 'https', host: domain).toString();
  }

  /// 按候选域名依次尝试请求 [url]，首个成功者（非空 Res）返回；
  /// 全部失败则返回最后一个错误 Res。最多轮询 [_domainCandidates] 个域名。
  ///
  /// 每次 attempt 使用独立 [time]（fresh token/time）。瞬态失败（网络/超时/
  /// 空体/解析/Dio 抛出的 403 等）返回 null 并轮换下一域；401 与其它业务
  /// Res 不轮换。真正成功（!error）时把可用 host 写回 [JmState.apiBaseUrl]。
  ///
  /// 首次生产路径会经 [_ensureDomainWarmup] 共享一次 `/login` 探测，避免并发
  /// 不同 GET 各自在失效首选域上串行空转。登录/鉴权操作跳过 warmup。
  /// 候选顺序经 [_endpointHealth.order] 重排：成功 host 优先，冷却中的靠后。
  /// 传输层 null 记为失败冷却；业务 Res（含 401）不冷却。
  Future<Res<dynamic>> _withDomainFailover(
    String url,
    Future<Res<dynamic>?> Function(String, int) attempt, {
    bool waitForLogin = true,
  }) async {
    if (waitForLogin && !_ownsAuthenticationOperation) {
      await _ensureDomainWarmup();
    }
    final candidates = _endpointHealth.order(_domainCandidates);
    Res<dynamic>? last = const Res(null, errorMessage: '所有域名均不可用');
    for (final d in candidates) {
      if (waitForLogin) await _waitForAuthenticationOperations();
      final time = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final res = await attempt(_urlWithDomain(url, d), time);
      if (res != null) {
        Log.d('JM OK', '$url (domain: $d)');
        // Mirror verifier: cache the first host that completed a non-error hop.
        // 401 / empty-data business Res still stop rotation but are not success.
        if (!res.error) {
          _endpointHealth.recordSuccess(d);
          _rememberSuccessfulApiHost(d);
        } else {
          // Business-level Res (401 / empty data / decoded errors): do not cool.
          _endpointHealth.recordBusinessResponse(d, isBusinessError: true);
        }
        return res;
      }
      // Transport / empty / parse failure: cool the host and try the next.
      _endpointHealth.recordFailure(d, FailureClass.network);
      Log.w('JM failover: $url', error: 'domain: $d');
      last = res ?? last;
    }
    return last!;
  }

  /// First-use domain probe shared across concurrent production requests.
  ///
  /// Single-flight sequential `/login` probes (body `&`, same as [selectDomain]).
  /// The first host that returns 401 is a reachable API endpoint: it is recorded
  /// as success and persisted so waiting callers reorder before failover.
  /// Skipped when a known-good host already exists, during login/auth zones, or
  /// when [waitForLogin] is false (login POST path). Injected [getRequest] never
  /// reaches this path.
  Future<void> _ensureDomainWarmup() {
    final candidates = _domainCandidates;
    if (candidates.isEmpty) return Future<void>.value();
    if (_endpointHealth.hasAnyKnownSuccess(candidates)) {
      return Future<void>.value();
    }
    return _endpointHealth.singleFlight('domain-warmup', () async {
      // Re-check after joining the flight: another waiter may have finished.
      final ordered = _endpointHealth.order(candidates);
      if (_endpointHealth.hasAnyKnownSuccess(ordered)) return;

      final time = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final dio = _dioFactory(buildApiOptions(time, post: true));
      dio.options.validateStatus = (_) => true;
      try {
        for (final domain in ordered) {
          try {
            final res = await dio.post('https://$domain/login', data: '&');
            if (res.statusCode == 401) {
              _endpointHealth.recordSuccess(domain);
              _rememberSuccessfulApiHost(domain);
              return;
            }
          } catch (_) {
            // Probe failure: try the next candidate.
          }
        }
      } finally {
        dio.close(force: true);
      }
    });
  }

  /// Persist a working API host so the next request prefers it (verifier parity).
  void _rememberSuccessfulApiHost(String domain) {
    final clean = domain
        .replaceAll(RegExp(r'^https?://'), '')
        .split('/')
        .first
        .trim();
    if (clean.isEmpty) return;
    final current = state?.apiBaseUrl ?? '';
    final currentHost =
        Uri.tryParse(current)?.host ??
        current.replaceAll(RegExp(r'^https?://'), '').split('/').first;
    if (currentHost.toLowerCase() == clean.toLowerCase()) return;
    state?.setApiBaseUrl('https://$clean');
  }

  /// Public GET entry. When [cacheTtl] is non-null, non-retry, and the path is
  /// an allowlisted public endpoint, successful responses are stored in the
  /// process-local [JmRequestCache]. Auth / favorite / private GETs omit TTL.
  Future<Res<dynamic>> get(
    String url, {
    bool isRetry = false,
    int? requestAuthGeneration,
    Duration? cacheTtl,
  }) async {
    final cacheKey = cacheTtl != null && !isRetry && _cacheInjectedRequests
        ? _publicGetCacheKey(url)
        : null;
    if (cacheKey != null) {
      final hit = _requestCache.get(cacheKey);
      if (hit != null) return hit;
    }

    final request = _getRequest;
    if (request != null) {
      final res = await request(url);
      if (cacheKey != null && !res.error) {
        _requestCache.put(cacheKey, res, cacheTtl!);
      }
      return res;
    }
    final generation = requestAuthGeneration ?? _authGeneration;
    final res = await _withDomainFailover(
      url,
      (u, t) =>
          _doGet(u, t, isRetry: isRetry, requestAuthGeneration: generation),
    );
    if (cacheKey != null && !res.error) {
      _requestCache.put(cacheKey, res, cacheTtl!);
    }
    return res;
  }

  /// Cache key: normalized path + query + optional account isolation.
  /// Never includes token / AVS / password values.
  String? _publicGetCacheKey(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final path = uri.path.isEmpty ? '/' : uri.path;
    // Private / auth / write-ish GETs are never cached even if a TTL is passed.
    if (_isPrivateOrAuthGetPath(path)) return null;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    final account = state?.username?.trim();
    final accountPart = (account != null && account.isNotEmpty)
        ? account
        : 'anonymous';
    // Account-safe public GETs still isolate by username so two sessions on the
    // same device do not share cached payloads that may embed personal fields.
    return 'jm:get:$path$query:$accountPart';
  }

  bool _isPrivateOrAuthGetPath(String path) {
    const blocked = <String>{
      '/login',
      '/favorite',
      '/favorite_folder',
      '/comment',
      '/like',
    };
    return blocked.contains(path);
  }

  Future<Res<dynamic>> post(
    String url,
    String data, {
    bool waitForLogin = true,
    bool includeAvs = true,
    bool isRetry = false,
    int? requestAuthGeneration,
  }) async {
    final request = _postRequest;
    if (request != null) return request(url, data);
    final generation = requestAuthGeneration ?? _authGeneration;
    final res = await _withDomainFailover(
      url,
      (u, t) => _doPost(
        u,
        data,
        t,
        includeAvs: includeAvs,
        isRetry: isRetry,
        requestAuthGeneration: generation,
      ),
      waitForLogin: waitForLogin,
    );
    return res;
  }

  // ============================ 域名探测 / setting 拉取 / 测速选源 ============================

  /// 在候选域名中并发探测可用者：对 `/login` post `&`，返回 401 视作可用。
  ///
  /// 登录前用于快速锁定一个可用接口域名写入 [JmState.apiBaseUrl]。
  /// 相同 [domains] 列表的并发调用经 [_endpointHealth.singleFlight] 合并为一次探测。
  Future<int?> selectDomain(
    List<String> domains, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (domains.isEmpty) return null;
    final flightKey = 'select-domain:${domains.join(',')}';
    return _endpointHealth.singleFlight(flightKey, () async {
      final time = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final dio = _dioFactory(buildApiOptions(time, post: true));
      dio.options.validateStatus = (_) => true;
      final completer = Completer<int?>();
      var remaining = domains.length;
      void complete(int? value) {
        if (!completer.isCompleted) completer.complete(value);
      }

      final timer = Timer(timeout, () => complete(null));
      for (var index = 0; index < domains.length; index++) {
        final domain = domains[index];
        () async {
          try {
            final res = await dio.post('https://$domain/login', data: '&');
            if (res.statusCode == 401) {
              // /login 401 means the API host is reachable: prioritize it for
              // waiting production requests (do not cool).
              _endpointHealth.recordSuccess(domain);
              complete(index);
            }
          } catch (_) {
            // A failed probe only contributes to the all-failed result.
          } finally {
            remaining--;
            if (remaining == 0) complete(null);
          }
        }();
      }

      try {
        return await completer.future;
      } finally {
        timer.cancel();
        dio.close(force: true);
      }
    });
  }

  /// 拉取禁漫 `/setting`，解析动态分流项与图床域名。
  ///
  /// 成功后把 `app_shunts` 写入 [JmState.shunts]、`img_host`→[JmState.imageBaseUrl]、
  /// `main_web_host`→[JmState.apiBaseUrl]（主接入域），并返回解析后的 JSON。
  /// 响应解密复用 [get]，无需重复实现 AES 逻辑。
  Future<Res<Map<String, dynamic>>> fetchSetting() async {
    final res = await get(
      '$baseUrl/setting',
      cacheTtl: const Duration(minutes: 5),
    );
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
    final res = await get(
      '$baseUrl/setting?$qs',
      cacheTtl: const Duration(minutes: 5),
    );
    if (res.error || res.data is! Map) return null;
    final host = jsonString(jsonMap(res.data)['img_host']);
    final clean = host.replaceAll(RegExp(r'^https?://'), '');
    return clean.isEmpty ? null : clean;
  }

  /// 测试某图床延迟：请求一个真实存在的轻量封面图片，失败返回 -1。
  Future<int> testImgHostLatency(String host) async {
    final clean = host.replaceAll(RegExp(r'^https?://'), '');
    final dio = _dioFactory(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (_) => true,
      ),
    );
    final stopwatch = Stopwatch()..start();
    try {
      final response = await dio.get<List<int>>(
        'https://$clean/media/albums/438696_3x4.jpg',
        options: Options(
          headers: imageHeaders(),
          responseType: ResponseType.bytes,
        ),
      );
      final status = response.statusCode;
      return status != null && status >= 200 && status < 300
          ? stopwatch.elapsedMilliseconds
          : -1;
    } catch (_) {
      return -1;
    } finally {
      stopwatch.stop();
      dio.close(force: true);
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
    final dio = _dioFactory(
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
  Future<Res<bool>> login(String account, String pwd) =>
      runAuthenticationOperation(() => _login(account, pwd));

  Future<Res<bool>> _login(String account, String pwd) async {
    _lastLoginProfile = null;
    final res = await post(
      '$baseUrl/login',
      'username=${Uri.encodeComponent(account)}&password=${Uri.encodeComponent(pwd)}',
      waitForLogin: false,
      includeAvs: false,
    );
    if (res.error) {
      await _clearAuthentication();
      return Res(null, errorMessage: res.errorMessage);
    }
    final data = res.data;
    if (data is! Map) {
      await _clearAuthentication();
      return const Res(null, errorMessage: '登录响应解析失败');
    }
    final loginData = jsonMap(data);
    final avs = jsonString(loginData['s']).trim();
    if (avs.isEmpty) {
      await _clearAuthentication();
      return const Res(null, errorMessage: '登录响应缺少 AVS');
    }
    String? optionalText(Object? value) {
      final text = jsonString(value).trim();
      return text.isEmpty ? null : text;
    }

    _lastLoginProfile = JmLoginProfile(
      name:
          optionalText(
            loginData['username'] ?? loginData['name'] ?? loginData['nickname'],
          ) ??
          account,
      id: optionalText(loginData['uid'] ?? loginData['id']),
      nickname: optionalText(loginData['nickname']),
      level: optionalText(loginData['level'] ?? loginData['lv']),
      photo: optionalText(
        loginData['photo'] ?? loginData['avatar'] ?? loginData['avatarUrl'],
      ),
    );

    ({String user, String password})? previousCredentials;
    try {
      previousCredentials = await _credentialStore.readCredentials('jm');
      await _credentialStore.saveCredentials('jm', account, pwd);
      await _credentialStore.saveSession('jm', 'avs', avs);
      await state?.setAvs(avs);
    } catch (_) {
      await _clearAuthentication();
      await _restoreCredentials(previousCredentials);
      return const Res(null, errorMessage: '登录凭据保存失败');
    }
    _authGeneration++;
    return const Res(true);
  }

  Future<void> _clearAuthentication() async {
    try {
      await state?.clearAvs();
    } catch (_) {
      // Local auth is invalidated before persistence by JmStateImpl.
    }
    try {
      await _credentialStore.saveSession('jm', 'avs', '');
    } catch (_) {
      // Cleanup is best-effort and must not replace the original auth error.
    }
  }

  Future<void> rollbackAuthentication(
    ({String user, String password})? previous,
  ) async {
    await _clearAuthentication();
    await _restoreCredentials(previous);
  }

  Future<void> _restoreCredentials(
    ({String user, String password})? previous,
  ) async {
    try {
      if (previous == null) {
        await _credentialStore.clearSource('jm');
      } else {
        await _credentialStore.saveCredentials(
          'jm',
          previous.user,
          previous.password,
        );
      }
    } catch (_) {
      // Rollback is best-effort when secure storage itself is unavailable.
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
    final res = await get(url, cacheTtl: const Duration(seconds: 45));
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
    final total = jsonInt(data['total']);
    return Res(comics, subData: total > 0 ? total : null);
  }

  /// 获取一级分类及其子分类。
  Future<Res<List<JmCategory>>> getCategories() async {
    final res = await get(
      '$baseUrl/categories',
      cacheTtl: const Duration(seconds: 45),
    );
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
    final res = await get(
      uri.toString(),
      cacheTtl: const Duration(seconds: 45),
    );
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
    final res = await get(
      '$baseUrl/promote?page=0',
      cacheTtl: const Duration(minutes: 2),
    );
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
          // promote 分区用数字 id 走 promote_list；category_id 用 slug 走 filter。
          categoryParam: key.isEmpty ? null : key,
          comics: comics,
        ),
      );
    }
    return Res(sections);
  }

  /// 首页运营分区完整列表（分页）。
  ///
  /// [id] 为 `/promote` 返回的分区 id（如 [jmPremiumPromoteId]）。
  /// [page] 对外使用 1-based；请求时转换为服务端 0-based。
  /// 成功时 [Res.subData] 为 total（可空）。
  Future<Res<List<JmComicBrief>>> getPromoteList(String id, int page) async {
    final promoteId = id.trim();
    if (promoteId.isEmpty) {
      return const Res(null, errorMessage: '分区 id 无效');
    }
    final apiPage = page < 1 ? 0 : page - 1;
    final uri = Uri.parse(
      '$baseUrl/promote_list',
    ).replace(queryParameters: {'id': promoteId, 'page': apiPage.toString()});
    final res = await get(uri.toString(), cacheTtl: const Duration(minutes: 2));
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    if (res.data is! Map) {
      return const Res(null, errorMessage: '分区列表解析失败');
    }
    final data = jsonMap(res.data);
    if (data['list'] is! List) {
      return const Res(null, errorMessage: '分区列表解析失败');
    }
    final comics = <JmComicBrief>[];
    for (final rawComic in jsonList(data['list'])) {
      if (rawComic is! Map) continue;
      final comic = JmComicBrief.fromJson(jsonMap(rawComic));
      if (comic.id.isEmpty) continue;
      comics.add(comic);
    }
    final total = jsonInt(data['total']);
    return Res(comics, subData: total > 0 ? total : null);
  }

  /// 专辑（漫画）详情。
  ///
  /// `/album` 含 liked/favorite 等个性化字段：已登录用户（[JmState.username]
  /// 非空）禁止命中公开 TTL 缓存，确保每次拉取最新收藏/点赞状态。
  Future<Res<JmComicInfo>> getComicInfo(String id) async {
    final username = state?.username?.trim();
    final loggedIn = username != null && username.isNotEmpty;
    final res = await get(
      '$baseUrl/album?id=$id',
      cacheTtl: loggedIn ? null : const Duration(minutes: 2),
    );
    if (res.error) {
      if (res.errorMessage?.contains('Empty data') ?? false) {
        return Res(null, errorMessage: '漫画不存在: id = $id');
      }
      return Res(null, errorMessage: res.errorMessage);
    }
    final info = parseJmComicInfoResponse(res.data, id: id);
    if (info == null) {
      _inlinePagesByComicId.remove(id);
      return const Res(null, errorMessage: '漫画详情解析失败');
    }
    _replaceInlinePages(id, info.images);
    return Res(info);
  }

  /// 章节内文图文件名列表（图片重组用 scrambleId 与 bookId 由调用方推算）。
  ///
  /// 未购买精品专辑时 chapter 仍通常返回完整 images；若为空则用 [pageHint]
  ///（来自 album.total_photos）按 `00001.webp` 顺序拼 CDN 路径。
  Future<Res<List<String>>> getChapter(String id, {int? pageHint}) async {
    final res = await get(
      '$baseUrl/chapter?id=$id',
      cacheTtl: const Duration(minutes: 1),
    );
    if (res.error) {
      final fallback = _cdnSequentialPages(id, pageHint);
      if (fallback != null) return Res(fallback);
      return Res(null, errorMessage: res.errorMessage);
    }
    final rawData = res.data;
    if (rawData is! Map) {
      final fallback = _cdnSequentialPages(id, pageHint);
      if (fallback != null) return Res(fallback);
      return const Res(null, errorMessage: '章节内容解析失败');
    }
    final names = jsonStringList(jsonMap(rawData)['images']);
    if (names.isEmpty) {
      final fallback = _cdnSequentialPages(id, pageHint);
      if (fallback != null) return Res(fallback);
      return const Res(null, errorMessage: '章节图片为空');
    }
    return Res(_resolveJmPageImages(names, id, _effectiveImageBaseUrl()));
  }

  /// 优先返回详情接口内联页；冷缓存先刷新详情，再按需回退章节端点。
  ///
  /// 付费未购精品常见：album.images 为空但 chapter 有图、CDN 可直读。
  /// 本方法保证只要 chapter 或 total_photos 可用就能返回完整页 URL 列表。
  Future<Res<List<String>>> getComicPages(
    String comicId,
    String? chapterId,
  ) async {
    final ep = (chapterId == null || chapterId.isEmpty || chapterId == comicId)
        ? comicId
        : chapterId;

    // Multi-chapter: go straight to the chapter endpoint for that ep id.
    if (ep != comicId) {
      return getChapter(ep);
    }

    var inlinePages = _takeCachedInlinePages(comicId);
    int? totalPhotosHint;
    if (inlinePages == null) {
      final detail = await getComicInfo(comicId);
      if (detail.error) {
        // Album failed — still try chapter / CDN for this id.
        return getChapter(comicId);
      }
      totalPhotosHint = detail.data.totalPhotos;
      inlinePages = _takeCachedInlinePages(comicId);
    }

    if (inlinePages != null && inlinePages.isNotEmpty) {
      return Res(
        _resolveJmPageImages(inlinePages, comicId, _effectiveImageBaseUrl()),
      );
    }

    // Empty inline (typical unpaid premium): chapter API + sequential CDN.
    return getChapter(comicId, pageHint: totalPhotosHint);
  }

  String _effectiveImageBaseUrl() =>
      resolveJmImageBaseUrl(state?.imageBaseUrl ?? jmBaseUrl);

  /// Builds absolute CDN URLs for sequential page names when the API omits
  /// images. Returns null when [pageHint] is missing or non-positive.
  List<String>? _cdnSequentialPages(String chapterId, int? pageHint) {
    final count = pageHint ?? 0;
    if (count <= 0) return null;
    return _resolveJmPageImages(
      buildJmSequentialPageNames(count),
      chapterId,
      _effectiveImageBaseUrl(),
    );
  }

  void _replaceInlinePages(String comicId, List<String> rawImages) {
    _inlinePagesByComicId.remove(comicId);
    if (rawImages.isEmpty) return;
    _inlinePagesByComicId[comicId] = List<String>.unmodifiable(rawImages);
    while (_inlinePagesByComicId.length > _inlinePageCacheLimit) {
      _inlinePagesByComicId.remove(_inlinePagesByComicId.keys.first);
    }
  }

  List<String>? _takeCachedInlinePages(String comicId) {
    final pages = _inlinePagesByComicId.remove(comicId);
    if (pages != null) _inlinePagesByComicId[comicId] = pages;
    return pages;
  }

  List<String> _resolveJmPageImages(
    Iterable<String> rawImages,
    String comicId,
    String imageBaseUrl,
  ) {
    final normalizedBaseUrl = resolveJmImageBaseUrl(imageBaseUrl);
    // Prefer the live image base; keep absolute URLs that already target a host.
    return List<String>.unmodifiable([
      for (final image in rawImages)
        if (_isAbsoluteHttpUrl(image))
          image
        else if (image.trim().isNotEmpty)
          '$normalizedBaseUrl/media/photos/$comicId/${image.trim()}',
    ]);
  }

  bool _isAbsoluteHttpUrl(String image) {
    final uri = Uri.tryParse(image);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// 发送漫画评论，保留底层请求错误。
  Future<Res<bool>> sendComment(String comicId, String content) async {
    final body = Uri(
      queryParameters: <String, String>{
        'video_id': comicId,
        'comment': content,
        'status': 'true',
      },
    ).query;
    final res = await post('$baseUrl/comment', body);
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    return const Res(true);
  }

  /// 点赞。
  Future<Res<bool>> likeComic(String id) async {
    final res = await post('$baseUrl/like', 'id=$id');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    return const Res(true);
  }

  Future<Res<({List<JmVideoItem> items, int total})>> getVideos({
    int page = 1,
    String videoType = '',
    String searchQuery = '',
  }) async {
    final query = <String, String>{
      'page': '$page',
      if (videoType.trim().isNotEmpty) 'video_type': videoType.trim(),
      if (searchQuery.trim().isNotEmpty) 'search_query': searchQuery.trim(),
    };
    final uri = Uri.parse('$baseUrl/videos').replace(queryParameters: query);
    final res = await get(
      uri.toString(),
      cacheTtl: const Duration(seconds: 30),
    );
    if (res.error) {
      return Res(null, errorMessage: res.errorMessage);
    }
    if (res.data is! Map) {
      return const Res(null, errorMessage: '视频列表响应结构错误');
    }
    final data = jsonMap(res.data);
    final rawValue = data['list'] ?? data['videos'] ?? data['data'];
    if (rawValue is! List) {
      return const Res(null, errorMessage: '视频列表响应结构错误');
    }
    final rawList = jsonList(rawValue);
    final imageBase = state?.imageBaseUrl ?? jmBuiltInImgUrls.first;
    final items = <JmVideoItem>[];
    for (final raw in rawList) {
      if (raw is! Map) {
        return const Res(null, errorMessage: '视频列表项目结构错误');
      }
      final item = JmVideoItem.fromJson(jsonMap(raw), imageBaseUrl: imageBase);
      if (item.id.isEmpty && item.title.isEmpty) {
        return const Res(null, errorMessage: '视频列表项目为空');
      }
      items.add(item);
    }
    final explicitTotal = jsonInt(
      data['total'] ?? data['total_count'] ?? data['count'],
      fallback: -1,
    );
    final inferredTotal = rawList.length >= 20
        ? page * 20 + 1
        : (page - 1) * 20 + rawList.length;
    return Res((
      items: items,
      total: explicitTotal >= 0 ? explicitTotal : inferredTotal,
    ));
  }

  Future<Res<JmVideoDetail>> getVideoDetail(String videoId) async {
    Res<dynamic>? lastFailure;
    for (final parameter in const <String>['vid', 'id']) {
      final uri = Uri.parse(
        '$baseUrl/video',
      ).replace(queryParameters: <String, String>{parameter: videoId});
      final res = await get(
        uri.toString(),
        cacheTtl: const Duration(seconds: 30),
      );
      if (res.error) {
        lastFailure = res;
        continue;
      }
      try {
        final detail = JmVideoDetail.fromJson(
          jsonMap(res.data),
          imageBaseUrl: state?.imageBaseUrl ?? jmBuiltInImgUrls.first,
        );
        if (detail.id.isNotEmpty || detail.title.isNotEmpty) {
          return Res(detail);
        }
        lastFailure = const Res(null, errorMessage: '视频详情为空');
      } on FormatException {
        lastFailure = const Res(null, errorMessage: '视频详情响应结构错误');
      }
    }
    return Res(null, errorMessage: lastFailure?.errorMessage ?? '视频详情加载失败');
  }

  Future<Res<List<JmVideoItem>>> getLatestHanime() async {
    final res = await get(
      '$baseUrl/latest_hanime',
      cacheTtl: const Duration(seconds: 45),
    );
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    final data = res.data;
    final rawList = switch (data) {
      List value => value,
      Map value => switch (value['list'] ?? value['data']) {
        List list => list,
        _ => null,
      },
      _ => null,
    };
    if (rawList == null) {
      return const Res(null, errorMessage: 'H动漫列表响应结构错误');
    }
    final imageBase = state?.imageBaseUrl ?? jmBuiltInImgUrls.first;
    final items = <JmVideoItem>[];
    for (final raw in rawList) {
      if (raw is! Map) {
        return const Res(null, errorMessage: 'H动漫列表项目结构错误');
      }
      final item = JmVideoItem.fromJson(jsonMap(raw), imageBaseUrl: imageBase);
      if (item.id.isEmpty && item.title.isEmpty) {
        return const Res(null, errorMessage: 'H动漫列表项目为空');
      }
      items.add(item);
    }
    return Res(items);
  }

  /// 获取热门搜索词。
  ///
  /// 响应为 JSON 字符串数组，如 `["校园","恋爱","同人"]`。
  Future<Res<List<String>>> getHotTags() async {
    final res = await get(
      '$baseUrl/hot_tags',
      cacheTtl: const Duration(seconds: 45),
    );
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
    if (rawData is! Map) return const Res(<JmComicBrief>[]);
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
  Future<void> logout() {
    _lastLoginProfile = null;
    return runAuthenticationOperation(_logout);
  }

  Future<void> _logout() async {
    await cookieJar.deleteAll();
    await _clearAuthentication();
    await _credentialStore.clearSource('jm');
  }

  // ============================ 评论相关 ============================

  /// 获取类型化评论分页数据。
  Future<Res<CommentPageData>> getComment(
    String id,
    int page, [
    String mode = 'manhua',
  ]) async {
    final res = await get('$baseUrl/forum?mode=$mode&aid=$id&page=$page');
    if (res.error) {
      return Res<CommentPageData>(null, errorMessage: res.errorMessage);
    }
    return parseJmCommentPage(res.data, page: page);
  }
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
