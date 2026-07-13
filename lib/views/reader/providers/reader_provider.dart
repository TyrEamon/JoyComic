/// 阅读器内容态 Provider。
///
/// 管理阅读器的核心内容状态：当前章节、页码、图片列表、工具栏显隐、自动翻页、
/// 阅读记录。与 [ListStateProvider]（UI 态）分离，遵循单一职责。
library reader_provider;

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

  const ReaderImage({required this.url, required this.cacheKey});

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

// ============================ BuildContext 扩展 ============================

extension BuildContextReader on BuildContext {
  ReaderProvider get reader => read<ReaderProvider>();
  ReaderProvider get watcher => watch<ReaderProvider>();
  T selector<T>(T Function(ReaderProvider) s) =>
      select<ReaderProvider, T>(s);
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
  })  : _imageLoader = imageLoader {
    id = state.id;
    title = state.title;
    chapters = state.chapters;
    _chapter = state.chapter;
    _pageNo = state.pageNo;
    _sourceKey = state.sourceKey;
    _type = state.type;
    _loadImageUrls();
  }

  // ============================ 基本信息 ============================

  /// 漫画 id。
  late final String id;

  /// 漫画标题。
  late final String title;

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

  /// 阅读记录助手。
  final _readRecordHelper = ReadRecordHelper();

  // ============================ 章节切换 ============================

  /// 当前章节。
  late ReaderChapter _chapter;
  ReaderChapter get chapter => _chapter;
  set chapter(ReaderChapter c) {
    _chapter = c;
    notifyListeners();
  }

  /// 当前章节在 [chapters] 中的索引。
  int get chapterIndex =>
      chapters.indexWhere((c) => c.id == _chapter.id);

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
  set pageNo(int index) {
    _pageNo = index;
    notifyListeners();
  }

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

  /// 加载当前章节图片 URL。
  ///
  /// 调用外部 [imageLoader] 获取图片列表，成功后更新 [_images] 并通知各子模块，
  /// 失败时置错误态留 UI 层展示 [ErrorPage]。
  Future<void> _loadImageUrls() async {
    if (_imageLoader == null) return;
    _loadingState = ReaderLoadState.loading;
    notifyListeners();

    Log.i('Reader load images', 'chapter: ${_chapter.id}');

    final res = await _imageLoader!(id, _chapter.id.isNotEmpty ? _chapter.id : null);

    if (res.error) {
      _loadingState = ReaderLoadState.error;
      _loadingErrorMessage = res.errorMessage ?? '加载章节图片失败';
      Log.e('Reader load failed', error: res.errorMessage);
      notifyListeners();
      return;
    }

    final urls = res.data;
    if (urls == null || urls.isEmpty) {
      _loadingState = ReaderLoadState.error;
      _loadingErrorMessage = '该章节暂无图片';
      Log.w('Reader load empty', 'chapter ${_chapter.id} has no images');
      notifyListeners();
      return;
    }

    _images = urls.map((url) => ReaderImage(url: url, cacheKey: url)).toList();
    Log.i('Reader loaded', '${_images.length} images');
    _multiPageImagesCache = null; // 强制重建分组缓存
    _loadingState = ReaderLoadState.success;

    // 通知预加载控制器（如已初始化）
    if (_preloadController != null) {
      _preloadController!.replaceItems(_images);
      final anchor =
          _readMode.isDoublePage ? toCorrectMultiPageNo(_pageNo, 2) : _pageNo;
      _preloadController!.onAnchorChanged([anchor]);
    }

    notifyListeners();
  }

  /// 重新加载当前章节（重试按钮回调）。
  void retry() => _loadImageUrls();

  // ============================ 章节导航 ============================

  /// 跳转到指定章节。
  void go(ReaderChapter target) {
    Log.i('Reader go to chapter', '${target.id} - ${target.name}');
    chapter = target;
    _pageNo = 0;
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
  int? _pendingReadRecordPageNo;

  /// 更新当前页码并 debounce 保存阅读记录。
  ///
  /// [index] 始终使用原始单页索引（非双页换算），与 [_pageNo] 内部存储一致。
  void onPageNoChanged(int index) {
    if (_pendingReadRecordPageNo == index) return;
    if (index == _pageNo && _pendingReadRecordPageNo == null) return;
    _pageNoTimer?.cancel();
    if (index != _pageNo) {
      _pageNo = index;
      notifyListeners();
    }
    _pendingReadRecordPageNo = index;
    _pageNoTimer = Timer(const Duration(milliseconds: 50), () {
      _pendingReadRecordPageNo = null;
      _readRecordHelper.save(
        comicId: id,
        sourceKey: _sourceKey,
        chapterId: _chapter.id,
        pageNo: index,
      );
    });
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
    _pageNo = index;
    notifyListeners();
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
      scrollOffsetController.scrollTo(offset);
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
      scrollOffsetController.scrollTo(_scrollSpeed);
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

  /// 图片预加载控制器（由 [ImagePreloadController] 实现在任务10 填写）。
  ///
  /// ReaderProvider 持有引用但不管理其生命周期——由 [VerticalList] /
  /// [HorizontalList] 在 initState 时初始化并调用 [initPreloadController]。
  ImagePreloadControllerRef? _preloadController;

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
    _pageController.dispose();
    turnPageTimer?.cancel();
    _smoothTicker?.dispose();
    _pageNoTimer?.cancel();
    super.dispose();
  }
}
