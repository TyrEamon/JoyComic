/// 哔咔源的内置声明与状态绑定。
///
/// 把 [PicacgNetwork] 与 [ComicSource] 契约连接起来：构造一个状态门面
/// [PicacgStateImpl] 桥接源运行期 `data`，注入到网络层；并声明账号登录流。
/// 分类/搜索/探索页/收藏等较高层字段在阶段2/3 逐步补全，此处仅保留可登录
/// 的最小骨架，确保整条鉴权链路可运行。
library built_in_picacg;

import 'dart:collection';

import '../../comic_source/comic_source.dart';
import '../../network/base_comic.dart';
import '../../network/picacg/picacg_network.dart';
import '../../network/res.dart';
import '../../network/source_state.dart';

/// 哔咔源状态门面实现：从 [ComicSource.data] 读写 token / channel / 图片质量 / 接入域名。
class PicacgStateImpl implements PicacgState {
  final ComicSource source;
  PicacgStateImpl(this.source);

  @override
  String get token => source.data['token'] ?? '';

  @override
  String get channel => source.data['appChannel'] ?? '3';

  @override
  String get imageQuality => source.data['imageQuality'] ?? 'original';

  @override
  String get apiBaseUrl =>
      source.data['apiBaseUrl'] ?? defaultPicacgApiUrl;

  @override
  void setApiBaseUrl(String url) {
    source.data['apiBaseUrl'] = url;
    source.saveData();
  }

  @override
  List<String>? getAccount() => source.data['account'] as List<String>?;

  @override
  Future<bool> reLogin() => source.reLogin();
}

/// 哔咔内置源声明。
ComicSource buildPicacgSource() {
  final source = ComicSource.named(
    name: '哔咔',
    key: 'picacg',
    filePath: 'built-in',
    url: 'https://picaapi.go2778.com',
    version: '2.2.1.3.3.4',
    account: AccountConfig.named(
      login: (account, pwd) async {
        final network = PicacgNetwork();
        final res = await network.login(account, pwd);
        if (res.error) return Res.fromErrorRes(res);
        final s = ComicSource.find('picacg')!;
        s.data['token'] = res.data;
        final profile = await network.getProfile();
        if (profile.error) {
          s.data['token'] = null;
          return Res.fromErrorRes(profile);
        }
        s.data['user'] = _profileToMap(profile.data);
        s.data['account'] = <String>[account, pwd];
        await s.saveData();
        return const Res(true);
      },
      logout: () {
        final s = ComicSource.find('picacg');
        if (s == null) return;
        s.data['user'] = null;
        s.data['token'] = null;
        s.saveData();
      },
      loginWebsite: 'https://picacomic.com',
    ),
    // 哔咔搜索：高级搜索，sort='ua' 默认排序。
    searchPageData: SearchPageData.named(
      loadPage: (keyword, page, options) async {
        final res = await PicacgNetwork().search(keyword, 'ua', page);
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return Res<List<BaseComic>>(res.data.cast<BaseComic>(),
            subData: res.subData);
      },
      enableTagsSuggestions: true,
      loadHotTags: () => PicacgNetwork().getHotTags(),
    ),
    // 详情：ComicItem → ComicInfoData 统一形态。
    loadComicInfo: (id) async {
      final res = await PicacgNetwork().getComicInfo(id);
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return Res(_picacgItemToComicInfoData(res.data));
    },
    // 章节图：ep 为 PicacgEpisode.order（章节序号，整数）。
    loadComicPages: (comicId, ep) async {
      final order = int.tryParse(ep ?? '1') ?? 1;
      final res = await PicacgNetwork().getComicContent(comicId, order);
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return Res(res.data);
    },
    // 哔咔图片（封面/内文）无额外鉴权头，走默认 dio 即可。
    getImageLoadingConfig: null,
    getThumbnailLoadingConfig: null,
    // 分类。
    categoryData: CategoryData.named(
      title: '哔咔分类',
      key: 'picacg',
      categories: [
        FixedCategoryPart('全部', [
          '恋爱', '校园', '科幻', '奇幻', '悬疑', '搞笑',
          '百合', '伪娘', '同人', '单本', '短篇', '完结',
        ], 'category'),
      ],
      enableRankingPage: true,
    ),
    categoryComicsData: CategoryComicsData.named(
      options: [
        CategoryComicsOptions.named(
          options: LinkedHashMap.from({'category': '类别'}),
        ),
      ],
      load: (category, param, options, page) async {
        // 哔咔分类搜索
        final res = await PicacgNetwork().search(category, 'ua', page);
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return Res<List<BaseComic>>(res.data.cast<BaseComic>(),
            subData: res.subData);
      },
    ),
    // 收藏。
    favoriteData: FavoriteData.named(
      load: (page, [folder]) async {
        final res = await PicacgNetwork().getFavorites(page, true);
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return Res<List<BaseComic>>(res.data.cast<BaseComic>(),
            subData: res.subData);
      },
      addOrDelFavorite: (comicId, folderId, isAdding) async {
        final res = await PicacgNetwork().favouriteOrUnfavourite(comicId);
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return const Res(true);
      },
      multiFolder: false,
    ),
    // 评论。
    commentsLoader: (id, subId, page, replyTo) async {
      final res = await PicacgNetwork().getComments(id, page: page);
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      final comments = res.data.map((m) => Comment(
        m['userName'] as String? ?? '',
        m['avatar'] as String?,
        m['content'] as String? ?? '',
        m['time'] as String?,
        m['replyCount'] as int? ?? 0,
        m['id'] as String?,
      )).toList();
      return Res(comments);
    },
    initData: (s) {
      s.data['appChannel'] ??= '3';
      s.data['imageQuality'] ??= 'original';
      // 默认接入 go2778 中转源；用户可在设置切换为 picacomic 直连。
      s.data['apiBaseUrl'] ??= defaultPicacgApiUrl;
    },
  );

  // 注入状态门面并注册到内置表。
  PicacgNetwork()..state = PicacgStateImpl(source);
  return source;
}

Map<String, dynamic> _profileToMap(Profile p) => {
      'id': p.id,
      'email': p.email,
      'name': p.name,
      'level': p.level,
      'exp': p.exp,
      'avatarUrl': p.avatarUrl,
      'title': p.title,
      'slogan': p.slogan,
    };

/// 哔咔详情 → 统一 [ComicInfoData]。
///
/// 章节映射：episodes（order→title）→ {order: title}，epId = order.toString()
/// 供 loadComicPages 调用。tags 含作者/分类/汉化组 + 热度/收藏数值化。
ComicInfoData _picacgItemToComicInfoData(ComicItem info) {
  final chapters = <String, String>{};
  for (final ep in info.episodes) {
    chapters[ep.order.toString()] = ep.title;
  }
  return ComicInfoData(
    title: info.title,
    subTitle: info.author,
    cover: info.cover,
    description: info.description,
    tags: {
      '作者': [info.author],
      if (info.chineseTeam.isNotEmpty) '汉化组': [info.chineseTeam],
      '标签': info.categories,
      '热度': [_formatCount(info.likes)],
      '评价人数': [_formatCount(info.comments)],
    },
    chapters: chapters,
    thumbnails: null,
    suggestions: info.recommendation.cast<BaseComic>(),
    sourceKey: 'picacg',
    comicId: info.id,
    isFavorite: info.isFavourite,
  );
}

/// 数值量化：>=1 亿显示"X.X 亿"，>=1 万显示"X.X 万"，否则原数。
String _formatCount(int n) {
  if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
  return n.toString();
}
