/// 哔咔网络请求单例。
///
/// 端点与解析对齐哔咔 API：登录取 token、分类、高级搜索、漫画详情、
/// 章节/分章图片、收藏切换等。所有请求经 [PicacgHeaders.buildHeaders]
/// 签名；遇 401 自动用已存账密重登并重试一次（避免登录态失效打回登录页）。
library picacg_network;

import 'dart:convert' as convert;

import 'package:dio/dio.dart';

import '../res.dart';
import '../json_value.dart';
import '../base_comic.dart';
import '../../foundation/log.dart';
import 'picacg_headers.dart';
import 'picacg_models.dart';
import 'picacg_parsing.dart';
import '../source_state.dart';

export 'picacg_models.dart';

/// 哔咔 API 接入域名候选：`go2778` 中转（默认）+ `picacomic` 直连（备用）。
///
/// 两者走同一套 HMAC 签名（同一服务两个接入点），由 [PicacgState.apiBaseUrl]
/// 持久化当前选中域名，运行期可在 UI 切换。
const picacgApiHosts = <String, String>{
  'go2778': 'https://picaapi.go2778.com',
  'picacomic': 'https://picaapi.picacomic.com',
};

/// 默认接入域名（go2778 中转）。未登录前或 state 未注入时使用。
final defaultPicacgApiUrl = picacgApiHosts['go2778']!;

const defaultAvatarUrl = 'DEFAULT_AVATAR_URL';

/// 哔咔网络请求类。
class PicacgNetwork {
  PicacgNetwork._create();
  static PicacgNetwork? _cache;
  factory PicacgNetwork() => _cache ??= PicacgNetwork._create();

  /// 由源注册流程在初始化时注入状态门面。
  PicacgState? state;

  /// 当前生效的接入域名（go2778/picacomic 二选一，默认 go2778 中转）。
  String get apiUrl =>
      (state?.apiBaseUrl.isNotEmpty ?? false)
          ? state!.apiBaseUrl
          : defaultPicacgApiUrl;

  String get _token => state?.token ?? '';

  // ============================ 通用 GET / POST ============================

  Future<Res<Map<String, dynamic>>> get(String url,
      {bool useCache = false}) async {
    if (_token == '') {
      await Future.delayed(const Duration(milliseconds: 500));
      return const Res(null, errorMessage: '未登录');
    }
    final dio = Dio(_buildOptions('GET', _token,
        url.replaceAll('${apiUrl}/', ''), useCache: useCache));
    dio.options.validateStatus = (i) => i == 200 || i == 400 || i == 401;
    try {
      final res = await dio.get<String>(url);
      final result = await _handle(res);
      if (result.error) {
        Log.w('Pica GET fail', error: '$url → ${result.errorMessage}');
      } else {
        Log.d('Pica GET', url);
      }
      return result;
    } on DioException catch (e) {
      Log.e('Pica GET error', error: e);
      return Res(null, errorMessage: _dioErrMsg(e));
    } catch (e) {
      Log.e('Pica GET error', error: e);
      return Res(null, errorMessage: e.toString());
    }
  }

  Future<Res<Map<String, dynamic>>> post(
      String url, Map<String, String>? data) async {
    final isAuth =
        url == '${apiUrl}/auth/sign-in' || url == '${apiUrl}/auth/register';
    if (_token == '' && !isAuth) {
      await Future.delayed(const Duration(milliseconds: 500));
      return const Res(null, errorMessage: '未登录');
    }
    final dio = Dio(_buildOptions('POST', _token, url.replaceAll('${apiUrl}/', '')));
    dio.options.validateStatus = (i) => i == 200 || i == 400 || i == 401;
    try {
      final res = await dio.post<String>(url, data: data);
      final result = await _handle(res);
      if (result.error) {
        Log.w('Pica POST fail', error: '$url → ${result.errorMessage}');
      } else {
        Log.d('Pica POST', url);
      }
      return result;
    } on DioException catch (e) {
      Log.e('Pica POST error', error: e);
      return Res(null, errorMessage: _dioErrMsg(e));
    } catch (e) {
      Log.e('Pica POST error', error: e);
      return Res(null, errorMessage: e.toString());
    }
  }

  BaseOptions _buildOptions(String method, String token, String path,
      {bool useCache = false}) {
    return buildHeaders(
      method: method,
      token: token,
      urlPath: path,
      channel: state?.channel ?? '3',
      imageQuality: state?.imageQuality ?? 'original',
    );
  }

  Future<Res<Map<String, dynamic>>> _handle(Response<String> res) async {
    if (res.data == null) {
      return const Res(null, errorMessage: 'Empty data');
    }
    final decoded = convert.jsonDecode(res.data!);
    if (decoded is! Map) {
      return const Res(null, errorMessage: '响应结构错误');
    }
    final json = jsonMap(decoded);
    if (res.statusCode == 200) {
      return Res(json);
    } else if (res.statusCode == 400) {
      return Res(
        null,
        errorMessage: jsonString(json['message'], fallback: '请求错误'),
      );
    } else if (res.statusCode == 401) {
      final ok = await _reLogin();
      if (!ok) {
        return const Res(null, errorMessage: '登录失效且重新登录失败');
      }
      // 重登成功：由调用方在网络层外重试一次整体调用更稳妥；
      // 此处返回错误以触发上层重试（保持与原版语义一致）。
      return const Res(null, errorMessage: '请重试');
    }
    return Res(null, errorMessage: 'Invalid Status Code ${res.statusCode}');
  }
  Future<bool> _reLogin() async => state?.reLogin() ?? false;

  String _dioErrMsg(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout) return '连接超时';
    if (e.type == DioExceptionType.sendTimeout) return '发送超时';
    if (e.type == DioExceptionType.receiveTimeout) return '接收超时';
    return e.message ?? e.toString().split('\n').first;
  }

  String _mediaUrl(Object? value, {String fallback = ''}) {
    if (value is String) return value;
    final media = jsonMap(value);
    final fileServer = jsonString(media['fileServer']);
    final path = jsonString(media['path']);
    if (fileServer.isEmpty || path.isEmpty) return fallback;
    return '$fileServer/static/$path';
  }

  // ============================ 业务端点 ============================

  /// 登录成功返回 token。
  Future<Res<String>> login(String email, String password) async {
    final response = await post('${apiUrl}/auth/sign-in', {
      'email': email,
      'password': password,
    });
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final res = response.data;
    final message = jsonString(res['message']);
    if (message == 'success') {
      final token = jsonString(jsonMap(res['data'])['token']);
      if (token.isNotEmpty) return Res(token);
      return const Res(null, errorMessage: 'Failed to get token');
    }
    return Res(null, errorMessage: message);
  }

  /// 用户档案。
  Future<Res<Profile>> getProfile() async {
    final response = await get('${apiUrl}/users/profile');
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final user = jsonMap(jsonMap(response.data['data'])['user']);
    final id = jsonString(user['_id'] ?? user['id']);
    if (id.isEmpty) {
      return const Res(null, errorMessage: '用户档案解析失败');
    }
    final avatar = user['avatar'] == null
        ? defaultAvatarUrl
        : _mediaUrl(user['avatar'], fallback: defaultAvatarUrl);
    return Res(Profile.fromJson(<String, dynamic>{
      ...user,
      'id': id,
      'avatarUrl': avatar,
      'frameUrl': user['character'],
    }));
  }

  /// 热门搜索词。
  Future<Res<List<String>>> getHotTags() async {
    final response = await get('${apiUrl}/keywords');
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final data = jsonMap(response.data['data']);
    return Res(jsonStringList(data['keywords']));
  }

  /// 获取首页分类。跳过 web 专属分类。
  Future<Res<List<CategoryItem>>> getCategories() async {
    final response = await get('${apiUrl}/categories');
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final items = <CategoryItem>[];
    final data = jsonMap(response.data['data']);
    for (final rawCategory in jsonList(data['categories'])) {
      if (rawCategory is! Map) continue;
      final category = jsonMap(rawCategory);
      if (jsonBool(category['isWeb'])) continue;
      final title = jsonString(category['title']);
      if (title.isEmpty) continue;
      items.add(CategoryItem(title, _mediaUrl(category['thumb'])));
    }
    return Res(items);
  }

  /// 高级搜索。[passed] subData 承载 maxPage。
  /// [sort] 排序，'ua'（默认）/'aa'/'dd'。
  Future<Res<List<ComicItemBrief>>> search(
      String keyword, String sort, int page) async {
    final response =
        await post('${apiUrl}/comics/advanced-search?page=$page', {
      'keyword': keyword,
      'sort': sort,
    });
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final comicsData = jsonMap(jsonMap(response.data['data'])['comics']);
    if (comicsData.isEmpty) {
      return const Res(null, errorMessage: '搜索结果解析失败');
    }
    final comics = <ComicItemBrief>[];
    for (final rawComic in jsonList(comicsData['docs'])) {
      if (rawComic is! Map) continue;
      final comic = ComicItemBrief.fromJson(jsonMap(rawComic));
      if (comic.id.isEmpty) continue;
      comics.add(comic);
    }
    return Res(comics, subData: jsonInt(comicsData['pages'], fallback: 1));
  }

  /// 漫画详情：合并详情 + 章节 + 推荐。
  Future<Res<ComicItem>> getComicInfo(String id) async {
    final response = await get('${apiUrl}/comics/$id');
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final epsRes = await getEps(id);
    if (epsRes.error) return Res(null, errorMessage: epsRes.errorMessage);
    final recRes = await getRecommendation(id);
    final comic = jsonMap(jsonMap(response.data['data'])['comic']);
    if (comic.isEmpty) {
      return const Res(null, errorMessage: '漫画详情解析失败');
    }
    final creator = jsonMap(comic['_creator']);
    return Res(ComicItem(
      id: jsonString(comic['_id'], fallback: id),
      title: jsonString(comic['title'], fallback: 'Unknown'),
      author: jsonString(creator['name'] ?? comic['author'], fallback: 'Unknown'),
      description: jsonString(comic['description']),
      thumbUrl: _mediaUrl(comic['thumb']),
      chineseTeam: jsonString(comic['chineseTeam']),
      categories: jsonStringList(comic['categories']),
      tags: jsonStringList(comic['tags']),
      likes: jsonInt(comic['likesCount'] ?? comic['totalLikes'] ?? comic['likes']),
      comments: jsonInt(
        comic['commentsCount'] ?? comic['totalComments'] ?? comic['comments'],
      ),
      isLiked: jsonBool(comic['isLiked']),
      isFavourite: jsonBool(comic['isFavourite']),
      epsCount: jsonInt(comic['epsCount']),
      pagesCount: jsonInt(comic['pagesCount'] ?? comic['pages']),
      time: jsonString(comic['created_at']),
      episodes: epsRes.data,
      recommendation: recRes.error ? <ComicItemBrief>[] : recRes.data,
    ));
  }

  /// 获取章节列表。服务端序为倒序，这里按 order 升序整理返回。
  Future<Res<List<PicacgEpisode>>> getEps(String id) async {
    final episodes = <PicacgEpisode>[];
    var page = 0;
    try {
      while (true) {
        page++;
        final res = await get('${apiUrl}/comics/$id/eps?page=$page');
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        final parsed = parsePicacgEpisodePage(res.data);
        if (parsed == null) {
          return const Res(null, errorMessage: '章节列表解析失败');
        }
        episodes.addAll(parsed.episodes);
        if (page >= parsed.pages) break;
      }
    } catch (e) {
      return Res(null, errorMessage: e.toString());
    }
    episodes.sort((a, b) => a.order.compareTo(b.order));
    return Res(episodes);
  }

  /// 获取某章节的全部图片 URL，分页聚合。
  Future<Res<List<String>>> getComicContent(String id, int order) async {
    final urls = <String>[];
    var page = 0;
    try {
      while (true) {
        page++;
        final res = await get('${apiUrl}/comics/$id/order/$order/pages?page=$page');
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        final pages = jsonMap(jsonMap(res.data['data'])['pages']);
        if (pages.isEmpty) {
          return const Res(null, errorMessage: '章节图片解析失败');
        }
        for (final rawPage in jsonList(pages['docs'])) {
          if (rawPage is! Map) continue;
          final url = _mediaUrl(jsonMap(rawPage)['media']);
          if (url.isNotEmpty) urls.add(url);
        }
        var lastPage = jsonInt(pages['pages'], fallback: 1);
        if (lastPage < 1) lastPage = 1;
        if (page >= lastPage) break;
      }
    } catch (e) {
      return Res(null, errorMessage: e.toString());
    }
    return Res(urls);
  }

  /// 推荐漫画（详情页底部相关推荐）。
  Future<Res<List<ComicItemBrief>>> getRecommendation(String id) async {
    final res = await get('${apiUrl}/comics/$id/recommendation');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    final data = jsonMap(res.data['data']);
    final comics = <ComicItemBrief>[];
    for (final rawComic in jsonList(data['comics'])) {
      if (rawComic is! Map) continue;
      final comic = ComicItemBrief.fromJson(jsonMap(rawComic));
      if (comic.id.isEmpty) continue;
      comics.add(comic);
    }
    return Res(comics);
  }

  /// 获取收藏列表。
  ///
  /// [newToOld] = true 时按最新排序，false 按最早。
  Future<Res<List<BaseComic>>> getFavorites(int page, bool newToOld) async {
    final sort = newToOld ? 'dd' : 'da';
    final res = await get('${apiUrl}/users/favourite?s=$sort&page=$page');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    final comicsData = jsonMap(jsonMap(res.dataOrNull?['data'])['comics']);
    final comics = <BaseComic>[];
    for (final rawComic in jsonList(comicsData['docs'])) {
      if (rawComic is! Map) continue;
      final comic = ComicItemBrief.fromJson(jsonMap(rawComic));
      if (comic.id.isEmpty) continue;
      comics.add(comic);
    }
    return Res<List<BaseComic>>(
      comics,
      subData: jsonInt(comicsData['pages'], fallback: 1),
    );
  }

  /// 收藏 / 取消收藏。
  Future<Res<bool>> favouriteOrUnfavourite(String id) async {
    final res = await post('${apiUrl}/comics/$id/favourite', {});
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    return const Res(true);
  }

  /// 获取评论列表。
  Future<Res<List<Map<String, dynamic>>>> getComments(String id,
      {int page = 1, String type = 'comics'}) async {
    final res = await get('${apiUrl}/$type/$id/comments?page=$page');
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    final commentsData =
        jsonMap(jsonMap(res.dataOrNull?['data'])['comments']);
    final list = <Map<String, dynamic>>[];
    for (final rawComment in jsonList(commentsData['docs'])) {
      if (rawComment is! Map) continue;
      final comment = jsonMap(rawComment);
      final user = jsonMap(comment['_user']);
      final avatar = user['avatar'] == null ? null : _mediaUrl(user['avatar']);
      final commentId = jsonString(comment['_id'] ?? comment['id']);
      list.add(<String, dynamic>{
        'id': commentId.isEmpty ? null : commentId,
        'avatar': avatar,
        'userName': jsonString(user['name'], fallback: 'Unknown'),
        'content': jsonString(comment['content']),
        'time': comment['created_at'] == null
            ? null
            : jsonString(comment['created_at']),
        'replyCount': jsonInt(
          comment['commentsCount'] ??
              comment['replyCount'] ??
              comment['reply_count'],
        ),
      });
    }
    return Res(
      list,
      subData: jsonInt(commentsData['pages'], fallback: 1),
    );
  }
}
