/// 竖直连续模式（条漫流）。
///
/// ScrollablePositionedList + ReaderImage。
/// 图片上屏走 ImageStream → RawImage，高度由解码尺寸缓存驱动。
///
/// 关键：列表交叉轴宽度必须来自 [MediaQuery] 兜底，不能依赖可能为 0
/// 的 LayoutBuilder 约束（真机日志曾出现 size=960x1378 layout=0x0 黑屏）。
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

  /// 解析可用布局宽：约束优先，否则 MediaQuery，再否则 390。
  ///
  /// 绝不能返回 0/NaN/Infinity，否则 RawImage 会以 layout=0 画成黑屏。
  double _safeLayoutWidth(BoxConstraints constraints) {
    final mq = MediaQuery.sizeOf(context);
    double w = 0;
    if (constraints.hasBoundedWidth &&
        constraints.maxWidth.isFinite &&
        constraints.maxWidth > 0) {
      w = constraints.maxWidth;
    } else if (mq.width.isFinite && mq.width > 0) {
      w = mq.width;
    }
    if (w <= 0 || !w.isFinite) w = 390;
    return w;
  }

  double _safeLayoutHeight(BoxConstraints constraints) {
    final mq = MediaQuery.sizeOf(context);
    double h = 0;
    if (constraints.hasBoundedHeight &&
        constraints.maxHeight.isFinite &&
        constraints.maxHeight > 0) {
      h = constraints.maxHeight;
    } else if (mq.height.isFinite && mq.height > 0) {
      h = mq.height;
    }
    if (h <= 0 || !h.isFinite) h = screenHeight > 0 ? screenHeight : 844;
    return h;
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
          final screenW = _safeLayoutWidth(constraints);
          final screenH = _safeLayoutHeight(constraints);

          // widthRatio 默认 1.0；若被写成 0 也强制回退到全宽。
          final widthFactor = widthRatio.clamp(0.05, 1.0);
          var imageWidth = screenW * widthFactor;
          if (imageWidth <= 0 || !imageWidth.isFinite) {
            imageWidth = screenW;
          }
          // 横屏略收窄，避免超宽条带。
          if (screenW > 0 && screenH / screenW < 1.2) {
            final capped = screenH / 1.2;
            if (capped.isFinite && capped > 0 && capped < imageWidth) {
              imageWidth = capped;
            }
          }

          final dpr = MediaQuery.devicePixelRatioOf(context);
          final cacheWidth = computeImageCacheWidth(
            layoutWidth: imageWidth,
            devicePixelRatio: dpr,
          );
          // 预加载使用同一个 cacheWidth，保证 ImageCache 命中。
          context.reader.updatePreloadCacheWidth(cacheWidth);

          // 占位高度；解码后 ReaderImage 按真实宽高比重写。
          final placeholderHeight = imageWidth * 1.2;

          // 用 Center + 固定宽，而不是 Align 吃零宽约束。
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: SizedBox(
                width: imageWidth,
                height: screenH,
                child: ScrollablePositionedList.builder(
                  initialScrollIndex: initialPage.clamp(0, pageCount),
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
                      fit: BoxFit.fitWidth,
                      filterQuality: FilterQuality.medium,
                      traceId: context.reader.traceId,
                      imageIndex: index,
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
