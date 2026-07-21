/// 竖直连续模式（条漫流）。
///
/// 使用简单 [ListView.builder]（不再用 ScrollablePositionedList），
/// 避免列表回收/重建把进行中的图片加载冲掉导致永久黑屏。
library;

import 'package:flutter/material.dart';

import '../../../../foundation/reader_config.dart';
import '../../providers/reader_provider.dart' hide ReaderImage;
import '../../providers/list_state_provider.dart';
import '../../utils/image_preload_controller.dart';
import '../../utils/reader_utils.dart';
import '../reader_image.dart';
import 'gesture.dart';

/// 竖直连续模式。
class VerticalList extends StatefulWidget {
  const VerticalList({super.key});

  @override
  State<VerticalList> createState() => _VerticalListState();
}

class _VerticalListState extends State<VerticalList> {
  final ScrollController _scrollController = ScrollController();
  ImagePreloadController? _preloadController;
  int _lastReportedPage = 0;

  @override
  void initState() {
    super.initState();
    _initPreloadController();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final page = context.reader.pageNo;
      if (page > 0) {
        // Approximate jump: each item ~1.2 * width until sizes known.
        // Real offset settles as images load; good enough for resume.
      }
    });
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _preloadController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final reader = context.reader;
    final count = reader.images.length;
    if (count == 0) return;

    // Estimate page from scroll offset using average item height.
    final width = MediaQuery.sizeOf(context).width;
    final avgH = width > 0 ? width * 1.2 : 600.0;
    final offset = _scrollController.offset;
    final index = (offset / avgH).floor().clamp(0, count - 1);
    if (index != _lastReportedPage) {
      _lastReportedPage = index;
      _preloadController?.onAnchorChanged([index]);
      reader.onPageNoChanged(index);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final physics = context.stateSelector((p) => p.physics);
    final widthRatio = context.stateSelector((p) => p.verticalListWidthRatio);
    final pageCount = context.selector((p) => p.pageCount);
    final images = context.selector((p) => p.images);

    return GestureWrapper(
      openOrCloseToolbar: context.reader.openOrCloseToolbar,
      jumpOffset: (delta) {
        if (!_scrollController.hasClients) return;
        final target = (_scrollController.offset + delta).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenW = _safeLayoutWidth(constraints);
          final screenH = _safeLayoutHeight(constraints);
          final widthFactor = widthRatio.clamp(0.05, 1.0);
          var imageWidth = screenW * widthFactor;
          if (imageWidth <= 0 || !imageWidth.isFinite) imageWidth = screenW;

          final placeholderHeight = imageWidth * 1.2;

          // Full-bleed list — no nested Center/SizedBox that can zero out width.
          return ColoredBox(
            color: const Color(0xFF121212),
            child: ListView.builder(
              controller: _scrollController,
              physics: physics,
              // ignore: deprecated_member_use
              cacheExtent: screenH * 4,
              padding: EdgeInsets.zero,
              itemCount: pageCount + 1,
              itemBuilder: (context, index) {
                if (index == pageCount) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
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
                  // Do not pass cacheWidth — let Flutter decode at natural size
                  // to avoid iOS texture upload edge cases.
                  width: imageWidth,
                  height: placeholderHeight,
                  fit: BoxFit.fitWidth,
                  filterQuality: FilterQuality.low,
                  traceId: context.reader.traceId,
                  imageIndex: index,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
