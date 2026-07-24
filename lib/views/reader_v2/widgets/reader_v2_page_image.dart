import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox, RenderImage;

import '../core/reader_v2_scheduler.dart';
import '../core/reader_v2_session.dart';
import '../data/reader_v2_page.dart';
import '../image/reader_v2_image_provider.dart';

final class ReaderV2PageImage extends StatefulWidget {
  const ReaderV2PageImage({
    super.key,
    required this.page,
    required this.session,
    required this.scheduler,
    required this.priority,
    required this.bytesLoader,
    this.onImageSize,
    this.height,
    this.placeholderHeight = 300,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.topCenter,
  });

  final ReaderV2Page page;
  final ReaderV2Session session;
  final ReaderV2Scheduler scheduler;
  final ReaderV2Priority priority;
  final ReaderV2BytesLoader bytesLoader;
  final ValueChanged<Size>? onImageSize;
  final double? height;
  final double placeholderHeight;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  @override
  State<ReaderV2PageImage> createState() => _ReaderV2PageImageState();
}

final class _ReaderV2PageImageState extends State<ReaderV2PageImage> {
  GlobalKey _imageKey = GlobalKey();
  late ReaderV2ImageProvider _provider;
  BoxConstraints? _lastConstraints;
  bool _frameworkFrameLogged = false;
  bool _hasRenderedFrame = false;
  double? _naturalAspectRatio;
  int? _loggedErrorGeneration;
  int _retryGeneration = 0;

  @override
  void initState() {
    super.initState();
    _provider = _buildImageProvider();
  }

  @override
  void didUpdateWidget(ReaderV2PageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.cacheKey != widget.page.cacheKey ||
        oldWidget.session.traceId != widget.session.traceId ||
        !identical(oldWidget.scheduler, widget.scheduler)) {
      _frameworkFrameLogged = false;
      _hasRenderedFrame = false;
      _naturalAspectRatio = null;
      _loggedErrorGeneration = null;
      _retryGeneration = 0;
      _imageKey = GlobalKey();
      _provider = _buildImageProvider();
    }
  }

  ReaderV2ImageProvider _buildImageProvider() {
    return ReaderV2ImageProvider(
      page: widget.page,
      session: widget.session,
      scheduler: widget.scheduler,
      priority: widget.priority,
      bytesLoader: widget.bytesLoader,
    );
  }

  Future<void> _retry() async {
    await _provider.evict();
    if (!mounted || widget.session.isCancelled) return;
    setState(() {
      _retryGeneration += 1;
      _frameworkFrameLogged = false;
      _hasRenderedFrame = false;
      _loggedErrorGeneration = null;
      _imageKey = GlobalKey();
      _provider = _buildImageProvider();
    });
  }

  void _recordFrameAndLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.session.isCancelled) return;
      final imageRenderObject = _imageKey.currentContext?.findRenderObject();
      final renderImage = imageRenderObject is RenderImage
          ? imageRenderObject
          : null;
      final decoded = renderImage?.image;
      double? nextAspectRatio;
      if (decoded != null) {
        final aspectRatio = decoded.width / decoded.height;
        widget.onImageSize?.call(
          Size(decoded.width.toDouble(), decoded.height.toDouble()),
        );
        widget.session.record(
          'frame',
          page: widget.page.index,
          detail: '${decoded.width}x${decoded.height}',
        );
        if (widget.height == null &&
            aspectRatio.isFinite &&
            aspectRatio > 0 &&
            _naturalAspectRatio != aspectRatio) {
          nextAspectRatio = aspectRatio;
        }
      }
      final resized = nextAspectRatio != null;
      if (!_hasRenderedFrame || resized) {
        setState(() {
          _hasRenderedFrame = true;
          if (nextAspectRatio != null) {
            _naturalAspectRatio = nextAspectRatio;
          }
        });
      }
      if (resized) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _recordLayout());
      } else {
        _recordLayout();
      }
    });
  }

  void _recordLayout() {
    if (!mounted || widget.session.isCancelled) return;
    final widgetRenderObject = context.findRenderObject();
    final imageRenderObject = _imageKey.currentContext?.findRenderObject();
    final widgetBox = widgetRenderObject is RenderBox
        ? widgetRenderObject
        : null;
    final imageBox = imageRenderObject is RenderBox ? imageRenderObject : null;
    final constraints = _lastConstraints;
    final global = imageBox?.localToGlobal(Offset.zero);
    widget.session.record(
      'layout',
      page: widget.page.index,
      detail: [
        'constraints=${_formatConstraints(constraints)}',
        'widget=${_formatSize(widgetBox)}',
        'image=${_formatSize(imageBox)}',
        'global=${global?.dx},${global?.dy}',
        'attached=${imageBox?.attached ?? false}',
        'hasSize=${imageBox?.hasSize ?? false}',
        'render=${imageRenderObject.runtimeType}',
      ].join(' '),
    );
  }

  static String _formatConstraints(BoxConstraints? constraints) {
    if (constraints == null) return 'missing';
    return '${constraints.minWidth}..${constraints.maxWidth}'
        'x${constraints.minHeight}..${constraints.maxHeight}';
  }

  static String _formatSize(RenderBox? box) {
    if (box == null) return 'missing';
    if (!box.hasSize) return 'unlaid-out';
    return '${box.size.width}x${box.size.height}';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastConstraints = constraints;
        final constrainedWidth = constraints.maxWidth;
        final mediaWidth = MediaQuery.sizeOf(context).width;
        final useFallbackWidth =
            !constrainedWidth.isFinite || constrainedWidth <= 1;
        final width = useFallbackWidth
            ? (mediaWidth.isFinite && mediaWidth > 1 ? mediaWidth : 390.0)
            : constrainedWidth;
        final naturalAspectRatio = _naturalAspectRatio;
        final height =
            widget.height ??
            (naturalAspectRatio == null
                ? widget.placeholderHeight
                : width / naturalAspectRatio);
        final image = SizedBox(
          width: width,
          height: height,
          child: ColoredBox(
            color: Colors.black,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Image(
                    key: _imageKey,
                    image: _provider,
                    width: width,
                    height: height,
                    fit: widget.height == null ? BoxFit.fitWidth : widget.fit,
                    alignment: widget.alignment,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                    excludeFromSemantics: true,
                    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                      if (frame == null) {
                        return const Center(
                          child: SizedBox.square(
                            dimension: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white54,
                            ),
                          ),
                        );
                      }
                      if (!_frameworkFrameLogged) {
                        _frameworkFrameLogged = true;
                        widget.session.record(
                          'paint-widget',
                          page: widget.page.index,
                          detail:
                              'Image frame=$frame sync=$wasSynchronouslyLoaded '
                              'stream=single',
                        );
                        _recordFrameAndLayout();
                      }
                      return child;
                    },
                    errorBuilder: _hasRenderedFrame
                        ? null
                        : (context, error, stackTrace) {
                            if (widget.session.isCancelled) {
                              return const SizedBox.shrink();
                            }
                            if (_loggedErrorGeneration != _retryGeneration) {
                              _loggedErrorGeneration = _retryGeneration;
                              widget.session.record(
                                'image-error',
                                page: widget.page.index,
                                detail: '$error',
                              );
                            }
                            return Center(
                              child: TextButton(
                                key: ValueKey(
                                  'reader-v2-retry-$_retryGeneration',
                                ),
                                onPressed: _retry,
                                child: const Text('重试'),
                              ),
                            );
                          },
                  ),
                ),
              ],
            ),
          ),
        );
        if (!useFallbackWidth) return image;
        return SizedBox(
          width: constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
          height: height,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: image,
          ),
        );
      },
    );
  }
}
