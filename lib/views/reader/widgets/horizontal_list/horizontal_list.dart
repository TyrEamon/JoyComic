/// 横向翻页模式（PhotoViewGallery 单页/双页）。
///
/// 使用 [PhotoViewGallery] 实现单页或双页翻页阅读模式。
/// 双页模式将图片两两分组（经 [ReaderProvider.multiPageImages]）后
/// 以 [Row] 并排渲染，RTL 模式自动反转图片顺序。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../../../../foundation/reader_config.dart';
import '../../providers/list_state_provider.dart';
import '../../providers/reader_provider.dart';
import '../../state/read_mode.dart';
import '../../utils/image_preload_controller.dart';
import '../../utils/reader_utils.dart';
import '../../utils/reader_image_provider.dart';
import '../reader_image.dart' as img_widget;

/// 横向翻页模式。
class HorizontalList extends StatefulWidget {
  const HorizontalList({super.key});

  @override
  State<HorizontalList> createState() => _HorizontalListState();
}

class _HorizontalListState extends State<HorizontalList> {
  ImagePreloadController? _preloadController;

  @override
  void initState() {
    super.initState();
    final reader = context.reader;
    _preloadController = ImagePreloadController(
      context: context,
      items: reader.images,
      type: reader.readerType,
      maxPreloadCount: ReaderConf.instance.preloadImageCount,
    );
    reader.initPreloadController(_preloadController!);
  }

  @override
  void dispose() {
    _preloadController?.dispose();
    super.dispose();
  }

  /// 当前章节 ID，用于图片缓存清理。
  String get cid => context.reader.id;

  void jumpToPage() {
    final initialIndex = context.reader.pageNo;
    context.reader.pageController.jumpToPage(initialIndex);
    _onPageChanged(initialIndex);
  }

  late TapDownDetails _tapDetails;

  // ============================ 点击翻页 ============================

  void _handleTap() {
    final conf = ReaderConf.instance;

    if (!conf.enableGesture) {
      context.reader.openOrCloseToolbar();
      return;
    }

    final width = context.width;
    final centerFraction = conf.horizontalCenterFraction;
    final leftFraction = (1 - centerFraction) / 2;
    final leftWidth = width * leftFraction;
    final centerWidth = width * centerFraction;
    final dx = _tapDetails.localPosition.dx;
    final isReverse = context.reader.readMode.isReverse;

    if (dx < leftWidth) {
      context.reader.pageTurnForHorizontal(isReverse);
    } else if (dx < (leftWidth + centerWidth)) {
      context.reader.openOrCloseToolbar();
    } else {
      context.reader.pageTurnForHorizontal(!isReverse);
    }
  }

  void _handleLockTap() {
    final conf = ReaderConf.instance;
    if (!conf.enableGesture) return;

    final width = context.width;
    final halfWidth = width / 2;
    final dx = _tapDetails.localPosition.dx;
    final isReverse = context.reader.readMode.isReverse;

    if (dx < halfWidth) {
      context.reader.pageTurnForHorizontal(isReverse);
    } else {
      context.reader.pageTurnForHorizontal(!isReverse);
    }
  }

  // ============================ 鼠标滚轮 ============================

  bool _scrollLock = false;

  void _handleScroll(PointerScrollEvent event) {
    if (_scrollLock) return;
    _scrollLock = true;

    if (event.scrollDelta.dy > 0) {
      context.reader.pageTurnForHorizontal();
    } else if (event.scrollDelta.dy < 0) {
      context.reader.pageTurnForHorizontal(false);
    }

    Future.delayed(const Duration(milliseconds: 200), () {
      _scrollLock = false;
    });
  }

  // ============================ 模式切换页码跳转 ============================

  bool? _lastIsDoublePage;

  // ============================ 构建 ============================

  @override
  Widget build(BuildContext context) {
    final pageCount = context.selector((p) => p.pageCount);
    final images = context.selector((p) => p.images);
    final multiPageImages = context.selector((p) => p.multiPageImages);
    final readMode = context.selector((p) => p.readMode);

    // 仅在单页 / 双页模式切换时做一次页码跳转
    if (_lastIsDoublePage != readMode.isDoublePage) {
      _lastIsDoublePage = readMode.isDoublePage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        jumpToPage();
      });
    }

    return GestureDetector(
      onTapDown: (details) => _tapDetails = details,
      onTap: () {
        context.stateReader.lockMenu ? _handleLockTap() : _handleTap();
      },
      child: Listener(
        onPointerSignal: (event) {
          if (HardwareKeyboard.instance.isControlPressed) return;
          if (event is PointerScrollEvent) _handleScroll(event);
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final dpr = MediaQuery.devicePixelRatioOf(context);
            final singleCacheWidth = computeImageCacheWidth(
              layoutWidth: constraints.maxWidth,
              devicePixelRatio: dpr,
            );
            final doubleCacheWidth = computeImageCacheWidth(
              layoutWidth: constraints.maxWidth / 2,
              devicePixelRatio: dpr,
            );
            final cacheWidth = readMode.isDoublePage
                ? doubleCacheWidth
                : singleCacheWidth;
            context.reader.updatePreloadCacheWidth(cacheWidth);

            // 构建 PhotoViewGallery 页面选项列表
            final pageOptions = List.generate(pageCount, (index) {
              if (!readMode.isDoublePage) {
                return _buildSinglePageOptions(images[index], singleCacheWidth);
              }
              return _buildDoublePageOptions(
                multiPageImages[index],
                readMode,
                doubleCacheWidth,
                constraints,
              );
            });

            return PhotoViewGallery(
              backgroundDecoration: BoxDecoration(
                color: context.colorScheme.surfaceContainerLowest,
              ),
              scrollPhysics: const BouncingScrollPhysics(),
              pageController: context.reader.pageController,
              onPageChanged: _onPageChanged,
              reverse: readMode.isReverse,
              pageOptions: pageOptions,
              loadingBuilder: (context, event) {
                final bytes = event?.cumulativeBytesLoaded ?? 0;
                double? value;
                final total = event?.expectedTotalBytes;
                if (total != null && total > 0) {
                  value = (bytes / total).clamp(0.0, 1.0);
                }
                return Center(
                  child: CircularProgressIndicator(
                    value: value,
                    strokeWidth: 3,
                    constraints: const BoxConstraints(
                      maxWidth: 28,
                      maxHeight: 28,
                    ),
                    strokeCap: StrokeCap.round,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ============================ 单页选项 ============================

  PhotoViewGalleryPageOptions _buildSinglePageOptions(
    ReaderImage item,
    int cacheWidth,
  ) {
    return PhotoViewGalleryPageOptions(
      minScale: PhotoViewComputedScale.contained * 1.0,
      maxScale: PhotoViewComputedScale.covered * 4.0,
      imageProvider: readerImageProvider(
        url: item.url,
        cacheKey: item.cacheKey,
        fallbackUrls: item.fallbackUrls,
        headers: item.headers,
        bytesTransformer: item.bytesTransformer,
        cacheWidth: cacheWidth,
      ),
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined, size: 40),
              const SizedBox(height: 10),
              const Text('图片加载失败'),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
                onPressed: () async {
                  await readerImageProvider(
                    url: item.url,
                    cacheKey: item.cacheKey,
                    fallbackUrls: item.fallbackUrls,
                    headers: item.headers,
                    bytesTransformer: item.bytesTransformer,
                    cacheWidth: cacheWidth,
                  ).evict();
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================ 双页选项 ============================

  PhotoViewGalleryPageOptions _buildDoublePageOptions(
    List<ReaderImage> items,
    ReadMode readMode,
    int cacheWidth,
    BoxConstraints constraints,
  ) {
    return PhotoViewGalleryPageOptions.customChild(
      childSize: Size(constraints.maxWidth, constraints.maxHeight) * 2,
      minScale: PhotoViewComputedScale.contained * 1.0,
      maxScale: PhotoViewComputedScale.covered * 10.0,
      child: _buildPageImagesRow(items, readMode.isReverse, cacheWidth),
    );
  }

  Widget _buildPageImagesRow(
    List<ReaderImage> items,
    bool isReverse,
    int cacheWidth,
  ) {
    final correctImages = isReverse ? items.reversed.toList() : items;
    return Row(
      children: correctImages.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final count = correctImages.length;
        return Expanded(
          child: img_widget.ReaderImage(
            key: ValueKey(item.cacheKey),
            url: item.url,
            cacheKey: item.cacheKey,
            headers: item.headers,
            fallbackUrls: item.fallbackUrls,
            bytesTransformer: item.bytesTransformer,
            cacheWidth: cacheWidth,
            alignment: count == 1
                ? Alignment.center
                : (idx == 0 ? Alignment.centerRight : Alignment.centerLeft),
          ),
        );
      }).toList(),
    );
  }

  // ============================ 缓存清理 ============================

  // ============================ 页面变化 ============================

  void _onPageChanged(int index) {
    final isDoublePage = context.reader.readMode.isDoublePage;
    final i = isDoublePage ? toCorrectSinglePageNo(index, 2) : index;

    context.reader.preloadController?.onAnchorChanged([i]);
    context.reader.onPageNoChanged(i);
  }
}
