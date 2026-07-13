/// 禁漫源的内置声明与状态绑定。
///
/// 把 [JmNetwork] 与 [ComicSource] 契约连接：构造 [JmStateImpl] 桥接源
/// 运行期 `data`（baseUrl 由域名选择后写入），注入到网络层；声明账号登录流。
/// 登录时还会探测选用可用接口域名与图床。
library built_in_jm;

import 'dart:collection';

import '../../comic_source/comic_source.dart';
import '../../network/base_comic.dart';
import '../../network/jm/jm_headers.dart';
import '../../network/jm/jm_image.dart';
import '../../network/jm/jm_network.dart';
import '../../network/res.dart';
import '../../network/source_state.dart';

/// 禁漫源状态门面实现。
class JmStateImpl implements JmState {
  final ComicSource source;
  JmStateImpl(this.source);

  @override
  String get apiBaseUrl =>
      source.data['apiBaseUrl'] ?? 'https://${jmBuiltInDomains.first}';

  @override
  void setApiBaseUrl(String url) {
    source.data['apiBaseUrl'] = url;
    source.saveData();
  }

  @override
  String get imageBaseUrl =>
      source.data['imageBaseUrl'] ?? jmBuiltInImgUrls.first;

  @override
  void setImageBaseUrl(String url) {
    source.data['imageBaseUrl'] = url;
    jmBaseUrl = url;
    source.saveData();
  }

  @override
  String get preferredDomain => source.data['preferredDomain'] ?? '';

  @override
  void setPreferredDomain(String domain) {
    source.data['preferredDomain'] = domain;
    source.saveData();
  }

  @override
  List<JmShunt> get shunts {
    final raw = source.data['shunts'];
    if (raw is! List) return const [];
    return [
      for (final s in raw)
        if (s is Map)
          JmShunt(key: s['key'] as int, title: (s['title'] ?? '') as String),
    ];
  }

  @override
  void setShunts(List<JmShunt> shunts) {
    source.data['shunts'] = [
      for (final s in shunts) {'key': s.key, 'title': s.title},
    ];
    source.saveData();
  }

  @override
  int get selectedShuntKey => source.data['selectedShuntKey'] ?? jmExpressShuntKey;

  @override
  void setSelectedShuntKey(int key) {
    source.data['selectedShuntKey'] = key;
    source.saveData();
  }

  @override
  String? get username => source.data['name'];

  @override
  List<String>? getAccount() => source.data['account'] as List<String>?;

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
    // 搜索：免登录可搜（token 仅 md5(时间戳+盐)，非 session）。
    searchPageData: SearchPageData.named(
      loadPage: (keyword, page, options) async {
        final res = await JmNetwork().search(keyword, page, 'mr');
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return Res<List<BaseComic>>(res.data.cast<BaseComic>());
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
    // 禁漫分类（使用预设主分类列表）。
    categoryData: CategoryData.named(
      title: '禁漫分类',
      key: 'jm',
      categories: [
        FixedCategoryPart('全部', [
          '恋爱', '校园', '同人', '奇幻', '悬疑', '搞笑',
          '百合', '伪娘', '单本', '短篇', '连载', '完结',
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
        final res = await JmNetwork().search(category, page, 'mr');
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return Res<List<BaseComic>>(res.data.cast<BaseComic>());
      },
    ),
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
        return Res<List<BaseComic>>(res.data.cast<BaseComic>());
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
      s.data['apiBaseUrl'] ??= 'https://${jmBuiltInDomains.first}';
      s.data['selectedShuntKey'] ??= jmExpressShuntKey;
    },
  );

  JmNetwork()..state = JmStateImpl(source);
  return source;
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
    suggestions: info.relatedComics.cast<BaseComic>(),
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
