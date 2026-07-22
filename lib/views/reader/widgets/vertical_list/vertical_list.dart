/// 竖直连续阅读 —— 对齐 HakaComic 可工作结构。
///
/// ## 与黑屏版的关键差异
/// - 使用 [ScrollablePositionedList]（精确定位 + 页码联动）
/// - 每页 [ReaderImage] **自己按宽高比撑开高度**，无固定槽、无 [Expanded]
/// - 解码后只写尺寸缓存，**不**对列表做 setState 改槽高
/// - 不包整表 [InteractiveViewer]（真机黑屏）
library;

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../foundation/reader_config.dart';
import '../../providers/list_state_provider.dart';
import '../../providers/reader_provider.dart' hide ReaderImage;
import '../../utils/image_preload_controller.dart';
import '../../utils/reader_pipeline.dart';
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
  final ItemPositionsListener _positionsListener =
      ItemPositionsListener.create();
  ImagePreloadController? _preloadController;
  bool _loggedOpen = false;

  @override
  void initState() {
    super.initState();
    final reader = context.reader;
    _preloadController = ImagePreloadController(
      context: context,
      items: reader.images,
      type: reader.readerType,
      maxPreloadCount: ReaderConf.instance.preloadImageCount,
      traceId: reader.traceId,
    );
    reader.initPreloadController(_preloadController!);
    _positionsListener.itemPositions.addListener(_onPositionsChanged);
  }

  @override
  void dispose() {
    _positionsListener.itemPositions.removeListener(_onPositionsChanged);
    _preloadController?.dispose();
    super.dispose();
  }

  void _onPositionsChanged() {
    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    final count = context.reader.images.length;
    final visible = visibleVerticalImageIndices(
      positions,
      imageCount: count,
    );
    if (visible.isEmpty) return;
    _preloadController?.onAnchorChanged(visible);
    context.reader.onPageNoChanged(visible.last);
  }

  @override
  Widget build(BuildContext context) {
    final physics = context.stateSelector((p) => p.physics);
    final widthRatio = context.stateSelector((p) => p.verticalListWidthRatio);
    final pageCount = context.selector((p) => p.pageCount);
    final images = context.selector((p) => p.images);
    final traceId = context.reader.traceId;
    // 仅 initialScrollIndex 用一次，不监听 pageNo 以免列表重建
    final initialPage = context.reader.pageNo;
    final mq = MediaQuery.sizeOf(context);

    if (!_loggedOpen) {
      _loggedOpen = true;
      ReaderPipeline.listBuild(pageCount: pageCount, mq: mq);
      ReaderPipeline.mark(
        ReaderStage.listBuild,
        detail: 'haka_style ScrollablePositionedList ratio=$widthRatio',
      );
    }

    return GestureWrapper(
      openOrCloseToolbar: context.reader.openOrCloseToolbar,
      jumpOffset: context.reader.pageTurnForVertical,
      child: ColoredBox(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final factor = widthRatio.clamp(0.05, 1.0);
            final layoutW = constraints.maxWidth * factor;
            final dpr = MediaQuery.devicePixelRatioOf(context);
            final cacheWidth = computeImageCacheWidth(
              layoutWidth: layoutW,
              devicePixelRatio: dpr,
            );
            context.reader.updatePreloadCacheWidth(cacheWidth);

            return Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                widthFactor: factor,
                child: ScrollablePositionedList.builder(
                  initialScrollIndex: initialPage.clamp(0, pageCount),
                  padding: EdgeInsets.zero,
                  physics: physics,
                  itemCount: pageCount + 1,
                  addAutomaticKeepAlives: false,
                  // ignore: deprecated_member_use
                  minCacheExtent: screenHeight * 2,
                  itemScrollController: context.reader.itemScrollController,
                  itemPositionsListener: _positionsListener,
                  scrollOffsetController: context.reader.scrollOffsetController,
                  itemBuilder: (context, index) {
                    if (index == pageCount) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          '本章完',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white54,
                          ),
                        ),
                      );
                    }

                    final item = images[index];
                    if (index < 5) {
                      ReaderPipeline.tileBuild(index, cacheKey: item.cacheKey);
                    }

                    return ReaderImage(
                      key: ValueKey(item.cacheKey),
                      url: item.url,
                      cacheKey: item.cacheKey,
                      headers: item.headers,
                      fallbackUrls: item.fallbackUrls,
                      bytesTransformer: item.bytesTransformer,
                      cacheWidth: cacheWidth,
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                      traceId: traceId,
                      imageIndex: index,
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
