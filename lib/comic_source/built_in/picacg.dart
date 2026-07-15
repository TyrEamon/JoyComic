/// 哔咔源的内置声明与状态绑定。
///
/// 把 [PicacgNetwork] 与 [ComicSource] 契约连接起来：构造一个状态门面
/// [PicacgStateImpl] 桥接源运行期 `data`，注入到网络层；并声明账号登录流。
/// 分类、分页和首页分区通过源中立契约暴露，网络请求仍复用源内鉴权状态。
library;

import '../../comic_source/comic_source.dart';
import '../../network/base_comic.dart';
import '../../network/json_value.dart';
import '../../network/picacg/picacg_network.dart';
import '../../network/res.dart';
import '../../network/source_state.dart';
import '../../views/common/source_content_models.dart';

/// 哔咔源状态门面实现：从 [ComicSource.data] 读写 token / channel / 图片质量 / 接入域名。
class PicacgStateImpl implements PicacgState {
  final ComicSource source;
  PicacgStateImpl(this.source);

  @override
  String get token => jsonString(source.data['token']);

  @override
  String get channel => jsonString(source.data['appChannel'], fallback: '3');

  @override
  String get imageQuality =>
      jsonString(source.data['imageQuality'], fallback: 'original');

  @override
  String get apiBaseUrl =>
      jsonString(source.data['apiBaseUrl'], fallback: defaultPicacgApiUrl);

  @override
  void setApiBaseUrl(String url) {
    source.data['apiBaseUrl'] = url;
    source.saveData();
  }

  @override
  List<String>? getAccount() => _storedAccount(source.data['account']);

  @override
  Future<bool> reLogin() => source.reLogin();
}

typedef PicacgHomePageLoader =
    Future<Res<List<BaseComic>>> Function(String sort);

const _picacgHomeSections = <({String key, String title, String sort})>[
  (key: 'latest', title: '最新漫画', sort: 'dd'),
  (key: 'popular', title: '热门漫画', sort: 'ld'),
  (key: 'recommended', title: '推荐漫画', sort: 'ua'),
];

/// Loads independent Picacg home feeds and keeps every successful section.
Future<Res<List<SourceContentSection>>> loadPicacgHomeSections(
  PicacgHomePageLoader loadPage,
) async {
  final results = await Future.wait([
    for (final section in _picacgHomeSections)
      _loadPicacgHomeSection(section, loadPage),
  ]);
  final sections = <SourceContentSection>[];
  final errors = <String>[];
  for (final result in results) {
    if (result.response.error) {
      errors.add('${result.key}: ${result.response.errorMessageWithoutNull}');
      continue;
    }
    sections.add(
      SourceContentSection(
        key: result.key,
        title: result.title,
        comics: result.response.data,
        moreQuery: SourceContentQuery(
          categoryKey: '',
          page: 1,
          sort: result.sort,
        ),
      ),
    );
  }
  if (sections.isEmpty) {
    return Res.error(errors.join('; '));
  }
  return Res(sections);
}

Future<({String key, String title, String sort, Res<List<BaseComic>> response})>
_loadPicacgHomeSection(
  ({String key, String title, String sort}) section,
  PicacgHomePageLoader loadPage,
) async {
  try {
    return (
      key: section.key,
      title: section.title,
      sort: section.sort,
      response: await loadPage(section.sort),
    );
  } catch (error) {
    return (
      key: section.key,
      title: section.title,
      sort: section.sort,
      response: Res<List<BaseComic>>.error(error.toString()),
    );
  }
}

/// 哔咔内置源声明。
ComicSource buildPicacgSource({
  PicacgHomePageLoader? homePageLoader,
  PicacgNetwork? network,
}) {
  final client = network ?? PicacgNetwork();
  final loadHomePage =
      homePageLoader ??
      (String sort) async {
        final result = await client.getCategoryComics('', 1, sort);
        if (result.error) {
          return Res<List<BaseComic>>.error(result.errorMessageWithoutNull);
        }
        return Res<List<BaseComic>>(<BaseComic>[...result.data]);
      };
  final source = ComicSource.named(
    name: '哔咔',
    key: 'picacg',
    filePath: 'built-in',
    url: 'https://picaapi.go2778.com',
    version: '2.2.1.3.3.4',
    account: AccountConfig.named(
      login: (account, pwd) async {
        final res = await client.login(account, pwd);
        if (res.error) return Res.fromErrorRes(res);
        final s = ComicSource.find('picacg')!;
        s.data['token'] = res.data;
        final profile = await client.getProfile();
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
    loadSourceCategories: () async {
      final res = await client.getCategories();
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return Res(
        normalizeCategories([
          for (final category in res.data)
            SourceCategory(
              key: category.key,
              title: category.title,
              param: category.param,
              cover: category.cover,
              sortOptions: _picacgSortOptions,
            ),
        ]),
      );
    },
    loadSourceContent: (query) async {
      final res = await client.getCategoryComics(
        query.param ?? query.categoryKey,
        query.page,
        _picacgSort(query.sort),
      );
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return Res(
        SourceContentPage(
          query: query,
          comics: <BaseComic>[...res.data],
          maxPage: _optionalPageCount(res.subData),
        ),
      );
    },
    loadHomeSections: () => loadPicacgHomeSections(loadHomePage),
    // 哔咔搜索：高级搜索，sort='ua' 默认排序。
    searchPageData: SearchPageData.named(
      loadPage: (keyword, page, options) async {
        final res = await client.search(keyword, 'ua', page);
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return Res<List<BaseComic>>(<BaseComic>[
          ...res.data,
        ], subData: res.subData);
      },
      enableTagsSuggestions: true,
      loadHotTags: () => client.getHotTags(),
    ),
    // 详情：ComicItem → ComicInfoData 统一形态。
    loadComicInfo: (id) async {
      final res = await client.getComicInfo(id);
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return Res(picacgItemToComicInfoData(res.data));
    },
    // 章节图：ep 为 PicacgEpisode.order（章节序号，整数）。
    loadComicPages: (comicId, ep) async {
      final order = int.tryParse(ep ?? '1') ?? 1;
      final res = await client.getComicContent(comicId, order);
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return Res(res.data);
    },
    // 哔咔图片（封面/内文）无额外鉴权头，走默认 dio 即可。
    getImageLoadingConfig: null,
    getThumbnailLoadingConfig: null,
    // 收藏。
    favoriteData: FavoriteData.named(
      load: (page, [folder]) async {
        final res = await client.getFavorites(page, true);
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return Res<List<BaseComic>>(<BaseComic>[
          ...res.data,
        ], subData: res.subData);
      },
      addOrDelFavorite: (comicId, folderId, isAdding) async {
        final res = await client.favouriteOrUnfavourite(comicId);
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return const Res(true);
      },
      multiFolder: false,
    ),
    // 评论与回复。
    commentsLoader: (id, subId, page, replyToId) => replyToId == null
        ? client.getComments(id, page: page)
        : client.getCommentChildren(replyToId, page: page),
    sendCommentFunc: (id, subId, content, replyTo) => replyTo == null
        ? client.sendComment(id, content)
        : client.replyComment(replyTo.id, content),
    initData: (s) {
      s.data['appChannel'] ??= '3';
      s.data['imageQuality'] ??= 'original';
      // 默认接入 go2778 中转源；用户可在设置切换为 picacomic 直连。
      s.data['apiBaseUrl'] ??= defaultPicacgApiUrl;
    },
  );

  // 注入状态门面并注册到内置表。
  client.state = PicacgStateImpl(source);
  return source;
}

const _picacgSortKeys = <String>{'ua', 'dd', 'da', 'ld'};

const _picacgSortOptions = <SourceSortOption>[
  SourceSortOption(key: 'ua', title: '默认'),
  SourceSortOption(key: 'dd', title: '新到旧'),
  SourceSortOption(key: 'da', title: '旧到新'),
  SourceSortOption(key: 'ld', title: '最多喜欢'),
];

String _picacgSort(String? sort) {
  if (sort == null || !_picacgSortKeys.contains(sort)) {
    return 'ua';
  }
  return sort;
}

int? _optionalPageCount(Object? value) => value is int ? value : null;

List<String>? _storedAccount(Object? value) {
  final account = jsonStringList(value);
  return account.length >= 2 ? account : null;
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
/// 供 loadComicPages 调用。兼容 tags 只保留作者、汉化组、分类与标签；
/// 阅读、喜欢与评论数量通过类型化字段暴露。
ComicInfoData picacgItemToComicInfoData(ComicItem info) {
  final chapters = <String, String>{
    for (final episode in info.episodes)
      episode.order.toString(): episode.title,
  };
  final chapterList = <ComicChapter>[
    for (final episode in info.episodes)
      ComicChapter(
        id: episode.order.toString(),
        title: episode.title,
        order: episode.order,
      ),
  ];
  return ComicInfoData.snapshot(
    title: info.title,
    subTitle: info.author,
    cover: info.cover,
    description: info.description,
    tags: <String, List<String>>{
      if (info.author.trim().isNotEmpty) '作者': <String>[info.author],
      if (info.chineseTeam.trim().isNotEmpty) '汉化组': <String>[info.chineseTeam],
      if (info.categories.isNotEmpty) '分类': info.categories,
      if (info.tagList.isNotEmpty) '标签': info.tagList,
    },
    chapters: chapters,
    thumbnails: null,
    suggestions: <BaseComic>[...info.recommendation],
    sourceKey: 'picacg',
    comicId: info.id,
    isFavorite: info.isFavourite,
    authors: info.author.trim().isEmpty
        ? const <String>[]
        : <String>[info.author],
    categories: info.categories,
    labels: info.tagList,
    viewCount: info.views,
    likeCount: info.likes,
    commentCount: info.comments,
    isLiked: info.isLiked,
    chapterList: chapterList,
  );
}
