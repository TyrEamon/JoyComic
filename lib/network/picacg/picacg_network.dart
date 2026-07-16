/// 哔咔网络请求单例。
///
/// 端点与解析对齐哔咔 API：登录取 token、分类、高级搜索、漫画详情、
/// 章节/分章图片、收藏切换等。所有请求经 [PicacgHeaders.buildHeaders]
/// 签名；遇 401 自动用已存账密重登并重试一次（避免登录态失效打回登录页）。
library;

import 'dart:async';
import 'dart:convert' as convert;

import 'package:dio/dio.dart';

import '../../comic_source/detail_models.dart';
import '../../foundation/log.dart';
import '../base_comic.dart';
import '../json_value.dart';
import '../res.dart';
import '../source_state.dart';
import 'picacg_headers.dart';
import 'picacg_models.dart';
import 'picacg_parsing.dart';

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

class PicacgCategory {
  final String key;
  final String title;
  final String param;
  final String? cover;

  const PicacgCategory({
    required this.key,
    required this.title,
    required this.param,
    this.cover,
  });
}

/// Parses a categories response into routable, non-web category records.
List<PicacgCategory> parsePicacgCategories(Object? value) {
  final root = jsonMap(value);
  final data = jsonMap(root['data']);
  if (data['categories'] is! List) return const [];
  final categories = <PicacgCategory>[];
  for (final rawCategory in jsonList(data['categories'])) {
    if (rawCategory is! Map) continue;
    final category = jsonMap(rawCategory);
    if (jsonBool(category['isWeb'])) continue;
    final title = jsonString(category['title']).trim();
    final key = jsonString(
      category['_id'] ?? category['id'] ?? category['title'],
    ).trim();
    if (key.isEmpty || title.isEmpty) continue;
    categories.add(
      PicacgCategory(
        key: key,
        title: title,
        param: title,
        cover: _picacgMediaUrl(category['thumb']),
      ),
    );
  }
  return categories;
}

/// Resolves max page only from explicit metadata or an unambiguous empty page.
int? picacgMaxPage({
  required int currentPage,
  required int itemCount,
  int? pageCount,
  int? total,
  int? pageSize,
}) {
  final page = currentPage < 1 ? 1 : currentPage;
  if (pageCount != null && pageCount > 0) {
    return pageCount < page ? page : pageCount;
  }
  if (itemCount == 0) return page;
  if (total == null || total <= 0 || pageSize == null || pageSize <= 0) {
    return null;
  }
  final calculated = (total + pageSize - 1) ~/ pageSize;
  return calculated < page ? page : calculated;
}

String? _picacgMediaUrl(Object? value) {
  if (value is String) {
    final url = value.trim();
    return url.isEmpty ? null : url;
  }
  final media = jsonMap(value);
  final fileServer = jsonString(media['fileServer']).trim();
  final path = jsonString(media['path']).trim();
  if (fileServer.isEmpty || path.isEmpty) return null;
  return '$fileServer/static/$path';
}

Res<CommentPageData> parsePicacgCommentPage(
  Object? value, {
  required int requestedPage,
}) {
  if (value is! Map || requestedPage < 1) {
    return _picacgCommentParseFailure();
  }
  final root = jsonMap(value);
  if (root['data'] is! Map) return _picacgCommentParseFailure();
  final data = jsonMap(root['data']);
  if (data['comments'] is! Map) return _picacgCommentParseFailure();
  final commentsData = jsonMap(data['comments']);
  if (commentsData['docs'] is! List ||
      !commentsData.containsKey('total') ||
      !commentsData.containsKey('pages')) {
    return _picacgCommentParseFailure();
  }

  final totalComments = _parsePicacgCommentInteger(commentsData['total']);
  final totalPages = _parsePicacgCommentInteger(commentsData['pages']);
  if (totalComments == null ||
      totalComments < 0 ||
      totalPages == null ||
      totalPages < 1) {
    return _picacgCommentParseFailure();
  }

  var page = requestedPage;
  if (commentsData.containsKey('page')) {
    final parsedPage = _parsePicacgCommentInteger(commentsData['page']);
    if (parsedPage == null || parsedPage < 1) {
      return _picacgCommentParseFailure();
    }
    page = parsedPage;
  }
  if (page > totalPages) return _picacgCommentParseFailure();

  final rawComments = jsonList(commentsData['docs']);
  if (rawComments.any(
    (comment) => comment is! Map || !_hasValidPicacgReplies(jsonMap(comment)),
  )) {
    return _picacgCommentParseFailure();
  }
  final comments = <Comment>[
    for (final rawComment in rawComments)
      _parsePicacgComment(jsonMap(rawComment)),
  ];
  if (comments.length > totalComments) return _picacgCommentParseFailure();

  return Res<CommentPageData>(
    CommentPageData(
      comments: comments,
      page: page,
      totalPages: totalPages,
      totalComments: totalComments,
    ),
  );
}

Res<CommentPageData> _picacgCommentParseFailure() =>
    const Res<CommentPageData>(null, errorMessage: '评论解析失败');

int? _optionalPicacgInteger(Object? value) {
  if (value == null) return null;
  final parsed = _parsePicacgCommentInteger(value);
  return parsed == null || parsed < 0 ? null : parsed;
}

int? _parsePicacgCommentInteger(Object? value) {
  if (value is int) return value;
  if (value is num) {
    if (!value.isFinite || value != value.truncateToDouble()) return null;
    return value.toInt();
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

bool _hasValidPicacgReplies(Map<String, dynamic> comment) {
  for (final key in const <String>['childrens', 'replies']) {
    if (!comment.containsKey(key) || comment[key] == null) continue;
    final value = comment[key];
    if (value is! List) return false;
    for (final rawReply in value) {
      if (rawReply is! Map || !_hasValidPicacgReplies(jsonMap(rawReply))) {
        return false;
      }
    }
  }
  return true;
}

Comment _parsePicacgComment(Map<String, dynamic> comment) {
  final user = jsonMap(comment['_user']);
  final commentId = jsonString(comment['_id'] ?? comment['id']).trim();
  final time = jsonString(comment['created_at']).trim();
  final rawReplies = comment['childrens'] ?? comment['replies'];
  final replies = <Comment>[
    for (final rawReply in jsonList(rawReplies))
      if (rawReply is Map) _parsePicacgComment(jsonMap(rawReply)),
  ];

  return Comment.snapshot(
    jsonString(user['name'], fallback: 'Unknown'),
    user['avatar'] == null ? null : _picacgMediaUrl(user['avatar']),
    jsonString(comment['content']),
    time.isEmpty ? null : time,
    jsonInt(
      comment['commentsCount'] ??
          comment['replyCount'] ??
          comment['reply_count'],
      fallback: replies.length,
    ),
    commentId.isEmpty ? null : commentId,
    jsonInt(comment['likesCount'] ?? comment['likeCount'] ?? comment['likes']),
    jsonBool(comment['isLiked'] ?? comment['liked']),
    replies,
  );
}

/// 哔咔网络请求类。
typedef PicacgDioFactory = Dio Function(BaseOptions options);
typedef PicacgGetRequest =
    Future<Res<Map<String, dynamic>>> Function(String url);
typedef PicacgPostRequest =
    Future<Res<Map<String, dynamic>>> Function(
      String url,
      Map<String, String>? data,
    );

class PicacgLoginResult {
  const PicacgLoginResult({required this.token, required this.apiBaseUrl});

  final String token;
  final String apiBaseUrl;
}

class PicacgNetwork {
  PicacgNetwork._create({
    PicacgDioFactory? dioFactory,
    PicacgGetRequest? getRequest,
    PicacgPostRequest? postRequest,
  }) : _dioFactory = dioFactory ?? Dio.new,
       _getRequest = getRequest,
       _postRequest = postRequest;

  static PicacgNetwork? _cache;

  factory PicacgNetwork({
    PicacgDioFactory? dioFactory,
    PicacgGetRequest? getRequest,
    PicacgPostRequest? postRequest,
  }) {
    if (dioFactory == null && getRequest == null && postRequest == null) {
      return _cache ??= PicacgNetwork._create();
    }
    return PicacgNetwork._create(
      dioFactory: dioFactory,
      getRequest: getRequest,
      postRequest: postRequest,
    );
  }

  final PicacgDioFactory _dioFactory;
  final PicacgGetRequest? _getRequest;
  final PicacgPostRequest? _postRequest;
  Future<void> _authenticationQueue = Future<void>.value();
  Future<bool>? _reLoginFuture;
  static final Object _authenticationOwnerKey = Object();

  bool get isInAuthenticationOperation =>
      identical(Zone.current[_authenticationOwnerKey], this);

  Future<T> runAuthenticationOperation<T>(Future<T> Function() operation) {
    if (isInAuthenticationOperation) return operation();
    final previous = _authenticationQueue;
    final turn = Completer<void>();
    _authenticationQueue = turn.future;
    return () async {
      await previous;
      try {
        return await runZoned<Future<T>>(
          operation,
          zoneValues: <Object?, Object?>{_authenticationOwnerKey: this},
        );
      } finally {
        turn.complete();
      }
    }();
  }

  /// 由源注册流程在初始化时注入状态门面。
  PicacgState? state;

  /// 当前生效的接入域名（go2778/picacomic 二选一，默认 go2778 中转）。
  String get apiUrl => (state?.apiBaseUrl.isNotEmpty ?? false)
      ? state!.apiBaseUrl
      : defaultPicacgApiUrl;

  String get _token => state?.token ?? '';

  // ============================ 通用 GET / POST ============================

  Future<Res<Map<String, dynamic>>> get(
    String url, {
    bool useCache = false,
  }) async {
    final injectedRequest = _getRequest;
    if (injectedRequest != null) return injectedRequest(url);
    return request('GET', Uri.parse(url));
  }

  Future<Res<Map<String, dynamic>>> post(
    String url,
    Map<String, String>? data,
  ) async {
    final injectedRequest = _postRequest;
    if (injectedRequest != null) return injectedRequest(url, data);
    return request('POST', Uri.parse(url), data: data);
  }

  Future<Res<Map<String, dynamic>>> request(
    String method,
    Uri uri, {
    Map<String, String>? data,
    bool requiresAuth = true,
    bool allowRelogin = true,
    bool retried = false,
  }) async {
    if (requiresAuth && _token.isEmpty) {
      return const Res(null, errorMessage: '未登录');
    }

    final requestBaseUrl = apiUrl;
    final dio = _dioFactory(_buildOptions(method, _token, uri));
    dio.options.validateStatus = (status) =>
        status == 200 || status == 400 || status == 401;
    try {
      final response = await dio.request<String>(
        uri.toString(),
        data: data,
        options: Options(method: method),
      );
      if (response.statusCode == 401 &&
          requiresAuth &&
          allowRelogin &&
          !retried &&
          !isInAuthenticationOperation) {
        final reloggedIn = await _reLoginOnce();
        if (!reloggedIn) {
          return const Res(null, errorMessage: '登录失效且重新登录失败');
        }
        return request(
          method,
          _rebaseApiUri(uri, fromBaseUrl: requestBaseUrl),
          data: data,
          requiresAuth: requiresAuth,
          allowRelogin: false,
          retried: true,
        );
      }
      final result = _handle(response);
      if (result.error) {
        Log.w(
          'Pica $method fail',
          error: '${uri.path} → ${result.errorMessage}',
        );
      } else {
        Log.d('Pica $method', uri.path);
      }
      return result;
    } on DioException catch (error) {
      final message = _dioErrMsg(error);
      Log.e('Pica $method error', error: '${uri.path} → $message');
      return Res(null, errorMessage: message);
    } catch (error) {
      Log.e('Pica $method error', error: '${uri.path} → $error');
      return Res(null, errorMessage: error.toString());
    }
  }

  BaseOptions _buildOptions(String method, String token, Uri uri) {
    final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    final signedPath = uri.hasQuery ? '$path?${uri.query}' : path;
    return buildHeaders(
      method: method,
      token: token,
      urlPath: signedPath,
      channel: state?.channel ?? '3',
      imageQuality: state?.imageQuality ?? 'original',
    );
  }

  Uri _rebaseApiUri(Uri uri, {required String fromBaseUrl}) {
    final from = Uri.parse(fromBaseUrl);
    final knownOrigins = <String>{
      from.origin,
      for (final base in picacgApiHosts.values) Uri.parse(base).origin,
    };
    if (!knownOrigins.contains(uri.origin)) return uri;
    final current = Uri.parse(apiUrl);
    return uri.replace(
      scheme: current.scheme,
      host: current.host,
      port: current.hasPort ? current.port : null,
    );
  }

  Res<Map<String, dynamic>> _handle(Response<String> response) {
    if (response.data == null) {
      return const Res(null, errorMessage: 'Empty data');
    }
    Object? decoded;
    try {
      decoded = convert.jsonDecode(response.data!);
    } on FormatException {
      return const Res(null, errorMessage: '响应结构错误');
    }
    if (decoded is! Map) {
      return const Res(null, errorMessage: '响应结构错误');
    }
    final json = jsonMap(decoded);
    if (response.statusCode == 200) return Res(json);
    if (response.statusCode == 400) {
      return Res(
        null,
        errorMessage: jsonString(json['message'], fallback: '请求错误'),
      );
    }
    if (response.statusCode == 401) {
      return Res(
        null,
        errorMessage: jsonString(json['message'], fallback: '未授权'),
      );
    }
    return Res(
      null,
      errorMessage: 'Invalid Status Code ${response.statusCode}',
    );
  }

  Future<bool> _reLoginOnce() {
    final active = _reLoginFuture;
    if (active != null) return active;
    final future = runAuthenticationOperation(() async {
      try {
        return await (state?.reLogin() ?? Future<bool>.value(false));
      } catch (error) {
        Log.e('Pica re-login error', error: error.toString());
        return false;
      }
    });
    _reLoginFuture = future;
    return future.whenComplete(() {
      if (identical(_reLoginFuture, future)) _reLoginFuture = null;
    });
  }

  String _dioErrMsg(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout) return '连接超时';
    if (error.type == DioExceptionType.sendTimeout) return '发送超时';
    if (error.type == DioExceptionType.receiveTimeout) return '接收超时';
    return error.message ?? error.toString().split('\n').first;
  }

  String _mediaUrl(Object? value, {String fallback = ''}) =>
      _picacgMediaUrl(value) ?? fallback;

  // ============================ 业务端点 ============================

  /// 登录成功返回 token 与实际成功的 API 接入点。
  Future<Res<PicacgLoginResult>> login(String email, String password) async {
    Res<Map<String, dynamic>>? lastFailure;
    final candidates = <String>{
      apiUrl,
      picacgApiHosts['picacomic']!,
      picacgApiHosts['go2778']!,
    };
    for (final base in candidates) {
      final uri = Uri.parse('$base/auth/sign-in');
      final response = await request(
        'POST',
        uri,
        data: {'email': email, 'password': password},
        requiresAuth: false,
        allowRelogin: false,
      );
      if (response.error) {
        lastFailure = response;
        continue;
      }
      final message = jsonString(response.data['message']);
      final token = jsonString(jsonMap(response.data['data'])['token']);
      if ((message == 'success' || message.isEmpty) && token.isNotEmpty) {
        return Res(PicacgLoginResult(token: token, apiBaseUrl: base));
      }
      lastFailure = Res(
        null,
        errorMessage: message.isEmpty ? 'Failed to get token' : message,
      );
    }
    return Res(null, errorMessage: lastFailure?.errorMessage ?? '登录失败');
  }

  /// 用户档案。
  Future<Res<Profile>> getProfile() async {
    final response = await get('$apiUrl/users/profile');
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final user = jsonMap(jsonMap(response.data['data'])['user']);
    final id = jsonString(user['_id'] ?? user['id']);
    if (id.isEmpty) {
      return const Res(null, errorMessage: '用户档案解析失败');
    }
    final avatar = user['avatar'] == null
        ? defaultAvatarUrl
        : _mediaUrl(user['avatar'], fallback: defaultAvatarUrl);
    return Res(
      Profile.fromJson(<String, dynamic>{
        ...user,
        'id': id,
        'avatarUrl': avatar,
        'frameUrl': user['character'],
      }),
    );
  }

  /// 热门搜索词。
  Future<Res<List<String>>> getHotTags() async {
    final response = await get('$apiUrl/keywords');
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final data = jsonMap(response.data['data']);
    return Res(jsonStringList(data['keywords']));
  }

  /// 获取分类。分类筛选参数使用服务端 title，稳定 key 优先使用 id。
  Future<Res<List<PicacgCategory>>> getCategories() async {
    final response = await get('$apiUrl/categories');
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final data = jsonMap(response.data['data']);
    if (data['categories'] is! List) {
      return const Res(null, errorMessage: '分类解析失败');
    }
    return Res(parsePicacgCategories(response.data));
  }

  /// 获取分类漫画；category 为空时返回全站漫画，可用于首页分区。
  Future<Res<List<ComicItemBrief>>> getCategoryComics(
    String category,
    int page,
    String sort,
  ) async {
    final uri = Uri.parse('$apiUrl/comics').replace(
      queryParameters: {
        'page': page.toString(),
        if (category.trim().isNotEmpty) 'c': category.trim(),
        's': sort,
      },
    );
    final response = await get(uri.toString());
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final comicsData = jsonMap(jsonMap(response.data['data'])['comics']);
    if (comicsData.isEmpty) {
      return const Res(null, errorMessage: '分类漫画解析失败');
    }
    final docs = jsonList(comicsData['docs']);
    final comics = <ComicItemBrief>[];
    for (final rawComic in docs) {
      if (rawComic is! Map) continue;
      final comic = ComicItemBrief.fromJson(jsonMap(rawComic));
      if (comic.id.isEmpty) continue;
      comics.add(comic);
    }
    final rawPageCount = jsonInt(
      comicsData['pages'] ??
          comicsData['page_count'] ??
          comicsData['total_page'],
    );
    final rawTotal = jsonInt(comicsData['total']);
    final rawPageSize = jsonInt(
      comicsData['page_size'] ?? comicsData['pageSize'] ?? comicsData['limit'],
    );
    return Res(
      comics,
      subData: picacgMaxPage(
        currentPage: page,
        itemCount: docs.length,
        pageCount: rawPageCount > 0 ? rawPageCount : null,
        total: rawTotal > 0 ? rawTotal : null,
        pageSize: rawPageSize > 0 ? rawPageSize : null,
      ),
    );
  }

  /// 高级搜索。[passed] subData 承载 maxPage。
  /// [sort] 排序，'ua'（默认）/'aa'/'dd'。
  Future<Res<List<ComicItemBrief>>> search(
    String keyword,
    String sort,
    int page,
  ) async {
    final response = await post('$apiUrl/comics/advanced-search?page=$page', {
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
    final response = await get('$apiUrl/comics/$id');
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final epsRes = await getEps(id);
    if (epsRes.error) return Res(null, errorMessage: epsRes.errorMessage);
    final recRes = await getRecommendation(id);
    final comic = jsonMap(jsonMap(response.data['data'])['comic']);
    if (comic.isEmpty) {
      return const Res(null, errorMessage: '漫画详情解析失败');
    }
    final creator = jsonMap(comic['_creator']);
    return Res(
      ComicItem(
        id: jsonString(comic['_id'], fallback: id),
        title: jsonString(comic['title'], fallback: 'Unknown'),
        author: jsonString(
          creator['name'] ?? comic['author'],
          fallback: 'Unknown',
        ),
        description: jsonString(comic['description']),
        thumbUrl: _mediaUrl(comic['thumb']),
        chineseTeam: jsonString(comic['chineseTeam']),
        categories: jsonStringList(comic['categories']),
        tags: jsonStringList(comic['tags']),
        views: _optionalPicacgInteger(
          comic['viewsCount'] ?? comic['totalViews'] ?? comic['views'],
        ),
        likes: jsonInt(
          comic['likesCount'] ?? comic['totalLikes'] ?? comic['likes'],
        ),
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
      ),
    );
  }

  /// 获取章节列表。服务端序为倒序，这里按 order 升序整理返回。
  Future<Res<List<PicacgEpisode>>> getEps(String id) async {
    final episodes = <PicacgEpisode>[];
    var page = 0;
    try {
      while (true) {
        page++;
        final res = await get('$apiUrl/comics/$id/eps?page=$page');
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
        final res = await get(
          '$apiUrl/comics/$id/order/$order/pages?page=$page',
        );
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
    final res = await get('$apiUrl/comics/$id/recommendation');
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
    final res = await get('$apiUrl/users/favourite?s=$sort&page=$page');
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
    final res = await post('$apiUrl/comics/$id/favourite', {});
    if (res.error) return Res(null, errorMessage: res.errorMessage);
    return const Res(true);
  }

  /// 获取类型化评论分页数据。
  Future<Res<CommentPageData>> getComments(
    String id, {
    int page = 1,
    String type = 'comics',
  }) async {
    final res = await get('$apiUrl/$type/$id/comments?page=$page');
    if (res.error) {
      return Res<CommentPageData>(null, errorMessage: res.errorMessage);
    }
    return parsePicacgCommentPage(res.dataOrNull, requestedPage: page);
  }

  /// 获取指定顶级评论的子评论分页。
  Future<Res<CommentPageData>> getCommentChildren(
    String commentId, {
    int page = 1,
  }) async {
    final res = await get('$apiUrl/comments/$commentId/childrens?page=$page');
    if (res.error) {
      return Res<CommentPageData>(null, errorMessage: res.errorMessage);
    }
    return parsePicacgCommentPage(res.dataOrNull, requestedPage: page);
  }

  /// 向漫画发表评论。
  Future<Res<bool>> sendComment(String comicId, String content) =>
      _sendCommentRequest('$apiUrl/comics/$comicId/comments', content);

  /// 回复指定评论。
  Future<Res<bool>> replyComment(String commentId, String content) =>
      _sendCommentRequest('$apiUrl/comments/$commentId', content);

  Future<Res<bool>> _sendCommentRequest(String url, String content) async {
    final normalized = content.trim();
    if (normalized.isEmpty) {
      return const Res<bool>(null, errorMessage: '评论内容不能为空');
    }
    final res = await post(url, <String, String>{'content': normalized});
    if (res.error) return Res<bool>(null, errorMessage: res.errorMessage);
    return const Res<bool>(true);
  }
}
