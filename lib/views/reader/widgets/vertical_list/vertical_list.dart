/// 竖直连续沉浸阅读。
///
/// 出图关键（真机已验证，勿删）：
/// 非零高度槽 + [Column] + [Expanded] + 系统 [Image]。
///
/// 沉浸：黑底、全宽 [BoxFit.fitWidth]、按像素宽高比算槽高（减少黑边）。
library;

import 'package:flutter/material.dart';

import '../../../../foundation/reader_config.dart';
import '../../image_pipeline/page_image_provider.dart';
import '../../providers/list_state_provider.dart';
import '../../providers/reader_provider.dart' hide ReaderImage;
import '../../utils/image_preload_controller.dart';
import '../../utils/reader_pipeline.dart';
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

  /// 每页槽高（逻辑像素）。先用默认比，解码后按真实宽高比更新。
  final Map<int, double> _slotHeights = <int, double>{};

  /// 默认高/宽（接近常见漫画 960×1355 ≈ 1.41）。
  static const double _kDefaultAspect = 1.41;

  /// 最小槽高：过小在部分机型上仍可能异常。
  static const double _kMinSlot = 200;

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

  double _defaultSlot(double width) {
    final h = width * _kDefaultAspect;
    if (!h.isFinite || h < _kMinSlot) return 520;
    return h;
  }

  double _slotOf(int index, double width) {
    final h = _slotHeights[index] ?? _defaultSlot(width);
    if (!h.isFinite || h < _kMinSlot) return _defaultSlot(width);
    return h;
  }

  int _pageAtOffset(double offset, double width, int count) {
    if (count <= 0) return 0;
    var y = 0.0;
    for (var i = 0; i < count; i++) {
      final h = _slotOf(i, width);
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

  void _onPixelSize(int index, int pxW, int pxH, double layoutW) {
    if (pxW <= 0 || pxH <= 0 || layoutW <= 1) return;
    final h = layoutW * pxH / pxW;
    if (!h.isFinite || h < _kMinSlot) return;
    final prev = _slotHeights[index];
    if (prev != null && (prev - h).abs() < 1.0) return;
    if (!mounted) return;
    setState(() => _slotHeights[index] = h);
  }

  @override
  Widget build(BuildContext context) {
    final physics = context.stateSelector((p) => p.physics);
    final pageCount = context.selector((p) => p.pageCount);
    final images = context.selector((p) => p.images);
    final traceId = context.reader.traceId;
    final mq = MediaQuery.sizeOf(context);
    final width = mq.width > 1 ? mq.width : 390.0;

    if (!_loggedOpen) {
      _loggedOpen = true;
      ReaderPipeline.listBuild(pageCount: pageCount, mq: mq);
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
          cacheExtent: mq.height * 3,
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

            final provider = createPageImageProvider(
              url: item.url,
              cacheKey: item.cacheKey,
              fallbackUrls: item.fallbackUrls,
              headers: item.headers,
              bytesTransformer: item.bytesTransformer,
              traceId: traceId,
              imageIndex: index,
            );

            final slotH = _slotOf(index, width);

            // 能出图结构：固定非零高 + Column + Expanded(Image)。
            // fitWidth：横向铺满；槽高按宽高比时上下黑边最小。
            return SizedBox(
              width: double.infinity,
              height: slotH,
              child: ColoredBox(
                color: Colors.black,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _PageImage(
                        provider: provider,
                        pageIndex: index,
                        layoutW: width,
                        layoutH: slotH,
                        onPixelSize: (pw, ph) {
                          _onPixelSize(index, pw, ph, width);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 单页 Image + 一次性尺寸探测（共享 ImageCache，不另开下载）。
class _PageImage extends StatefulWidget {
  const _PageImage({
    required this.provider,
    required this.pageIndex,
    required this.layoutW,
    required this.layoutH,
    required this.onPixelSize,
  });

  final ImageProvider provider;
  final int pageIndex;
  final double layoutW;
  final double layoutH;
  final void Function(int pxW, int pxH) onPixelSize;

  @override
  State<_PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<_PageImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool _sizeSent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachSizeListener();
  }

  @override
  void didUpdateWidget(covariant _PageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) {
      _detach();
      _sizeSent = false;
      _attachSizeListener();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _attachSizeListener() {
    if (_sizeSent) return;
    final stream = widget.provider.resolve(
      createLocalImageConfiguration(context),
    );
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (_sizeSent) return;
      final w = info.image.width;
      final h = info.image.height;
      if (w > 0 && h > 0) {
        _sizeSent = true;
        widget.onPixelSize(w, h);
      }
    }, onError: (_, __) {});
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    return Image(
      image: widget.provider,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      alignment: Alignment.topCenter,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            ReaderPipeline.widgetFrame(
              widget.pageIndex,
              layoutW: widget.layoutW,
              layoutH: widget.layoutH,
            );
          });
          return child;
        }
        return const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              color: Colors.white54,
              strokeWidth: 3,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) {
        ReaderPipeline.widgetError(widget.pageIndex, error: error);
        return Center(
          child: Text(
            '加载失败 第${widget.pageIndex + 1}页',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        );
      },
    );
  }
}
