/// 禁漫源的内置声明与状态绑定。
///
/// 把 [JmNetwork] 与 [ComicSource] 契约连接：构造 [JmStateImpl] 桥接源
/// 运行期 `data`（baseUrl 由域名选择后写入），注入到网络层；声明账号登录流。
/// 登录时还会探测选用可用接口域名与图床。
library built_in_jm;

import '../../comic_source/comic_source.dart';
import '../../network/base_comic.dart';
import '../../network/jm/jm_headers.dart';
import '../../network/jm/jm_image.dart';
import '../../network/jm/jm_network.dart';
import '../../network/json_value.dart';
import '../../network/res.dart';
import '../../network/source_state.dart';
import '../../views/common/source_content_models.dart';

/// 禁漫源状态门面实现。
class JmStateImpl implements JmState {
  final ComicSource source;
  JmStateImpl(this.source);

  @override
  String get apiBaseUrl => jsonString(
        source.data['apiBaseUrl'],
        fallback: 'https://${jmBuiltInDomains.first}',
      );

  @override
  void setApiBaseUrl(String url) {
    source.data['apiBaseUrl'] = url;
    source.saveData();
  }

  @override
  String get imageBaseUrl => jsonString(
        source.data['imageBaseUrl'],
        fallback: jmBuiltInImgUrls.first,
      );

  @override
  void setImageBaseUrl(String url) {
    source.data['imageBaseUrl'] = url;
    jmBaseUrl = url;
    source.saveData();
  }

  @override
  String get preferredDomain => jsonString(source.data['preferredDomain']);

  @override
  void setPreferredDomain(String domain) {
    source.data['preferredDomain'] = domain;
    source.saveData();
  }

  @override
  List<JmShunt> get shunts {
    final shunts = <JmShunt>[];
    for (final rawShunt in jsonList(source.data['shunts'])) {
      if (rawShunt is! Map) continue;
      final shunt = jsonMap(rawShunt);
      final key = jsonInt(shunt['key'], fallback: -1);
      if (key < 0) continue;
      shunts.add(JmShunt(key: key, title: jsonString(shunt['title'])));
    }
    return shunts;
  }
  @override
  void setShunts(List<JmShunt> shunts) {
    source.data['shunts'] = [
      for (final s in shunts) {'key': s.key, 'title': s.title},
    ];
    source.saveData();
  }

  @override
  int get selectedShuntKey => jsonInt(
        source.data['selectedShuntKey'],
        fallback: jmExpressShuntKey,
      );

  @override
  void setSelectedShuntKey(int key) {
    source.data['selectedShuntKey'] = key;
    source.saveData();
  }

  @override
  String? get username => _optionalString(source.data['name']);

  @override
  List<String>? getAccount() => _storedAccount(source.data['account']);

  @override
  Future<bool> reLogin() => source.reLogin();
}

/// 禁漫内置源声明。
ComicSource buildJmSource() {
  final source = ComicSource.named(
    name: '禁漫',
    key: 'jm',
    filePath: 'built-in',
    url: 'https://jmcomic1.cc',
    version: '1.6.3',
    account: AccountConfig.named(
      login: (account, pwd) async {
        final network = JmNetwork();
        // 登录前先探测可用接口域名并写入。
        final idx = await network.selectDomain(jmBuiltInDomains);
        final s = ComicSource.find('jm')!;
        if (idx != null) {
          final domain = jmBuiltInDomains[idx];
          s.data['apiBaseUrl'] = 'https://$domain';
          // 探测到的可用域名置顶轮询池，避免后续 get 被池首域名覆盖。
          network.state?.setPreferredDomain(domain);
          await s.saveData();
        }
        final res = await network.login(account, pwd);
        if (res.error) return Res.fromErrorRes(res);
        s.data['name'] = account;
        s.data['account'] = <String>[account, pwd];
        await s.saveData();
        // 登录后拉取 /setting：动态分流项 + 图床域名写入持久化。
        final setting = await network.fetchSetting();
        if (!setting.error) {
          // 兜底：setting 未返回图床时用内置候选首项。
          if ((s.data['imageBaseUrl'] ?? '') == '') {
            network.state?.setImageBaseUrl(jmBuiltInImgUrls[0]);
          }
        } else {
          network.state?.setImageBaseUrl(jmBuiltInImgUrls[0]);
        }
        await s.saveData();
        return const Res(true);
      },
      logout: () {
        final s = ComicSource.find('jm');
        if (s == null) return;
        s.data['name'] = null;
        s.data['account'] = null;
        s.saveData();
        JmNetwork().logout();
      },
      loginWebsite: 'https://jmcomic1.cc',
    ),
    loadSourceCategories: () async {
      final res = await JmNetwork().getCategories();
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      final categories = <SourceCategory>[];
      for (final category in res.data) {
        categories.add(SourceCategory(
          key: category.slug,
          title: category.name,
          param: category.slug,
          sortOptions: _jmSortOptions,
        ));
        for (final subCategory in category.subCategories) {
          categories.add(SourceCategory(
            key: subCategory.cid,
            title: subCategory.name,
            parentKey: category.slug,
            param: subCategory.slug.isEmpty
                ? subCategory.cid
                : subCategory.slug,
            sortOptions: _jmSortOptions,
          ));
        }
      }
      return Res(normalizeCategories(categories));
    },
    loadSourceContent: (query) async {
      final res = await JmNetwork().getCategoryComics(
        query.param ?? query.categoryKey,
        _jmSort(query.sort),
        query.page,
      );
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return Res(SourceContentPage(
        query: query,
        comics: <BaseComic>[...res.data],
        maxPage: jsonInt(res.subData, fallback: query.page),
      ));
    },
    loadHomeSections: () async {
      final res = await JmNetwork().getHomeSections();
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return Res([
        for (final section in res.data)
          SourceContentSection(
            key: section.key,
            title: section.title,
            comics: <BaseComic>[...section.comics],
            moreQuery: section.categoryParam == null
                ? null
                : SourceContentQuery(
                    categoryKey: section.key,
                    param: section.categoryParam,
                    sort: 'latest',
                  ),
          ),
      ]);
    },
    // 搜索：免登录可搜（token 仅 md5(时间戳+盐)，非 session）。
    searchPageData: SearchPageData.named(
      loadPage: (keyword, page, options) async {
        final res = await JmNetwork().search(keyword, page, 'mr');
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return Res<List<BaseComic>>(<BaseComic>[...res.data]);
      },
      enableTagsSuggestions: true,
      loadHotTags: () => JmNetwork().getHotTags(),
    ),
    // 详情：JmComicInfo → ComicInfoData 统一形态。
    loadComicInfo: (id) async {
      final res = await JmNetwork().getComicInfo(id);
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return Res(_jmInfoToComicInfoData(res.data));
    },
    // 章节图：ep 为 chapterId（来自 series 映射值）。
    loadComicPages: (comicId, ep) async {
      final res = await JmNetwork().getChapter(ep ?? comicId);
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return Res(res.data);
    },
    // 禁漫图片（封面/内文）统一带仿浏览器头，部分图床校验 UA/Referer。
    getImageLoadingConfig: (imageKey, comicId, epId) => imageHeaders(),
    getThumbnailLoadingConfig: (imageKey) => imageHeaders(),
    // 收藏。
    favoriteData: FavoriteData.named(
      load: (page, [folder]) async {
        final res = await JmNetwork().fetchFavorites(
          page: page,
          folderId: folder ?? '0',
        );
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return Res<List<BaseComic>>(<BaseComic>[...res.data]);
      },
      addOrDelFavorite: (comicId, folderId, isAdding) async {
        if (isAdding) {
          // 禁漫切换收藏：调用 /favorite?aid=
          await JmNetwork().toggleFavorite(comicId);
        } else {
          await JmNetwork().toggleFavorite(comicId);
        }
        return const Res(true);
      },
      multiFolder: true,
    ),
    // 评论。
    commentsLoader: (id, subId, page, replyTo) async {
      final res = await JmNetwork().getComment(id, page);
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      final comments = res.data.map((comment) => Comment(
        jsonString(comment['userName']),
        _optionalString(comment['avatar']),
        jsonString(comment['content']),
        _optionalString(comment['time']),
        jsonInt(comment['replyCount']),
        _optionalString(comment['id']),
      )).toList();
      return Res(comments);
    },
    initData: (s) {
      s.data['apiBaseUrl'] ??= 'https://${jmBuiltInDomains.first}';
      s.data['selectedShuntKey'] ??= jmExpressShuntKey;
    },
  );

  JmNetwork()..state = JmStateImpl(source);
  return source;
}

const _jmSortOptions = <SourceSortOption>[
  SourceSortOption(key: 'latest', title: '最新'),
  SourceSortOption(key: 'popular', title: '总排行'),
  SourceSortOption(key: 'month', title: '月排行'),
  SourceSortOption(key: 'week', title: '周排行'),
  SourceSortOption(key: 'day', title: '日排行'),
  SourceSortOption(key: 'pictures', title: '最多图片'),
  SourceSortOption(key: 'likes', title: '最多喜欢'),
];

const _jmSortMap = <String, String>{
  'latest': 'mr',
  'popular': 'mv',
  'month': 'mv_m',
  'week': 'mv_w',
  'day': 'mv_t',
  'pictures': 'mp',
  'likes': 'tf',
};

String _jmSort(String? sort) => _jmSortMap[sort] ?? 'mr';

List<String>? _storedAccount(Object? value) {
  final account = jsonStringList(value);
  return account.length >= 2 ? account : null;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final text = jsonString(value);
  return text.isEmpty ? null : text;
}

/// 禁漫详情 → 统一 [ComicInfoData]。
///
/// 章节映射：JmComicInfo.series（order→chapterId）+ epNames（按 order 对齐）
/// → {chapterId: 章节名}。tags 组装为 Map（作者/标签/作品/演员 + 热度/收藏
/// 数值化，供详情页元数据组与热度 pill 取用）。禁漫无封面级评分数据，
/// 评分留空（详情页用默认占位，不强行编造）。
ComicInfoData _jmInfoToComicInfoData(JmComicInfo info) {
  final chapters = <String, String>{};
  for (final c in info.chapters) {
    chapters[c.chapterId] = c.title;
  }
  return ComicInfoData(
    title: info.name,
    subTitle: info.author.isNotEmpty ? info.author.first : null,
    cover: info.cover,
    description: info.description,
    tags: {
      '作者': info.author,
      '标签': info.tags,
      if (info.works.isNotEmpty) '作品': info.works,
      if (info.actors.isNotEmpty) '演员': info.actors,
      '热度': [_formatCount(info.views)],
      '收藏': [_formatCount(info.likes)],
    },
    chapters: chapters,
    thumbnails: null,
    suggestions: <BaseComic>[...info.relatedComics],
    sourceKey: 'jm',
    comicId: info.id,
    isFavorite: info.favorite,
  );
}

/// 数值量化：>=1 亿显示"X.X 亿"，>=1 万显示"X.X 万"，否则原数。
String _formatCount(int n) {
  if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
  return n.toString();
}
