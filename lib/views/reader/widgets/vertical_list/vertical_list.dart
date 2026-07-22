/// 竖直连续模式。
///
/// 列表项必须有**非零固定槽位**（真机 S17 layout=0x0 黑屏根因）。
/// 出图路径：createPageImageProvider → Image，无 InteractiveViewer。
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
  final Set<int> _tileLogged = <int>{};

  /// 每页布局高度（逻辑像素）。
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

  /// 默认占位高：约 4:3 竖图，且永不 < 200。
  double _defaultHeight(double width) {
    final h = width / (3 / 4);
    if (!h.isFinite || h < 200) return 520;
    return h;
  }

  double _heightOf(int index, double width) {
    final h = _heights[index] ?? _defaultHeight(width);
    if (!h.isFinite || h < 1) return _defaultHeight(width);
    return h;
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

  void _onImageSize(int index, int layoutW, int layoutH) {
    if (layoutW <= 1 || layoutH <= 1) return;
    final h = layoutH.toDouble();
    final prev = _heights[index];
    if (prev != null && (prev - h).abs() < 1.0) return;
    if (!mounted) return;
    setState(() => _heights[index] = h);
  }

  @override
  Widget build(BuildContext context) {
    final physics = context.stateSelector((p) => p.physics);
    final pageCount = context.selector((p) => p.pageCount);
    final images = context.selector((p) => p.images);
    final traceId = context.reader.traceId;

    // 列表交叉轴宽度：优先约束，再 MediaQuery，再 390。
    return LayoutBuilder(
      builder: (context, constraints) {
        double imageWidth = 0;
        if (constraints.hasBoundedWidth &&
            constraints.maxWidth.isFinite &&
            constraints.maxWidth > 1) {
          imageWidth = constraints.maxWidth;
        } else {
          final mq = MediaQuery.sizeOf(context).width;
          imageWidth = mq > 1 ? mq : 390;
        }

        if (!_loggedOpen) {
          _loggedOpen = true;
          ReaderPipeline.listBuild(
            pageCount: pageCount,
            mq: Size(imageWidth, MediaQuery.sizeOf(context).height),
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
                if (_tileLogged.add(index)) {
                  ReaderPipeline.tileBuild(index, cacheKey: item.cacheKey);
                }
                final layoutH = _heightOf(index, imageWidth);

                // 与诊断版相同：外层强制宽高，内层 Image。
                return SizedBox(
                  width: imageWidth,
                  height: layoutH,
                  child: ReaderImage(
                    key: ValueKey(item.cacheKey),
                    url: item.url,
                    cacheKey: item.cacheKey,
                    headers: item.headers,
                    fallbackUrls: item.fallbackUrls,
                    bytesTransformer: item.bytesTransformer,
                    width: imageWidth,
                    height: layoutH,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    traceId: traceId,
                    imageIndex: index,
                    onImageSizeChanged: (pw, ph) {
                      _onImageSize(index, pw, ph);
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
