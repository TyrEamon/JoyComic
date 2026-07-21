/// 竖直连续模式。
///
/// 对齐已验证可用的连续竖读布局：
/// ScrollablePositionedList + ComicPageImage(width, height=w*1.2, fit: cover)
/// 图片：StreamImageProvider（下载+JM重组）→ ImageStream → RawImage。
library;

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../../foundation/reader_config.dart';
import '../../image_pipeline/comic_page_image.dart';
import '../../image_pipeline/page_image_provider.dart';
import '../../providers/reader_provider.dart' hide ReaderImage;
import '../../providers/list_state_provider.dart';
import '../../utils/image_preload_controller.dart';
import '../../utils/reader_utils.dart';
import 'gesture.dart';
import 'page_index.dart';

/// 竖直连续模式。
class VerticalList extends StatefulWidget {
  const VerticalList({super.key});

  @override
  State<VerticalList> createState() => _VerticalListState();
}

class _VerticalListState extends State<VerticalList> {
  final itemPositionsListener = ItemPositionsListener.create();
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
      traceId: reader.traceId,
    );
    reader.initPreloadController(_preloadController!);
    itemPositionsListener.itemPositions.addListener(_onItemPositionsChanged);
  }

  @override
  void dispose() {
    itemPositionsListener.itemPositions.removeListener(_onItemPositionsChanged);
    _preloadController?.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    final physics = context.stateSelector((p) => p.physics);
    final pageCount = context.selector((p) => p.pageCount);
    final images = context.selector((p) => p.images);
    final initialPage = context.reader.pageNo;
    final traceId = context.reader.traceId;

    return GestureWrapper(
      openOrCloseToolbar: context.reader.openOrCloseToolbar,
      jumpOffset: context.reader.pageTurnForVertical,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Proven continuous vertical: full screen width for pages.
          final width = MediaQuery.sizeOf(context).width;
          final height = MediaQuery.sizeOf(context).height;
          var imageWidth = width;
          if (height / width < 1.2) {
            final capped = height / 1.2;
            if (capped < imageWidth) imageWidth = capped;
          }
          if (imageWidth <= 0 || !imageWidth.isFinite) {
            imageWidth = width > 0 ? width : 390;
          }

          return ColoredBox(
            color: Colors.black,
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
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '本章完',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                      ),
                    ),
                  );
                }

                final item = images[index];
                final provider = createPageImageProvider(
                  url: item.url,
                  cacheKey: item.cacheKey,
                  fallbackUrls: item.fallbackUrls,
                  headers: item.headers,
                  bytesTransformer: item.bytesTransformer,
                  traceId: traceId,
                  imageIndex: index,
                );

                // Continuous vertical page tile (width + placeholder height).
                return ComicPageImage(
                  key: ValueKey(item.cacheKey),
                  image: provider,
                  width: imageWidth,
                  height: imageWidth * 1.2,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
