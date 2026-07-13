/// 哔咔网络请求单例。
///
/// 端点与解析对齐哔咔 API：登录取 token、分类、高级搜索、漫画详情、
/// 章节/分章图片、收藏切换等。所有请求经 [PicacgHeaders.buildHeaders]
/// 签名；遇 401 自动用已存账密重登并重试一次（避免登录态失效打回登录页）。
library picacg_network;

import 'dart:convert' as convert;

import 'package:dio/dio.dart';

import '../res.dart';
import '../base_comic.dart';
import '../../foundation/log.dart';
import 'picacg_headers.dart';
import 'picacg_models.dart';
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
    if (res.statusCode == 200) {
      return Res(convert.jsonDecode(res.data!) as Map<String, dynamic>);
    } else if (res.statusCode == 400) {
      final json = convert.jsonDecode(res.data!) as Map<String, dynamic>;
      return Res(null, errorMessage: json['message'] ?? '请求错误');
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

  // ============================ 业务端点 ============================

  /// 登录成功返回 token。
  Future<Res<String>> login(String email, String password) async {
    final response = await post('${apiUrl}/auth/sign-in', {
      'email': email,
      'password': password,
    });
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final res = response.data;
    if (res['message'] == 'success') {
      try {
        return Res(res['data']['token']);
      } catch (e) {
        return const Res(null, errorMessage: 'Failed to get token');
      }
    }
    return Res(null, errorMessage: res['message']);
  }

  /// 用户档案。
  Future<Res<Profile>> getProfile() async {
    final response = await get('${apiUrl}/users/profile');
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final u = response.data['data']['user'];
    String url;
    if (u['avatar'] == null) {
      url = defaultAvatarUrl;
    } else {
      url = u['avatar']['fileServer'] + '/static/' + u['avatar']['path'];
    }
    return Res(Profile(
      id: u['_id'] ?? '',
      avatarUrl: url,
      email: u['email'] ?? '',
      exp: u['exp'] ?? 0,
      level: u['level'] ?? 0,
      name: u['name'] ?? '',
      title: u['title'] ?? '',
      isPunched: u['isPunched'],
      slogan: u['slogan'],
      frameUrl: u['character'],
    ));
  }

  /// 热门搜索词。
  Future<Res<List<String>>> getHotTags() async {
    final response = await get('${apiUrl}/keywords');
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final list = <String>[];
    final k = response.data['data']['keywords'] ?? [];
    for (int i = 0; i < k.length; i++) {
      list.add(k[i]);
    }
    return Res(list);
  }

  /// 获取首页分类。跳过 web 专属分类。
  Future<Res<List<CategoryItem>>> getCategories() async {
    final response = await get('${apiUrl}/categories');
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final items = <CategoryItem>[];
    final cats = response.data['data']['categories'] ?? [];
    for (final c in cats) {
      if (c['isWeb'] == true) continue;
      final thumb = c['thumb'] ?? {};
      var url = thumb['fileServer'] ?? '';
      final path = thumb['path'] ?? '';
      url = url.endsWith('/') ? '$url$path' : '$url/static/$path';
      items.add(CategoryItem(c['title'] ?? '', url));
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
    final data = response.data['data']['comics'];
    final pages = data['pages'] ?? 1;
    final comics = <ComicItemBrief>[];
    for (final doc in data['docs'] ?? []) {
      try {
        final tags = <String>[];
        tags.addAll(List<String>.from(doc['tags'] ?? []));
        tags.addAll(List<String>.from(doc['categories'] ?? []));
        comics.add(ComicItemBrief(
          title: doc['title'] ?? 'Unknown',
          author: doc['author'] ?? 'Unknown',
          likes: int.tryParse('${doc['likesCount']}') ?? 0,
          coverPath: doc['thumb']['fileServer'] +
              '/static/' +
              doc['thumb']['path'],
          id: doc['_id'],
          tags: tags,
          pages: doc['pagesCount'],
        ));
      } catch (e) {
        continue;
      }
    }
    return Res(comics, subData: pages);
  }

  /// 漫画详情：合并详情 + 章节 + 推荐。
  Future<Res<ComicItem>> getComicInfo(String id) async {
    final response = await get('${apiUrl}/comics/$id');
    if (response.error) return Res(null, errorMessage: response.errorMessage);
    final epsRes = await getEps(id);
    if (epsRes.error) return Res(null, errorMessage: epsRes.errorMessage);
    final recRes = await getRecommendation(id);
    final comic = response.data['data']['comic'];
    final creatorSrc = comic['_creator'];
    String avatar;
    if (creatorSrc['avatar'] == null) {
      avatar = defaultAvatarUrl;
    } else {
      avatar = creatorSrc['avatar']['fileServer'] +
          '/static/' +
          creatorSrc['avatar']['path'];
    }
    final item = ComicItem(
      id: comic['_id'] ?? id,
      title: comic['title'] ?? 'Unknown',
      author: creatorSrc['name'] ?? 'Unknown',
      description: comic['description'] ?? '',
      thumbUrl: comic['thumb']['fileServer'] + '/static/' + comic['thumb']['path'],
      chineseTeam: comic['chineseTeam'] ?? '',
      categories: List<String>.from(comic['categories'] ?? []),
      tags: List<String>.from(comic['tags'] ?? []),
      likes: comic['likesCount'] ?? 0,
      comments: comic['commentsCount'] ?? 0,
      isLiked: comic['isLiked'] ?? false,
      isFavourite: comic['isFavourite'] ?? false,
      epsCount: comic['epsCount'] ?? 0,
      pagesCount: comic['pagesCount'] ?? 0,
      time: comic['created_at'] ?? '',
      episodes: epsRes.data,
      recommendation: recRes.error ? [] : recRes.data,
    );
    return Res(item);
  }

  /// 获取章节列表。服务端序为倒序，这里按 order 升序整理返回。
  Future<Res<List<PicacgEpisode>>> getEps(String id) async {
    final eps = <PicacgEpisode>[];
    int i = 0;
    try {
      while (true) {
        i++;
        final res = await get('${apiUrl}/comics/$id/eps?page=$i');
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        final epsRoot = res.data['data']['eps'];
        final lastPage = epsRoot['pages'] ?? 1;
        for (final doc in epsRoot['docs'] ?? []) {
          final order = doc['order'] ?? 0;
          final title = doc['title'];
          eps.add(PicacgEpisode(
            title: (title == null || (title as String).isEmpty)
                ? '第$order'
                : title,
            order: order,
          ));
        }
        if (lastPage == i) break;
      }
    } catch (e) {
      return Res(null, errorMessage: e.toString());
    }
    eps.sort((a, b) => a.order.compareTo(b.order));
    return Res(eps);
  }

  /// 获取某章节的全部图片 URL，分页聚合。
  Future<Res<List<String>>> getComicContent(String id, int order) async {
    final urls = <String>[];
    int i = 0;
    try {
      while (true) {
        i++;
        final res = await get('${apiUrl}/comics/$id/order/$order/pages?page=$i');
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        final pages = res.data['data']['pages'];
        if ((pages['pages'] ?? 1) == i) {
          for (final doc in pages['docs'] ?? []) {
            final media = doc['media'];
            urls.add('${media['fileServer']}/static/${media['path']}');
          }
          break;
        }
        for (final doc in pages['docs'] ?? []) {
          final media = doc['media'];
          urls.add('${media['fileServer']}/static/${media['path']}');
        }
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
    final comics = <ComicItemBrief>[];
    for (final doc in res.data['data']['comics'] ?? []) {
      try {
        comics.add(ComicItemBrief(
          title: doc['title'] ?? 'Unknown',
          author: doc['author'] ?? '',
          likes: doc['likesCount'] ?? 0,
          coverPath: doc['thumb']['fileServer'] + '/static/' + doc['thumb']['path'],
          id: doc['_id'],
        ));
      } catch (e) {
        continue;
      }
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
    final comics = <BaseComic>[];
    final docs = res.dataOrNull?['data']?['comics']?['docs'] ?? [];
    for (final doc in docs) {
      final tags = <String>[];
      if (doc['tags'] is List) tags.addAll(List<String>.from(doc['tags']));
      if (doc['categories'] is List) tags.addAll(List<String>.from(doc['categories']));
      comics.add(ComicItemBrief(
        title: doc['title'] ?? 'Unknown',
        id: doc['_id'] ?? '',
        author: doc['author'] ?? '',
        coverPath: doc['thumb']?.toString() ?? doc['cover']?.toString() ?? '',
        tags: tags,
        likes: doc['totalLikes'] ?? 0,
      ));
    }
    final maxPage = res.dataOrNull?['data']?['comics']?['pages'] ?? 1;
    return Res<List<BaseComic>>(comics, subData: maxPage);
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
    final data = res.dataOrNull;
    final docs = data?['data']?['comments']?['docs'] ?? [];
    final pages = data?['data']?['comments']?['pages'] ?? 1;
    final list = docs.map<Map<String, dynamic>>((d) {
      final user = d['_user'] ?? {};
      final avatar = user['avatar'] != null
          ? '${user['avatar']['fileServer']}/static/${user['avatar']['path']}'
          : null;
      return {
        'id': d['_id']?.toString(),
        'avatar': avatar,
        'userName': user['name'] ?? 'Unknown',
        'content': d['content'] ?? '',
        'time': d['created_at']?.toString(),
        'replyCount': d['commentsCount'] ?? 0,
      };
    }).toList();
    return Res(list, subData: pages);
  }
}
