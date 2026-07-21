/// 竖直连续模式（条漫流）。
///
/// 对齐  `image_view.dart` buildType4：
/// ScrollablePositionedList + ComicImage(width, height=width*1.2, fit: cover)
/// 图片上屏走移植的  ComicImage 路径（RawImage + size cache）。
library;

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../foundation/reader_config.dart';
import '../../providers/reader_provider.dart' hide ReaderImage;
import '../../providers/list_state_provider.dart';
import '../../utils/image_preload_controller.dart';
import '../../utils/reader_utils.dart';
import '../reader_image.dart';
import 'gesture.dart';
import 'page_index.dart';

/// 竖直连续模式。
class VerticalList extends StatefulWidget {
  const VerticalList({super.key});

  @override
  State<VerticalList> createState() => _VerticalListState();
}

class _VerticalListState extends State<VerticalList> {
  /// 列表项位置监听器，用于追踪当前可见区域。
  final itemPositionsListener = ItemPositionsListener.create();

  /// 图片预加载控制器（生命周期由本 widget 管理）。
  ImagePreloadController? _preloadController;

  // ============================ 生命周期 ============================

  @override
  void initState() {
    super.initState();

    // 初始化预加载控制器并注入 ReaderProvider。
    _initPreloadController();

    // 监听位置变化→更新页码+预加载锚点。
    itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
  }

  void _initPreloadController() {
    final reader = context.reader;
    _preloadController = ImagePreloadController(
      context: context,
      items: reader.images,
      type: reader.readerType,
      maxPreloadCount: ReaderConf.instance.preloadImageCount,
      traceId: reader.traceId,
    );
    reader.initPreloadController(_preloadController!);
  }

  @override
  void dispose() {
    itemPositionsListener.itemPositions.removeListener(_onItemPositionsChanged);
    _preloadController?.dispose();
    super.dispose();
  }

  // ============================ 列表项位置变化 ============================

  void _onItemPositionsChanged() {
    final positions = itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final visibleIndices = visibleVerticalImageIndices(
      positions,
      imageCount: context.reader.images.length,
    );
    if (visibleIndices.isEmpty) return;

    final lastIndex = visibleIndices.last;

    _preloadController?.onAnchorChanged(visibleIndices);
    context.reader.onPageNoChanged(lastIndex);
  }

  // ============================ 构建 ============================

  @override
  Widget build(BuildContext context) {
    final physics = context.stateSelector((p) => p.physics);
    final widthRatio = context.stateSelector((p) => p.verticalListWidthRatio);
    final pageCount = context.selector((p) => p.pageCount);
    final images = context.selector((p) => p.images);
    // 仅在首次构建时读取 pageNo，不监听后续变化。
    final initialPage = context.reader.pageNo;

    return GestureWrapper(
      openOrCloseToolbar: context.reader.openOrCloseToolbar,
      jumpOffset: context.reader.pageTurnForVertical,
      child: LayoutBuilder(
        builder: (context, constraints) {
          //  continuous vertical: full list width, image width
          // optionally capped for landscape (height/width < 1.2).
          final screenW = constraints.maxWidth;
          final screenH = constraints.maxHeight;
          final widthFactor = widthRatio.clamp(0.0, 1.0);
          var imageWidth = screenW * widthFactor;
          if (imageWidth <= 0) imageWidth = screenW;
          if (screenH / screenW < 1.2) {
            // Match  landscape clamp when enabled via width ratio.
            final capped = screenH / 1.2;
            if (capped < imageWidth) imageWidth = capped;
          }

          final dpr = MediaQuery.devicePixelRatioOf(context);
          final cacheWidth = computeImageCacheWidth(
            layoutWidth: imageWidth,
            devicePixelRatio: dpr,
          );
          // 预加载使用同一个 cacheWidth，保证 ImageCache 命中。
          context.reader.updatePreloadCacheWidth(cacheWidth);

          //  initial placeholder height = imageWidth * 1.2;
          // ComicImage then rewrites height from decoded size cache.
          final placeholderHeight = imageWidth * 1.2;

          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: imageWidth,
              height: screenH,
              child: ScrollablePositionedList.builder(
                initialScrollIndex: initialPage,
                padding: EdgeInsets.zero,
                physics: physics,
                itemCount: pageCount + 1,
                addAutomaticKeepAlives: false,
                minCacheExtent: screenHeight * 2,
                itemScrollController: context.reader.itemScrollController,
                itemPositionsListener: itemPositionsListener,
                scrollOffsetController: context.reader.scrollOffsetController,
                itemBuilder: (context, index) {
                  if (index == pageCount) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Text(
                        '本章完',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20.0,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFECECEC),
                        ),
                      ),
                    );
                  }

                  final item = images[index];
                  //  continuous: ComicImage(width, height: w*1.2,
                  // fit: cover). ComicImage itself then drives height from
                  // decoded size cache (constructor height is config only).
                  return ReaderImage(
                    key: ValueKey(item.cacheKey),
                    url: item.url,
                    cacheKey: item.cacheKey,
                    headers: item.headers,
                    fallbackUrls: item.fallbackUrls,
                    bytesTransformer: item.bytesTransformer,
                    cacheWidth: cacheWidth,
                    width: imageWidth,
                    height: placeholderHeight,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    traceId: context.reader.traceId,
                    imageIndex: index,
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
