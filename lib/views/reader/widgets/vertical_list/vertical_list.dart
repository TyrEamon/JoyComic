/// 竖直连续模式（条漫流）。
///
/// 使用 [ScrollablePositionedList] + [GestureWrapper]（自定义 [InteractiveViewer]）
/// 实现可缩放、可定位的连续漫画阅读体验。
///
/// 布局结构：
/// ```
/// GestureWrapper（三区点击翻页 / 双指缩放 / 双击放大）
///   └── FractionallySizedBox（宽度比例控制）
///         └── ScrollablePositionedList.builder
///               ├── 图片项 × pageCount
///               └── "本章完" 占位项
/// ```
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
          final widthFactor = widthRatio.clamp(0.0, 1.0);
          final imageLayoutWidth = constraints.maxWidth * widthFactor;
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final cacheWidth = computeImageCacheWidth(
            layoutWidth: imageLayoutWidth,
            devicePixelRatio: dpr,
          );
          // 预加载使用同一个 cacheWidth，保证 ImageCache 命中。
          context.reader.updatePreloadCacheWidth(cacheWidth);

          return FractionallySizedBox(
            widthFactor: widthFactor,
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
                // 最后一项："本章完" 占位。
                if (index == pageCount) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Text(
                      '本章完',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }

                final item = images[index];
                return ReaderImage(
                  key: ValueKey(item.cacheKey),
                  url: item.url,
                  cacheKey: item.cacheKey,
                  headers: item.headers,
                  fallbackUrls: item.fallbackUrls,
                  bytesTransformer: item.bytesTransformer,
                  cacheWidth: cacheWidth,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
