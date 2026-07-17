/// 阅读器内容态 Provider。
///
/// 管理阅读器的核心内容状态：当前章节、页码、图片列表、工具栏显隐、自动翻页、
/// 阅读记录。与 [ListStateProvider]（UI 态）分离，遵循单一职责。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../database/read_record_helper.dart';
import '../../../foundation/reader_config.dart';
import '../../../foundation/log.dart';
import '../../../network/res.dart';
import '../state/comic_state.dart';
import '../state/read_mode.dart';
import '../utils/reader_utils.dart';
import '../widgets/toast.dart';

// ============================ 图片类型 ============================

/// 阅读器使用的单张图片数据。
///
/// [url] 为实际加载地址（或重组后的地址），[cacheKey] 用于 ImageCache 去重。
/// 禁漫图片重组后 url 可能会变，但 cacheKey 保持与重组前一致以确保缓存命中。
class ReaderImage {
  /// 图片加载 URL（重组后为实际地址）。
  final String url;

  /// ImageCache 去重键（应与最终送入图片加载器的 key 一致）。
  final String cacheKey;

  /// 源要求的网络图片请求头；本地图片为 null。
  final Map<String, String>? headers;

  const ReaderImage({required this.url, required this.cacheKey, this.headers});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderImage && cacheKey == other.cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}

// ============================ 图片加载函数 ============================

/// 阅读器获取章节图片的外部回调。
///
/// 由调用方（`reader.dart` 入口）在构造时注入，屏蔽源差异。
/// 接收漫画 id + 章节 ep，返回图片 URL 列表或错误。
typedef ReaderImageLoader =
    Future<Res<List<String>>> Function(String comicId, String? episodeKey);

/// 将源返回的图片 key 解析为实际 URL、请求头与缓存键。
typedef ReaderImageConfigResolver =
    Map<String, dynamic>? Function(
      String imageKey,
      String comicId,
      String episodeId,
    );

// ============================ BuildContext 扩展 ============================

extension BuildContextReader on BuildContext {
  ReaderProvider get reader => read<ReaderProvider>();
  ReaderProvider get watcher => watch<ReaderProvider>();
  T selector<T>(T Function(ReaderProvider) s) => select<ReaderProvider, T>(s);
}

// ============================ 加载状态 ============================

/// 章节图片加载状态。
enum ReaderLoadState { idle, loading, success, error }

/// ImagePreloadController 的最小引用契约。
///
/// 在 [ImagePreloadController] 实现（任务10）之前，先定义 ReaderProvider 所需的
/// 交互接口，使类型不依赖具体预加载实现。
abstract class ImagePreloadControllerRef {
  int? get cacheWidth;
  set cacheWidth(int? v);
  void replaceItems(List<ReaderImage> items);
  void onAnchorChanged(List<int> anchors);
  void invalidatePreloaded();
}

// ============================ ReaderProvider ============================

class ReaderProvider extends ChangeNotifier {
  ReaderProvider({
    required ComicState state,
    ReaderImageLoader? imageLoader,
    ReaderImageConfigResolver? imageConfigResolver,
    ReadRecordHelper? readRecordHelper,
    this.readRecordDebounce = const Duration(milliseconds: 250),
  }) : _imageLoader = imageLoader,
       _imageConfigResolver = imageConfigResolver,
       _readRecordHelper = readRecordHelper ?? ReadRecordHelper() {
    id = state.id;
    title = state.title;
    coverUrl = state.coverUrl;
    author = state.author;
    chapters = state.chapters;
    _chapter = state.chapter;
    _pageNo = state.pageNo < 0 ? 0 : state.pageNo;
    _sourceKey = state.sourceKey;
    _type = state.type;
    _scheduleReadRecordSave();
    _loadImageUrls();
  }

  // ============================ 基本信息 ============================

  /// 漫画 id。
  late final String id;

  /// 漫画标题。
  late final String title;

  /// 封面与作者用于写入可离线展示的完整历史元数据。
  late final String coverUrl;
  late final String author;

  /// 全部章节。
  late final List<ReaderChapter> chapters;

  /// 阅读源类型（网络 / 本地）。
  late final ReaderType _type;
  ReaderType get readerType => _type;

  /// 源 key（用于区分禁漫 / 哔咔，图片加载策略差异）。
  late final String _sourceKey;
  String get sourceKey => _sourceKey;

  /// 外部图片加载回调。
  final ReaderImageLoader? _imageLoader;

  /// 漫画源提供的单图请求配置。
  final ReaderImageConfigResolver? _imageConfigResolver;

  /// 阅读记录助手。
  final ReadRecordHelper _readRecordHelper;

  /// 连续翻页合并写入的等待时间。
  final Duration readRecordDebounce;

  // ============================ 章节切换 ============================

  /// 当前章节。
  late ReaderChapter _chapter;
  ReaderChapter get chapter => _chapter;
  set chapter(ReaderChapter c) {
    _chapter = c;
    notifyListeners();
  }

  /// 当前章节在 [chapters] 中的索引。
  int get chapterIndex => chapters.indexWhere((c) => c.id == _chapter.id);

  /// 是否为第一章。
  bool get isFirstChapter => chapter.id == chapters.first.id;

  /// 是否为最后一章。
  bool get isLastChapter => chapter.id == chapters.last.id;

  // ============================ 页码与图片列表 ============================

  /// 当前章节图片的 _原始_ 单页索引（非双页换算值）。
  int _pageNo = 0;

  /// 当前页码（双页模式下返回换算后值）。
  int get pageNo =>
      _readMode.isDoublePage ? toCorrectMultiPageNo(_pageNo, 2) : _pageNo;

  /// 设置当前页码（始终存储原始单页索引）。
  set pageNo(int index) => onPageNoChanged(index);

  /// 当前章节的图片 URL 列表。
  List<ReaderImage> _images = const [];
  List<ReaderImage> get images => _images;

  /// 双页模式下的图片分组缓存（每 2 张一组）。
  List<ReaderImage>? _multiPageImagesSource;
  List<List<ReaderImage>>? _multiPageImagesCache;
  List<List<ReaderImage>> get multiPageImages {
    final source = _images;
    final cache = _multiPageImagesCache;
    if (cache != null && identical(source, _multiPageImagesSource)) {
      return cache;
    }
    final next = splitList(source, 2);
    _multiPageImagesSource = source;
    _multiPageImagesCache = next;
    return next;
  }

  /// 当前章节总页数（双页模式下按分组计数）。
  int get pageCount =>
      _readMode.isDoublePage ? multiPageImages.length : _images.length;

  // ============================ 图片加载 ============================

  /// 图片加载状态。
  ReaderLoadState _loadingState = ReaderLoadState.idle;
  ReaderLoadState get loadingState => _loadingState;

  /// 读取错误信息。
  String? _loadingErrorMessage;
  String? get loadingErrorMessage => _loadingErrorMessage;

  int _loadGeneration = 0;
  bool _disposed = false;

  /// 加载当前章节图片 URL。
  ///
  /// 调用外部 [imageLoader] 获取图片列表，成功后更新 [_images] 并通知各子模块，
  /// 失败时置错误态留 UI 层展示 [ErrorPage]。
  Future<void> _loadImageUrls() async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    final chapterSnapshot = _chapter;
    final imageLoader = _imageLoader;

    _loadingState = ReaderLoadState.loading;
    _loadingErrorMessage = null;
    notifyListeners();

    if (imageLoader == null) {
      _setLoadError(generation, chapterSnapshot, '未配置章节图片加载器');
      return;
    }

    Log.i('Reader load images', 'chapter: ${chapterSnapshot.id}');

    try {
      final res = await imageLoader(
        id,
        chapterSnapshot.id.isNotEmpty ? chapterSnapshot.id : null,
      );
      if (!_isCurrentLoad(generation, chapterSnapshot)) return;

      if (res.error) {
        _setLoadError(
          generation,
          chapterSnapshot,
          res.errorMessage ?? '加载章节图片失败',
        );
        return;
      }

      final urls = res.data
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList(growable: false);
      if (urls.isEmpty) {
        _setLoadError(generation, chapterSnapshot, '该章节暂无图片');
        return;
      }

      final images = <ReaderImage>[
        for (final url in urls) _resolveReaderImage(url, chapterSnapshot.id),
      ];
      if (!_isCurrentLoad(generation, chapterSnapshot)) return;

      _images = List<ReaderImage>.unmodifiable(images);
      Log.i('Reader loaded', '${_images.length} images');
      _multiPageImagesCache = null;
      if (_pageNo >= _images.length) {
        _pageNo = _images.length - 1;
      }
      _loadingState = ReaderLoadState.success;
      _scheduleReadRecordSave();

      if (_preloadController != null) {
        _preloadController!.replaceItems(_images);
        final anchor = _readMode.isDoublePage
            ? toCorrectMultiPageNo(_pageNo, 2)
            : _pageNo;
        _preloadController!.onAnchorChanged([anchor]);
      }

      notifyListeners();
    } catch (error, stackTrace) {
      if (!_isCurrentLoad(generation, chapterSnapshot)) return;
      Log.e('Reader load threw', error: error, stackTrace: stackTrace);
      _setLoadError(
        generation,
        chapterSnapshot,
        '章节图片加载失败：${_readableError(error)}',
      );
    }
  }

  ReaderImage _resolveReaderImage(String imageKey, String episodeId) {
    final config = _imageConfigResolver?.call(imageKey, id, episodeId);
    final configuredUrl = config?['url'];
    final url = configuredUrl is String && configuredUrl.trim().isNotEmpty
        ? configuredUrl.trim()
        : imageKey;
    final configuredCacheKey = config?['cacheKey'];
    final cacheKey =
        configuredCacheKey is String && configuredCacheKey.trim().isNotEmpty
        ? configuredCacheKey.trim()
        : imageKey;
    final isStructured =
        config?.containsKey('url') == true ||
        config?.containsKey('headers') == true ||
        config?.containsKey('cacheKey') == true ||
        config?.containsKey('method') == true;
    final headers = _stringHeaders(isStructured ? config!['headers'] : config);
    return ReaderImage(url: url, cacheKey: cacheKey, headers: headers);
  }

  void _setLoadError(
    int generation,
    ReaderChapter chapterSnapshot,
    String message,
  ) {
    if (!_isCurrentLoad(generation, chapterSnapshot)) return;
    _loadingState = ReaderLoadState.error;
    _loadingErrorMessage = message;
    Log.e('Reader load failed', error: message);
    notifyListeners();
  }

  static Map<String, String>? _stringHeaders(Object? value) {
    if (value is! Map) return null;
    final headers = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is String && entry.value != null) {
        headers[entry.key as String] = entry.value.toString();
      }
    }
    return headers.isEmpty ? null : Map<String, String>.unmodifiable(headers);
  }

  static String _readableError(Object error) {
    final message = error.toString().trim();
    if (message.isEmpty) return '未知错误';
    return message.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  bool _isCurrentLoad(int generation, ReaderChapter chapterSnapshot) {
    return !_disposed &&
        generation == _loadGeneration &&
        chapterSnapshot.id == _chapter.id;
  }

  /// 重新加载当前章节（重试按钮回调）。
  void retry() => _loadImageUrls();

  // ============================ 章节导航 ============================

  /// 跳转到指定章节。
  void go(ReaderChapter target) {
    if (_disposed) return;
    Log.i('Reader go to chapter', '${target.id} - ${target.name}');
    _pageNoTimer?.cancel();
    _hasPendingReadRecord = false;
    _chapter = target;
    _pageNo = 0;
    notifyListeners();
    _scheduleReadRecordSave();
    // 切章后必须重置 PageController，否则 PageView 在新章节长度不足时会 clamp
    // 但不一定回调 onPageChanged，导致预加载锚点停留在旧章。
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
    _loadImageUrls();
  }

  /// 下一章。
  void goNext() {
    if (isLastChapter) return;
    go(chapters[chapterIndex + 1]);
  }

  /// 上一章。
  void goPrevious() {
    if (isFirstChapter) return;
    go(chapters[chapterIndex - 1]);
  }

  // ============================ 阅读记录（debounce 兜底） ============================

  Timer? _pageNoTimer;
  bool _hasPendingReadRecord = false;

  /// 生成当前完整恢复点；该纯逻辑入口也用于验证保存参数。
  ReadRecord buildReadRecord({int? updatedAt}) {
    return ReadRecord(
      source: _sourceKey,
      comic: id,
      title: title,
      cover: coverUrl,
      author: author,
      chapterId: _chapter.id,
      chapterTitle: _chapter.name,
      pageNo: _pageNo,
      pageCount: _images.length,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _scheduleReadRecordSave() {
    if (_disposed) return;
    _pageNoTimer?.cancel();
    _hasPendingReadRecord = true;
    _pageNoTimer = Timer(readRecordDebounce, _persistReadRecord);
  }

  void _persistReadRecord({bool allowDisposed = false}) {
    if (_disposed && !allowDisposed) return;
    _pageNoTimer = null;
    _hasPendingReadRecord = false;
    _readRecordHelper.upsert(buildReadRecord());
  }

  /// 更新当前原始单页索引并 debounce 保存完整阅读记录。
  void onPageNoChanged(int index) {
    final normalized = index < 0 ? 0 : index;
    if (normalized == _pageNo && !_hasPendingReadRecord) return;
    if (normalized != _pageNo) {
      _pageNo = normalized;
      notifyListeners();
    }
    _scheduleReadRecordSave();
  }

  // ============================ 阅读模式 ============================

  ReadMode _readMode = ReaderConf.instance.readMode;
  ReadMode get readMode => _readMode;
  set readMode(ReadMode mode) {
    _readMode = mode;
    ReaderConf.instance.readMode = mode;
    notifyListeners();
  }

  // ============================ 滚动/翻页控制器 ============================

  /// [VerticalList] 精确滚动偏移控制器（scrollable_positioned_list）。
  final scrollOffsetController = ScrollOffsetController();

  /// [VerticalList] 条目滚动控制器。
  final itemScrollController = ItemScrollController();

  /// [HorizontalList] PageView 控制器。
  final PageController _pageController = PageController();
  PageController get pageController => _pageController;

  // ============================ 工具栏显隐 ============================

  /// 是否显示顶部/底部工具栏。
  bool showToolbar = false;

  /// 是否显示菜单锁定按钮。
  bool showMenuLock = false;

  /// 锁定状态下菜单锁定按钮是否展开。
  bool menuLockExpanded = false;

  /// 展开锁定状态下的菜单锁定按钮。
  void expandMenuLock() {
    if (menuLockExpanded) return;
    menuLockExpanded = true;
    notifyListeners();
  }

  /// 收起锁定状态下的菜单锁定按钮。
  void collapseMenuLock() {
    if (!menuLockExpanded) return;
    menuLockExpanded = false;
    notifyListeners();
  }

  /// 隐藏菜单锁定按钮。
  void hideMenuLock() {
    if (!showMenuLock && !menuLockExpanded) return;
    showMenuLock = false;
    menuLockExpanded = false;
    notifyListeners();
  }

  /// 隐藏工具栏（仅在显示时生效）。
  void hideToolbar() {
    if (!showToolbar) {
      hideMenuLock();
      return;
    }
    openOrCloseToolbar();
  }

  /// 切换工具栏显示状态。
  ///
  /// 工具栏打开时暂停自动翻页（定时/平滑），关闭时恢复。
  void openOrCloseToolbar() {
    Future.microtask(() {
      final willShowToolbar = !showToolbar;

      if (willShowToolbar) {
        if (_isPageTurning) {
          turnPageTimer?.cancel();
          turnPageTimer = null;
          _smoothTicker?.stop();
          _isPageTurnPausedByToolbar = true;
        }
      } else if (_isPageTurning && _isPageTurnPausedByToolbar) {
        if (_isSmoothScroll) {
          _smoothTicker?.start();
        } else {
          _startPageTurnTimer();
        }
        _isPageTurnPausedByToolbar = false;
      }

      showToolbar = willShowToolbar;
      showMenuLock = willShowToolbar;
      if (!willShowToolbar) {
        menuLockExpanded = false;
      }
      SystemChrome.setEnabledSystemUIMode(
        showToolbar ? SystemUiMode.edgeToEdge : SystemUiMode.immersive,
      );
      notifyListeners();
    });
  }

  // ============================ 翻页：Slider ============================

  /// 底部工具栏 Slider 拖动回调。
  void onSliderChanged(int index) {
    onPageNoChanged(index);
    if (_readMode.isVertical) {
      itemScrollController.jumpTo(index: index);
    } else {
      _pageController.jumpToPage(index);
    }
  }

  // ============================ 翻页：VerticalList ============================

  /// [VerticalList] 翻页（按偏移量滚动）。
  void pageTurnForVertical(double offset) {
    if (!itemScrollController.isAttached) return;

    if (_pageNo == 0 && offset < 0) {
      if (!isFirstChapter) {
        goPrevious();
      } else {
        Toast.show(message: '没有上一章了');
      }
      return;
    }

    if (_pageNo == _images.length - 1 && offset > 0) {
      if (!isLastChapter) {
        goNext();
      } else {
        stopPageTurn();
        Toast.show(message: '没有下一章了');
      }
      return;
    }

    if (ReaderConf.instance.enablePageAnimation) {
      scrollOffsetController.animateScroll(
        offset: offset,
        duration: const Duration(milliseconds: 200),
      );
    } else {
      scrollOffsetController.animateScroll(
        offset: offset,
        duration: Duration.zero,
      );
    }
  }

  // ============================ 翻页：HorizontalList ============================

  /// [HorizontalList] 翻页。
  void pageTurnForHorizontal([bool isTurnNext = true]) {
    void previousPage() {
      if (_pageNo == 0) {
        if (!isFirstChapter) {
          goPrevious();
        } else {
          Toast.show(message: '没有上一章了');
        }
        return;
      }

      if (ReaderConf.instance.enablePageAnimation) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.linear,
        );
      } else {
        _pageController.jumpToPage(_pageController.page!.round() - 1);
      }
    }

    void nextPage() {
      if (_pageNo == pageCount - 1) {
        if (!isLastChapter) {
          goNext();
        } else {
          stopPageTurn();
          Toast.show(message: '没有下一章了');
        }
        return;
      }

      if (ReaderConf.instance.enablePageAnimation) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.linear,
        );
      } else {
        _pageController.jumpToPage(_pageController.page!.round() + 1);
      }
    }

    isTurnNext ? nextPage() : previousPage();
  }

  // ============================ 统一翻页 ============================

  /// 向前翻一页（模式自适应）。
  void prev() {
    if (_readMode.isVertical) {
      pageTurnForVertical(screenHeight * ReaderConf.instance.slipFactor * -1);
    } else {
      pageTurnForHorizontal(false);
    }
  }

  /// 向后翻一页（模式自适应）。
  void next() {
    if (_readMode.isVertical) {
      pageTurnForVertical(screenHeight * ReaderConf.instance.slipFactor);
    } else {
      pageTurnForHorizontal();
    }
  }

  // ============================ 自动翻页（定时） ============================

  bool _isPageTurning = false;

  /// 是否为平滑滚动模式（vs 定时翻页）。
  bool _isSmoothScroll = false;
  bool get isSmoothScroll => _isSmoothScroll;

  /// 由工具栏打开而暂停的标记（工具栏关闭后恢复）。
  bool _isPageTurnPausedByToolbar = false;

  /// 是否正在自动翻页。
  bool get isPageTurning => _isPageTurning;
  set isPageTurning(bool value) {
    _isPageTurning = value;
    notifyListeners();
  }

  /// 定时翻页定时器。
  Timer? turnPageTimer;

  /// 定时翻页间隔（秒）。
  int _interval = ReaderConf.instance.interval;
  int get interval => _interval;
  set interval(int v) {
    _interval = v;
    ReaderConf.instance.interval = v;
    notifyListeners();
  }

  void _startPageTurnTimer() {
    turnPageTimer?.cancel();
    turnPageTimer = Timer.periodic(Duration(seconds: _interval), (timer) {
      if (_loadingState == ReaderLoadState.loading) return;
      next();
    });
  }

  /// 开始定时翻页。
  void startPageTurn() {
    _isSmoothScroll = false;
    _isPageTurnPausedByToolbar = false;
    _startPageTurnTimer();
    isPageTurning = true;
  }

  // ============================ 自动翻页（平滑滚动） ============================

  /// 平滑滚动 Ticker。
  Ticker? _smoothTicker;

  /// 平滑滚动速度（每帧像素数）。
  double _scrollSpeed = ReaderConf.instance.scrollSpeed;
  double get scrollSpeed => _scrollSpeed;
  set scrollSpeed(double value) {
    _scrollSpeed = value;
    ReaderConf.instance.scrollSpeed = value;
    notifyListeners();
  }

  void updateScrollSpeed(double speed) {
    scrollSpeed = speed;
  }

  /// 开始平滑滚动（竖直连续模式下的自动滚屏）。
  void startSmoothScroll(TickerProvider vsync) {
    _isSmoothScroll = true;
    _isPageTurnPausedByToolbar = false;
    _smoothTicker?.dispose();
    _smoothTicker = vsync.createTicker((_) {
      if (_loadingState == ReaderLoadState.loading) return;
      if (!itemScrollController.isAttached) return;
      if (_pageNo == _images.length - 1) {
        if (!isLastChapter) {
          goNext();
        } else {
          stopPageTurn();
          Toast.show(message: '没有下一章了');
        }
        return;
      }
      scrollOffsetController.animateScroll(
        offset: _scrollSpeed,
        duration: Duration.zero,
      );
    });
    _smoothTicker!.start();
    isPageTurning = true;
  }

  /// 停止自动翻页（定时 & 平滑通用）。
  void stopPageTurn() {
    turnPageTimer?.cancel();
    turnPageTimer = null;
    _smoothTicker?.stop();
    _smoothTicker?.dispose();
    _smoothTicker = null;
    _isSmoothScroll = false;
    _isPageTurnPausedByToolbar = false;
    isPageTurning = false;
  }

  /// 更新定时翻页间隔。
  void updateInterval(int interval) {
    this.interval = interval;
  }

  // ============================ 预加载控制器引用 ============================

  /// 图片预加载控制器引用（由 [ImagePreloadController] 实现在任务10 填写）。
  ///
  /// ReaderProvider 持有引用但不管理其生命周期——由 [VerticalList] /
  /// [HorizontalList] 在 initState 时初始化并调用 [initPreloadController]。
  ImagePreloadControllerRef? _preloadController;

  /// 预加载控制器（公开读取，供 HorizontalList 等使用）。
  ImagePreloadControllerRef? get preloadController => _preloadController;

  /// 初始化预加载控制器引用。
  ///
  /// 由列表 widget 在创建 [ImagePreloadController] 后调用，使 ReaderProvider
  /// 在章节切换 / 图片加载完成后能通知预加载控制器。
  void initPreloadController(ImagePreloadControllerRef controller) {
    _preloadController = controller;
  }

  /// 更新预加载解码宽度（与显示端保持一致，保证 ImageCache 命中）。
  void updatePreloadCacheWidth(int? cacheWidth) {
    if (_preloadController == null) return;
    if (_preloadController!.cacheWidth == cacheWidth) return;
    _preloadController!.cacheWidth = cacheWidth;
    _preloadController!.invalidatePreloaded();
  }

  // ============================ 资源释放 ============================

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loadGeneration++;
    _pageController.dispose();
    turnPageTimer?.cancel();
    _smoothTicker?.dispose();
    _pageNoTimer?.cancel();
    _pageNoTimer = null;
    if (_hasPendingReadRecord) {
      _persistReadRecord(allowDisposed: true);
    }
    super.dispose();
  }
}
