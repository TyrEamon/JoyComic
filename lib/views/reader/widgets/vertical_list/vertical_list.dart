/// 竖直连续模式：图贴图、真实高度缓存、滚动藏 UI、双指缩放。
library;

import 'package:flutter/material.dart';

import '../../../../foundation/reader_config.dart';
import '../../providers/list_state_provider.dart';
import '../../providers/reader_provider.dart' hide ReaderImage;
import '../../utils/image_preload_controller.dart';
import '../../utils/reader_pipeline.dart';
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
  int _lastPage = 0;
  bool _loggedOpen = false;

  /// 每页布局高度（逻辑像素），用于精确页码。
  final Map<int, double> _heights = <int, double>{};

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
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _preloadController?.dispose();
    super.dispose();
  }

  double _defaultHeight(double width) => width / (3 / 4); // 4:3 竖图占位

  double _heightOf(int index, double width) {
    return _heights[index] ?? _defaultHeight(width);
  }

  int _pageAtOffset(double offset, double width, int count) {
    if (count <= 0) return 0;
    var y = 0.0;
    for (var i = 0; i < count; i++) {
      final h = _heightOf(i, width);
      if (offset < y + h) return i;
      y += h;
    }
    return count - 1;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final count = context.reader.images.length;
    if (count == 0) return;
    final w = MediaQuery.sizeOf(context).width;
    final index = _pageAtOffset(_scrollController.offset, w, count);
    if (index != _lastPage) {
      _lastPage = index;
      _preloadController?.onAnchorChanged([index]);
      context.reader.onPageNoChanged(index);
    }
  }

  void _onImageSize(int index, int pxW, int pxH, double layoutW) {
    if (pxW <= 0 || pxH <= 0 || layoutW <= 0) return;
    final h = layoutW * pxH / pxW;
    if (_heights[index] != null && (_heights[index]! - h).abs() < 0.5) {
      return;
    }
    setState(() => _heights[index] = h);
  }

  @override
  Widget build(BuildContext context) {
    final physics = context.stateSelector((p) => p.physics);
    final pageCount = context.selector((p) => p.pageCount);
    final images = context.selector((p) => p.images);
    final traceId = context.reader.traceId;
    final screenW = MediaQuery.sizeOf(context).width;
    final imageWidth = screenW > 1 ? screenW : 390.0;

    if (!_loggedOpen) {
      _loggedOpen = true;
      ReaderPipeline.listBuild(
        pageCount: pageCount,
        mq: MediaQuery.sizeOf(context),
      );
    }

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
      child: ColoredBox(
        color: Colors.black,
        child: ListView.builder(
          controller: _scrollController,
          physics: physics,
          // ignore: deprecated_member_use
          cacheExtent: MediaQuery.sizeOf(context).height * 3,
          padding: EdgeInsets.zero,
          // 相邻图零间距
          itemCount: pageCount + 1,
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
            final layoutH = _heightOf(index, imageWidth);

            return ReaderImage(
              key: ValueKey(item.cacheKey),
              url: item.url,
              cacheKey: item.cacheKey,
              headers: item.headers,
              fallbackUrls: item.fallbackUrls,
              bytesTransformer: item.bytesTransformer,
              width: imageWidth,
              height: layoutH,
              fit: BoxFit.fitWidth,
              filterQuality: FilterQuality.medium,
              traceId: traceId,
              imageIndex: index,
              onImageSizeChanged: (pw, ph) {
                _onImageSize(index, pw, ph, imageWidth);
              },
            );
          },
        ),
      ),
    );
  }
}
