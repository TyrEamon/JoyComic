/// 禁漫源的内置声明与状态绑定。
///
/// 把 [JmNetwork] 与 [ComicSource] 契约连接：构造 [JmStateImpl] 桥接源
/// 运行期 `data`（baseUrl 由域名选择后写入），注入到网络层；声明账号登录流。
/// 登录时还会探测选用可用接口域名与图床。
library;

import 'package:flutter/foundation.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/source_credential_store.dart';
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
  JmStateImpl(this.source);

  final ComicSource source;
  String _avs = '';

  @override
  String get avs => _avs;

  Future<void> restoreAuthentication() async {
    var changed = false;
    final legacy = _storedAccount(source.data.remove('account'));
    if (legacy != null) {
      await source.credentialStore.saveCredentials(
        source.key,
        legacy[0],
        legacy[1],
      );
      changed = true;
    }
    if (source.data.remove('name') != null) changed = true;

    final credentials = await source.credentialStore.readCredentials(
      source.key,
    );
    final restoredAvs = await source.credentialStore.readSession(
      source.key,
      'avs',
    );
    if (credentials == null || restoredAvs == null || restoredAvs.isEmpty) {
      await clearAvs();
      return;
    }

    _avs = restoredAvs;
    if (source.data['authenticated'] != true) {
      source.data['authenticated'] = true;
      changed = true;
    }
    if (changed) await source.saveData();
  }

  @override
  Future<void> setAvs(String value) async {
    _avs = value.trim();
    if (_avs.isEmpty) {
      source.data.remove('authenticated');
    } else {
      source.data['authenticated'] = true;
    }

    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await source.credentialStore.saveSession(source.key, 'avs', _avs);
    } catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }
    try {
      await source.saveData();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  @override
  Future<void> clearAvs() => setAvs('');

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
  String get imageBaseUrl => resolveJmImageBaseUrl(
    jsonString(source.data['imageBaseUrl'], fallback: jmBuiltInImgUrls.first),
  );

  @override
  void setImageBaseUrl(String url) {
    final resolved = resolveJmImageBaseUrl(url);
    source.data['imageBaseUrl'] = resolved;
    jmBaseUrl = resolved;
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
  int get selectedShuntKey =>
      jsonInt(source.data['selectedShuntKey'], fallback: jmExpressShuntKey);

  @override
  void setSelectedShuntKey(int key) {
    source.data['selectedShuntKey'] = key;
    source.saveData();
  }

  @override
  String? get username {
    if (source.data['authenticated'] != true) return null;
    final user = jsonMap(source.data['user']);
    final name = jsonString(user['name'] ?? user['username']).trim();
    return name.isEmpty ? 'authenticated' : name;
  }

  @override
  List<String>? getAccount() => null;

  @override
  Future<bool> reLogin() => source.reLogin();
}

typedef JmFavoriteToggle = Future<Res<bool>> Function(String comicId);
typedef JmCommentSender =
    Future<Res<bool>> Function(String comicId, String content);

/// Adapts the JM toggle endpoint without replacing its error or boolean data.
Future<Res<bool>> adaptJmFavoriteToggle(
  String comicId,
  JmFavoriteToggle toggleFavorite,
) => toggleFavorite(comicId);

/// 禁漫内置源声明。
ComicSource buildJmSource({
  JmFavoriteToggle? favoriteToggle,
  JmCommentSender? commentSender,
  SourceCredentialStore? credentialStore,
  JmNetwork? network,
  void Function(JmNetwork network)? onNetworkReady,
  Future<int?> Function(List<String> domains)? domainSelector,
}) {
  late final JmNetwork client;
  late final SourceCredentialStore effectiveCredentialStore;
  if (network != null) {
    if (credentialStore != null &&
        !identical(credentialStore, network.credentialStore)) {
      throw ArgumentError('JM source and network credential stores must match');
    }
    client = network;
    effectiveCredentialStore = credentialStore ?? network.credentialStore;
  } else if (credentialStore != null) {
    effectiveCredentialStore = credentialStore;
    client = JmNetwork(credentialStore: effectiveCredentialStore);
  } else {
    client = JmNetwork();
    effectiveCredentialStore = client.credentialStore;
  }
  onNetworkReady?.call(client);
  late final JmStateImpl stateFacade;
  final toggleFavoriteRequest = favoriteToggle ?? client.toggleFavorite;
  final sendCommentRequest = commentSender ?? client.sendComment;
  final source = ComicSource.named(
    name: '禁漫',
    key: 'jm',
    filePath: 'built-in',
    url: 'https://jmcomic1.cc',
    version: '1.6.3',
    credentialStore: effectiveCredentialStore,
    account: AccountConfig.named(
      login: (account, pwd) => client.runAuthenticationOperation(() async {
        final previousCredentials = await effectiveCredentialStore
            .readCredentials('jm');
        var networkLoginSucceeded = false;
        try {
          // 登录前先探测可用接口域名并写入。
          final idx = await (domainSelector ?? client.selectDomain)(
            jmBuiltInDomains,
          );
          final s = ComicSource.find('jm')!;
          if (idx != null) {
            final domain = jmBuiltInDomains[idx];
            s.data['apiBaseUrl'] = 'https://$domain';
            // 探测到的可用域名置顶轮询池，避免后续 get 被池首域名覆盖。
            client.state?.setPreferredDomain(domain);
            await s.saveData();
          }
          final res = await client.login(account, pwd);
          if (res.error) return Res.fromErrorRes(res);
          networkLoginSucceeded = true;
          // 登录后拉取 /setting：动态分流项 + 图床域名写入持久化。
          final setting = await client.fetchSetting();
          if (setting.errorMessage == '請先登入會員') {
            await client.rollbackAuthentication(previousCredentials);
            networkLoginSucceeded = false;
            return Res<bool>(null, errorMessage: setting.errorMessage);
          }
          if (!setting.error) {
            // 兜底：setting 未返回图床时用内置候选首项。
            if ((s.data['imageBaseUrl'] ?? '') == '') {
              client.state?.setImageBaseUrl(jmBuiltInImgUrls[0]);
            }
          } else {
            client.state?.setImageBaseUrl(jmBuiltInImgUrls[0]);
          }
          final profile = client.lastLoginProfile;
          if (profile != null) {
            final photo = profile.photo?.trim();
            s.data['user'] = <String, dynamic>{
              'name': profile.name,
              if (profile.id != null) 'id': profile.id,
              if (profile.nickname != null) 'nickname': profile.nickname,
              if (profile.level != null) 'level': profile.level,
              if (photo != null && photo.isNotEmpty)
                'avatarUrl': photo.startsWith('http')
                    ? photo
                    : getJmAvatarUrl(photo),
            };
          }
          await s.saveData();
          return const Res(true);
        } catch (_) {
          if (networkLoginSucceeded) {
            await client.rollbackAuthentication(previousCredentials);
          }
          rethrow;
        }
      }),
      logout: () => client.runAuthenticationOperation(() async {
        await client.logout();
        final s = ComicSource.find('jm');
        if (s == null) return;
        s.data.remove('name');
        s.data.remove('user');
        s.data.remove('account');
        s.data.remove('authenticated');
        await s.saveData();
      }),
      loginWebsite: 'https://jmcomic1.cc',
    ),
    loadSourceCategories: () async {
      final res = await client.getCategories();
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return Res(adaptJmSourceCategories(res.data));
    },
    loadSourceContent: (query) async {
      final category = (query.param ?? query.categoryKey).trim();
      // Numeric promote ids (e.g. 30 = 禁漫去碼&全彩化) use promote_list.
      if (RegExp(r'^\d+$').hasMatch(category)) {
        final res = await client.getPromoteList(category, query.page);
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        final total = res.subData is int ? res.subData as int : 0;
        final maxPage = jmCategoryMaxPage(
          total: total,
          currentPage: query.page,
          itemCount: res.data.length,
          pageSize: res.data.isNotEmpty ? res.data.length : null,
        );
        return Res(
          SourceContentPage(
            query: query,
            comics: <BaseComic>[...res.data],
            maxPage: maxPage,
          ),
        );
      }
      final res = await client.getCategoryComics(
        category,
        _jmSort(query.sort),
        query.page,
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
    loadHomeSections: () async {
      final res = await client.getHomeSections();
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
    categoryComicsData: CategoryComicsData.named(
      load: (category, param, options, page) async {
        final order = options.isEmpty ? 'mr' : options.first;
        final res = await client.getCategoryComics(
          param ?? category,
          order,
          page,
        );
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return Res<List<BaseComic>>(<BaseComic>[...res.data]);
      },
      rankingData: RankingData.named(
        options: const <String, String>{
          'latest': 'mr',
          'hot': 'mp',
          'rating': 'mv',
        },
        load: (option, page) async {
          final res = await client.search('', page, option);
          if (res.error) return Res(null, errorMessage: res.errorMessage);
          return Res<List<BaseComic>>(<BaseComic>[...res.data]);
        },
      ),
    ),
    // 搜索：免登录可搜（token 仅 md5(时间戳+盐)，非 session）。
    searchPageData: SearchPageData.named(
      loadPage: (keyword, page, options) async {
        final res = await client.search(keyword, page, 'mr');
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return Res<List<BaseComic>>(<BaseComic>[...res.data]);
      },
      enableTagsSuggestions: true,
      loadHotTags: () => client.getHotTags(),
    ),
    // 详情：JmComicInfo → ComicInfoData 统一形态。
    loadComicInfo: (id) async {
      final res = await client.getComicInfo(id);
      if (res.error) return Res(null, errorMessage: res.errorMessage);
      return Res(jmInfoToComicInfoData(res.data));
    },
    // 单卷优先复用详情内联页，分章继续调用 chapter 端点。
    loadComicPages: (comicId, ep) => client.getComicPages(comicId, ep),
    // 禁漫图片：仿官方图床请求头 + 多图床 fallback + 按章节 id/无扩展名文件名重组。
    getImageLoadingConfig: (imageKey, comicId, epId) {
      final current = stateFacade.imageBaseUrl;
      final fallbacks = <String>[];
      final seenHosts = <String>{};
      // Prefer session image base, then built-in CDN pool (verifier order).
      // Skip hosts that would only reproduce the primary URL.
      void addCandidate(String hostBase) {
        if (hostBase.isEmpty) return;
        final host = Uri.tryParse(hostBase)?.host ?? '';
        if (host.isEmpty || !seenHosts.add(host)) return;
        final replaced = _replaceJmImageHost(imageKey, hostBase);
        if (replaced == imageKey) return;
        fallbacks.add(replaced);
      }

      addCandidate(current);
      for (final candidate in jmBuiltInImgUrls) {
        addCandidate(candidate);
      }

      final parsedImage = Uri.tryParse(imageKey);
      final rawName = parsedImage != null && parsedImage.pathSegments.isNotEmpty
          ? parsedImage.pathSegments.last
          : imageKey
                .split('/')
                .lastWhere((s) => s.isNotEmpty, orElse: () => imageKey);
      final episodeId = epId.trim().isNotEmpty ? epId.trim() : comicId.trim();
      final isGif = rawName.toLowerCase().endsWith('.gif');
      return <String, dynamic>{
        'url': imageKey,
        // Cache key ignores query noise and host so fallbacks share one entry.
        'cacheKey': _jmImageCacheKey(imageKey),
        'headers': imageHeaders(),
        if (fallbacks.isNotEmpty) 'fallbackUrls': fallbacks,
        if (episodeId.isNotEmpty && rawName.isNotEmpty && !isGif)
          'transform': <String, String>{
            'type': 'jm',
            'episodeId': episodeId,
            'imageName': rawName,
            'scrambleId': jmScrambleId,
          },
      };
    },
    getThumbnailLoadingConfig: (imageKey) => imageHeaders(),
    // 收藏。
    favoriteData: FavoriteData.named(
      load: (page, [folder]) async {
        final res = await client.fetchFavorites(
          page: page,
          folderId: folder ?? '0',
        );
        if (res.error) return Res(null, errorMessage: res.errorMessage);
        return Res<List<BaseComic>>(<BaseComic>[...res.data]);
      },
      // 禁漫端点本身执行切换；保留网络层的 error 和 bool 结果。
      addOrDelFavorite: (comicId, folderId, isAdding) =>
          adaptJmFavoriteToggle(comicId, toggleFavoriteRequest),
      multiFolder: true,
    ),
    // 评论。
    commentsLoader: (id, subId, page, replyToId) => client.getComment(id, page),
    sendCommentFunc: (id, subId, content, replyTo) {
      final trimmedContent = content.trim();
      final payload = replyTo == null
          ? trimmedContent
          : '@${replyTo.userName} $trimmedContent';
      return sendCommentRequest(id, payload);
    },
    initData: (s) async {
      s.data['apiBaseUrl'] ??= 'https://${jmBuiltInDomains.first}';
      s.data['selectedShuntKey'] ??= jmExpressShuntKey;
      await stateFacade.restoreAuthentication();
      jmBaseUrl = stateFacade.imageBaseUrl;
    },
  );

  stateFacade = JmStateImpl(source);
  client.state = stateFacade;
  return source;
}

String _replaceJmImageHost(String url, String host) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.host.isEmpty) return url;
  final base = Uri.tryParse(host);
  if (base == null || base.host.isEmpty) return url;
  return parsed
      .replace(
        scheme: base.scheme.isEmpty ? parsed.scheme : base.scheme,
        host: base.host,
      )
      .toString();
}

/// Stable cache key for JM media: path without host/query so host fallbacks hit.
String _jmImageCacheKey(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.path.isEmpty) {
    return url.replaceAll(RegExp(r'\?.*$'), '');
  }
  return parsed.path;
}

List<SourceCategory> adaptJmSourceCategories(
  Iterable<JmCategory> sourceCategories,
) {
  final categories = <SourceCategory>[];
  for (final category in sourceCategories) {
    final parentKey = category.slug.trim();
    final parentTitle = category.name.trim();
    if (parentKey.isEmpty || parentTitle.isEmpty) continue;

    categories.add(
      SourceCategory(
        key: parentKey,
        title: parentTitle,
        param: parentKey,
        sortOptions: _jmSortOptions,
      ),
    );
    for (final subCategory in category.subCategories) {
      final childKey = subCategory.cid.trim();
      final childTitle = subCategory.name.trim();
      if (childKey.isEmpty || childTitle.isEmpty) continue;
      final childParam = subCategory.slug.trim();
      categories.add(
        SourceCategory(
          key: childKey,
          title: childTitle,
          parentKey: parentKey,
          param: childParam.isEmpty ? childKey : childParam,
          sortOptions: _jmSortOptions,
        ),
      );
    }
  }
  return normalizeCategories(categories);
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

int? _optionalPageCount(Object? value) => value is int ? value : null;

List<String>? _storedAccount(Object? value) {
  final account = jsonStringList(value);
  return account.length >= 2 ? account : null;
}

/// 禁漫详情 → 统一 [ComicInfoData]。
@visibleForTesting
ComicInfoData jmInfoToComicInfoData(JmComicInfo info) {
  final jmChapters = <JmChapter>[...info.chapters];
  if (jmChapters.isEmpty &&
      info.series.isEmpty &&
      (info.seriesId == null || info.seriesId == 0)) {
    jmChapters.add(
      JmChapter(
        order: 1,
        chapterId: info.id,
        title: info.name.trim().isEmpty ? '第 1 话' : info.name,
        pageCount: info.totalPhotos,
      ),
    );
  }

  final chapters = <String, String>{
    for (final chapter in jmChapters) chapter.chapterId: chapter.title,
  };
  final chapterList = <ComicChapter>[
    for (final chapter in jmChapters)
      ComicChapter(
        id: chapter.chapterId,
        title: chapter.title,
        order: chapter.order,
        pageCount: chapter.pageCount ??
            (jmChapters.length == 1 ? info.totalPhotos : null),
      ),
  ];

  // Unpaid premium albums often have empty images; reader loads via chapter.
  final singlePages = info.images.isEmpty ? null : info.images;

  return ComicInfoData.snapshot(
    title: info.name,
    subTitle: info.author.isNotEmpty ? info.author.first : null,
    cover: info.cover,
    description: info.description,
    tags: <String, List<String>>{
      if (info.author.isNotEmpty) '作者': info.author,
      if (info.categories.isNotEmpty) '分类': info.categories,
      if (info.tags.isNotEmpty) '标签': info.tags,
      if (info.works.isNotEmpty) '作品': info.works,
      if (info.actors.isNotEmpty) '演员': info.actors,
    },
    chapters: chapters,
    thumbnails: null,
    suggestions: <BaseComic>[...info.relatedComics],
    sourceKey: 'jm',
    comicId: info.id,
    isFavorite: info.favorite,
    authors: info.author,
    categories: info.categories,
    labels: info.tags,
    viewCount: info.views,
    likeCount: info.likes,
    commentCount: info.comments,
    isLiked: info.liked,
    chapterList: chapterList,
    singleChapterPages: singlePages,
  );
}
