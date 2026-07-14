/// JoyComic 漫画源抽象契约。
///
/// 采用声明式设计：一个"漫画源"是一个 **数据 + 函数** 的聚合体，靠
/// 函数字段（typedef）描述契约，而非继承抽象类。这样：
///   - 每个源在自身文件里以 `ComicSource.named(...)` 声明即可注册；
///   - 阅读器 / 列表 / 详情页通过源 key 路由到对应实现，无需 if-else 硬编码。
library comic_source;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../network/base_comic.dart';
import '../network/res.dart';
import 'history.dart';

// ============================ typedefs：源契约函数签名 ============================

/// 构建漫画列表。约定 [Res.subData] 为 maxPage（无上限时为 null）。
typedef ComicListBuilder = Future<Res<List<BaseComic>>> Function(int page);

typedef LoginFunction = Future<Res<bool>> Function(String, String);

/// 加载漫画详情，返回统一形态 [ComicInfoData]。
typedef LoadComicFunc = Future<Res<ComicInfoData>> Function(String id);

/// 加载某章节的图片地址列表（图片 key / url）。
typedef LoadComicPagesFunc = Future<Res<List<String>>> Function(
    String id, String? ep);

typedef CommentsLoader = Future<Res<List<Comment>>> Function(
    String id, String? subId, int page, String? replyTo);

typedef SendCommentFunc = Future<Res<bool>> Function(
    String id, String? subId, String content, String? replyTo);

/// 单图加载配置覆写（url/method/headers 等），供自定义鉴权图片链路使用。
typedef GetImageLoadingConfigFunc = Map<String, dynamic> Function(
    String imageKey, String comicId, String epId)?;
typedef GetThumbnailLoadingConfigFunc = Map<String, dynamic> Function(
    String imageKey)?;

typedef SearchFunction = Future<Res<List<BaseComic>>> Function(
    String keyword, int page, List<String> searchOption);

typedef CategoryComicsLoader = Future<Res<List<BaseComic>>> Function(
    String category, String? param, List<String> options, int page);

// ============================ ComicSource ============================

class ComicSource {
  /// 内置源登记表。仅在 [init] 时按用户启用项加载到 [sources]。
  /// 哔咔与禁漫的具体声明在 lib/comic_source/built_in/ 下各自文件，
  /// 这里通过源 map 注入，避免硬 import 形成环依赖（详见 init）。
  static final builtInMap = <String, ComicSource Function()>{};

  static final List<ComicSource> sources = [];

  static ComicSource? find(String key) {
    for (final s in sources) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// 初始化启用的内置源。由 app 启动流程在 settings 系统就绪后调用。
  static Future<void> init(Set<String> enabledKeys) async {
    for (final entry in builtInMap.entries) {
      if (!enabledKeys.contains(entry.key)) continue;
      final s = entry.value();
      sources.add(s);
      await s.loadData();
      s.initData?.call(s);
    }
  }

  static Future<void> reload(Set<String> enabledKeys) async {
    sources.clear();
    await init(enabledKeys);
  }

  final String name;
  final String key;

  final AccountConfig? account;

  final CategoryData? categoryData;

  final CategoryComicsData? categoryComicsData;

  final FavoriteData? favoriteData;

  final List<ExplorePageData> explorePages;

  final SearchPageData? searchPageData;

  final List<SettingItem> settings;

  final LoadComicFunc? loadComicInfo;
  final LoadComicPagesFunc? loadComicPages;

  final GetImageLoadingConfigFunc getImageLoadingConfig;
  final GetThumbnailLoadingConfigFunc getThumbnailLoadingConfig;

  final String? matchBriefIdReg;
  final RegExp? idMatcher;

  final String filePath;
  final String url;
  final String version;

  final CommentsLoader? commentsLoader;
  final SendCommentFunc? sendCommentFunc;

  /// 仅内置源使用：数据加载后的一次性初始化钩子（如挑选默认图床域名）。
  final FutureOr<void> Function(ComicSource source)? initData;

  /// 源运行期状态：token / 账号 / 个人信息 / 源内设置。持久化到本地文件。
  var data = <String, dynamic>{};

  bool get isLogin => data["account"] != null;

  Future<void> loadData() async {
    final file = File(await _dataFilePath);
    if (await file.exists()) {
      data = Map<String, dynamic>.from(jsonDecode(await file.readAsString()));
    }
  }

  bool _isSaving = false;
  bool _haveWaitingTask = false;

  Future<void> saveData() async {
    if (_haveWaitingTask) return;
    while (_isSaving) {
      _haveWaitingTask = true;
      await Future.delayed(const Duration(milliseconds: 20));
      _haveWaitingTask = false;
    }
    _isSaving = true;
    final file = File(await _dataFilePath);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(data));
    _isSaving = false;
  }

  Future<String> get _dataFilePath async =>
      "${await _dataPath}/comic_source/$key.data";

  /// 由 app 在启动时注入应用数据目录（避免直接依赖 path_provider）。
  static String Function()? dataPathProvider;

  static Future<String> get _dataPath async =>
      dataPathProvider != null ? dataPathProvider!() : '';

  Future<bool> reLogin() async {
    if (data["account"] == null) return false;
    final List accountData = data["account"];
    final res = await account!.login!(accountData[0], accountData[1]);
    return !res.error;
  }

  ComicSource.named({
    required this.name,
    required this.key,
    this.account,
    this.categoryData,
    this.categoryComicsData,
    this.favoriteData,
    this.explorePages = const [],
    this.searchPageData,
    this.settings = const [],
    this.loadComicInfo,
    this.loadComicPages,
    this.getImageLoadingConfig,
    this.getThumbnailLoadingConfig,
    this.matchBriefIdReg,
    this.idMatcher,
    required this.filePath,
    this.url = '',
    this.version = '',
    this.commentsLoader,
    this.sendCommentFunc,
    this.initData,
  });
}

// ============================ 账号相关 ============================

class AccountConfig {
  final LoginFunction? login;
  final FutureOr<void> Function(BuildContext)? onLogin;
  final String? loginWebsite;
  final String? registerWebsite;
  final void Function()? logout;
  final bool allowReLogin;
  final List<AccountInfoItem> infoItems;

  const AccountConfig.named({
    this.login,
    this.loginWebsite,
    this.registerWebsite,
    this.logout,
    this.onLogin,
    this.allowReLogin = true,
    this.infoItems = const [],
  });
}

class AccountInfoItem {
  final String title;
  final String Function()? data;
  final void Function()? onTap;
  final WidgetBuilder? builder;

  AccountInfoItem({required this.title, this.data, this.onTap, this.builder});
}

// ============================ 探索页 / 分类 / 搜索 / 收藏 ============================

class ExplorePageData {
  final String title;
  final ExplorePageType type;
  final ComicListBuilder? loadPage;
  final Future<Res<List<ExplorePagePart>>> Function()? loadMultiPart;
  final Future<Res<List<Object>>> Function(int index)? loadMixed;
  final WidgetBuilder? overridePageBuilder;

  ExplorePageData.named({
    required this.title,
    required this.type,
    this.loadPage,
    this.loadMultiPart,
    this.loadMixed,
    this.overridePageBuilder,
  });
}

class ExplorePagePart {
  final String title;
  final List<BaseComic> comics;
  final String? viewMore;
  const ExplorePagePart(this.title, this.comics, this.viewMore);
}

enum ExplorePageType {
  multiPageComicList,
  singlePageWithMultiPart,
  mixed,
  override,
}

class SearchPageData {
  final List<SearchOptions>? searchOptions;
  final Widget Function(BuildContext, List<String> initialValues,
      void Function(List<String>))? customOptionsBuilder;
  final Widget Function(String keyword, List<String> options)?
      overrideSearchResultBuilder;
  final SearchFunction? loadPage;
  final bool enableLanguageFilter;
  final bool enableTagsSuggestions;

  /// 加载热门搜索词（为空时 UI 层可回落预设列表）。
  final Future<Res<List<String>>> Function()? loadHotTags;

  const SearchPageData.named({
    this.searchOptions,
    this.loadPage,
    this.enableLanguageFilter = false,
    this.customOptionsBuilder,
    this.overrideSearchResultBuilder,
    this.enableTagsSuggestions = false,
    this.loadHotTags,
  });
}

class SearchOptions {
  final LinkedHashMap<String, String> options;
  final String label;
  const SearchOptions.named({required this.options, required this.label});
  String get defaultValue => options.keys.first;
}

class CategoryComicsData {
  final List<CategoryComicsOptions> options;
  final CategoryComicsLoader load;
  final RankingData? rankingData;

  const CategoryComicsData.named({
    this.options = const [],
    required this.load,
    this.rankingData,
  });
}

class RankingData {
  final Map<String, String> options;
  final Future<Res<List<BaseComic>>> Function(String option, int page) load;
  const RankingData.named({required this.options, required this.load});
}

class CategoryComicsOptions {
  final LinkedHashMap<String, String> options;
  final List<String> notShowWhen;
  final List<String>? showWhen;
  const CategoryComicsOptions.named({
    required this.options,
    this.notShowWhen = const [],
    this.showWhen,
  });
}

class FavoriteData {
  final Future<Res<List<BaseComic>>> Function(int page, [String? folder]) load;
  final Future<Res<List<String>>> Function()? loadFolders;
  final Future<Res<bool>> Function(String comicId, String folderId, bool isAdding)?
      addOrDelFavorite;
  final Future<Res<bool>> Function(String name)? addFolder;
  final Future<Res<bool>> Function(String id)? deleteFolder;
  final bool multiFolder;

  const FavoriteData.named({
    required this.load,
    this.loadFolders,
    this.addOrDelFavorite,
    this.addFolder,
    this.deleteFolder,
    this.multiFolder = false,
  });
}

// ============================ 通用详情契约 / 设置项 / 评论 ============================

class ComicInfoData with HistoryMixin {
  @override
  final String title;
  @override
  final String? subTitle;
  @override
  final String cover;
  final String? description;
  final Map<String, List<String>> tags;

  /// 章节映射，id -> name（无分章的漫画为 null）。
  final Map<String, String>? chapters;
  final List<String>? thumbnails;
  final Future<Res<List<String>>> Function(String id, int page)? thumbnailLoader;
  final int thumbnailMaxPage;
  final List<BaseComic>? suggestions;
  final String sourceKey;
  final String comicId;
  final bool? isFavorite;
  final String? subId;

  const ComicInfoData({
    required this.title,
    required this.subTitle,
    required this.cover,
    required this.description,
    required this.tags,
    required this.chapters,
    required this.thumbnails,
    this.thumbnailLoader,
    this.thumbnailMaxPage = 0,
    this.suggestions,
    required this.sourceKey,
    required this.comicId,
    this.isFavorite,
    this.subId,
  });

  @override
  HistoryType get historyType => HistoryType.fromKey(sourceKey);

  @override
  String get target => comicId;
}

class SettingItem {
  final String name;
  final String iconName;
  final SettingType type;
  final List<String>? options;
  const SettingItem.named({
    required this.name,
    required this.iconName,
    required this.type,
    this.options,
  });
}

enum SettingType { switcher, selector, input }

class Comment {
  final String userName;
  final String? avatar;
  final String content;
  final String? time;
  final int? replyCount;
  final String? id;
  const Comment(this.userName, this.avatar, this.content, this.time,
      this.replyCount, this.id);
}

// ============================ 分类页数据 ============================

/// 分类页的整体数据：固定/随机分类块 + 入口按钮 + 是否启用排行榜。
class CategoryData {
  final String title;
  final String key;
  final List<BaseCategoryPart> categories;
  final bool enableRankingPage;
  final List<CategoryButtonData> buttons;

  const CategoryData.named({
    required this.title,
    required this.key,
    this.categories = const [],
    this.enableRankingPage = false,
    this.buttons = const [],
  });
}

/// 分类块基类。
abstract class BaseCategoryPart {
  String get title;
}

/// 固定项分类块：如哔咔的"分类"标签集合，[key] 指明加载时传入的参数键。
class FixedCategoryPart extends BaseCategoryPart {
  @override
  final String title;
  final List<String> categories;
  final String key;
  const FixedCategoryPart(this.title, this.categories, this.key);
}

/// 随机项分类块：每次刷新取随机顺序的若干标签。
class RandomCategoryPart extends BaseCategoryPart {
  @override
  final String title;
  final List<String> categories;
  final String key;
  final int randomNumber;
  const RandomCategoryPart(this.title, this.categories, this.key,
      {this.randomNumber = 0});
}

/// 分类页上的自定义入口按钮。
class CategoryButtonData {
  final String label;
  final void Function() onTap;
  const CategoryButtonData({required this.label, required this.onTap});
}
