/// 阅读器单图：ImageProvider → ImageStream → RawImage + 尺寸缓存。
///
/// 下载 / JM 重组仍用 [ReaderNetworkImageProvider]；显示侧用标准
/// ImageStream 路径上屏，按解码像素宽高计算列表项高度。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

import '../../../foundation/log.dart';
import '../utils/reader_image_provider.dart';

/// 漫画单图加载显示组件。
class ReaderImage extends StatefulWidget {
  ReaderImage({
    super.key,
    required this.url,
    this.cacheKey,
    this.headers,
    this.fallbackUrls = const <String>[],
    this.bytesTransformer,
    this.fit = BoxFit.fitWidth,
    this.filterQuality = FilterQuality.medium,
    this.cacheWidth,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.onImageSizeChanged,
    this.traceId,
    this.imageIndex,
    this.gaplessPlayback = false,
  }) : image = readerImageProvider(
         url: url,
         cacheKey: cacheKey ?? url,
         fallbackUrls: fallbackUrls,
         headers: headers,
         bytesTransformer: bytesTransformer,
         cacheWidth: cacheWidth,
         traceId: traceId,
         imageIndex: imageIndex,
       );

  /// 直接喂 ImageProvider（水平 PhotoView / 测试用）。
  const ReaderImage.fromProvider({
    super.key,
    required this.image,
    this.url = '',
    this.cacheKey,
    this.headers,
    this.fallbackUrls = const <String>[],
    this.bytesTransformer,
    this.fit = BoxFit.fitWidth,
    this.filterQuality = FilterQuality.medium,
    this.cacheWidth,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.onImageSizeChanged,
    this.traceId,
    this.imageIndex,
    this.gaplessPlayback = false,
  });

  final ImageProvider image;
  final String url;
  final String? cacheKey;
  final Map<String, String>? headers;
  final List<String> fallbackUrls;
  final ReaderImageBytesTransformer? bytesTransformer;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final int? cacheWidth;
  final AlignmentGeometry alignment;
  final double? width;
  final double? height;
  final void Function(int width, int height)? onImageSizeChanged;
  final String? traceId;
  final int? imageIndex;
  final bool gaplessPlayback;

  static void clearSizeCache() => _ReaderImageState.clear();

  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> with WidgetsBindingObserver {
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  ImageChunkEvent? _loadingProgress;
  bool _isListeningToStream = false;
  late bool _invertColors;
  int? _frameNumber;
  bool _wasSynchronouslyLoaded = false;
  late DisposableBuildContext<State<ReaderImage>> _scrollAwareContext;
  Object? _lastException;
  ImageStreamCompleterHandle? _completerHandle;
  bool _loggedFirstFrame = false;

  /// Cache decoded pixel size by image hash for list layout.
  static final Map<int, Size> _cache = {};

  static void clear() => _cache.clear();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollAwareContext = DisposableBuildContext<State<ReaderImage>>(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopListeningToStream();
    _completerHandle?.dispose();
    _scrollAwareContext.dispose();
    _replaceImage(info: null);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    _updateInvertColors();
    _resolveImage();

    // ignore: deprecated_member_use — pause stream when ticker mode is off
    if (TickerMode.of(context)) {
      _listenToStream();
    } else {
      _stopListeningToStream(keepStreamAlive: true);
    }

    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      _loggedFirstFrame = false;
      _resolveImage();
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    super.didChangeAccessibilityFeatures();
    setState(() {
      _updateInvertColors();
    });
  }

  @override
  void reassemble() {
    _resolveImage();
    super.reassemble();
  }

  void _updateInvertColors() {
    _invertColors =
        MediaQuery.maybeInvertColorsOf(context) ??
        SemanticsBinding.instance.accessibilityFeatures.invertColors;
  }

  void _resolveImage() {
    // ScrollAwareImageProvider defers loads for off-screen list items.
    final ScrollAwareImageProvider provider = ScrollAwareImageProvider<Object>(
      context: _scrollAwareContext,
      imageProvider: widget.image,
    );
    final ImageStream newStream = provider.resolve(
      createLocalImageConfiguration(
        context,
        size: widget.width != null && widget.height != null
            ? Size(widget.width!, widget.height!)
            : null,
      ),
    );
    _updateSourceStream(newStream);
  }

  ImageStreamListener? _imageStreamListener;
  ImageStreamListener _getListener({bool recreateListener = false}) {
    if (_imageStreamListener == null || recreateListener) {
      _lastException = null;
      _imageStreamListener = ImageStreamListener(
        _handleImageFrame,
        onChunk: _handleImageChunk,
        onError: (Object error, StackTrace? stackTrace) {
          setState(() {
            _lastException = error;
          });
          if (widget.traceId != null) {
            Log.w(
              'Reader image stream error',
              error:
                  'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
                  'via=stream err=$error',
            );
          }
        },
      );
    }
    return _imageStreamListener!;
  }

  void _handleImageFrame(ImageInfo imageInfo, bool synchronousCall) {
    setState(() {
      _replaceImage(info: imageInfo);
      _loadingProgress = null;
      _lastException = null;
      _frameNumber = _frameNumber == null ? 0 : _frameNumber! + 1;
      _wasSynchronouslyLoaded = _wasSynchronouslyLoaded | synchronousCall;
    });

    final w = imageInfo.image.width;
    final h = imageInfo.image.height;
    widget.onImageSizeChanged?.call(w, h);

    if (!_loggedFirstFrame && widget.traceId != null) {
      _loggedFirstFrame = true;
      final layoutW = widget.width ?? MediaQuery.sizeOf(context).width;
      final layoutH = h * (layoutW / w);
      Log.i(
        'Reader first frame',
        'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
        'size=${w}x$h '
        'layout=${layoutW.toStringAsFixed(1)}x${layoutH.toStringAsFixed(1)} '
        'via=stream '
        'cache=${ReaderDiagnostics.cacheKeySummary(widget.cacheKey ?? widget.url)}',
      );
    }
  }

  void _handleImageChunk(ImageChunkEvent event) {
    setState(() {
      _loadingProgress = event;
      _lastException = null;
    });
  }

  void _replaceImage({required ImageInfo? info}) {
    final ImageInfo? oldImageInfo = _imageInfo;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => oldImageInfo?.dispose(),
    );
    _imageInfo = info;
  }

  void _updateSourceStream(ImageStream newStream) {
    if (_imageStream?.key == newStream.key) {
      return;
    }

    if (_isListeningToStream) {
      _imageStream!.removeListener(_getListener());
    }

    if (!widget.gaplessPlayback) {
      setState(() {
        _replaceImage(info: null);
      });
    }

    setState(() {
      _loadingProgress = null;
      _frameNumber = null;
      _wasSynchronouslyLoaded = false;
    });

    _imageStream = newStream;
    if (_isListeningToStream) {
      _imageStream!.addListener(_getListener());
    }
  }

  void _listenToStream() {
    if (_isListeningToStream) {
      return;
    }

    _imageStream!.addListener(_getListener());
    _completerHandle?.dispose();
    _completerHandle = null;

    _isListeningToStream = true;
  }

  void _stopListeningToStream({bool keepStreamAlive = false}) {
    if (!_isListeningToStream) {
      return;
    }

    if (keepStreamAlive &&
        _completerHandle == null &&
        _imageStream?.completer != null) {
      _completerHandle = _imageStream!.completer!.keepAlive();
    }

    _imageStream!.removeListener(_getListener());
    _isListeningToStream = false;
  }

  double _resolveWidth(BoxConstraints constraints) {
    if (widget.width != null && widget.width! > 0) return widget.width!;
    if (constraints.hasBoundedWidth &&
        constraints.maxWidth.isFinite &&
        constraints.maxWidth > 0) {
      return constraints.maxWidth;
    }
    final mq = MediaQuery.sizeOf(context).width;
    return mq > 0 ? mq : 390;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _resolveWidth(constraints);

        if (_lastException != null) {
          return SizedBox(
            width: width,
            height: widget.height ?? 300,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFFECECEC),
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '图片加载失败',
                    style: TextStyle(color: Color(0xFFECECEC)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _lastException = null;
                      });
                      _resolveImage();
                    },
                    child: const Text(
                      'Retry',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Width from prop/constraints; height from size cache only.
        double? height;

        final Size? cacheSize = _cache[widget.image.hashCode];
        if (cacheSize != null) {
          height = cacheSize.height * (width / cacheSize.width);
          height = height.ceilToDouble();
        }

        if (_imageInfo != null) {
          _cache[widget.image.hashCode] = Size(
            _imageInfo!.image.width.toDouble(),
            _imageInfo!.image.height.toDouble(),
          );
          height =
              _imageInfo!.image.height * (width / _imageInfo!.image.width);
          height = height.ceilToDouble();

          Widget result = RawImage(
            image: _imageInfo?.image,
            debugImageLabel: _imageInfo?.debugLabel,
            width: width,
            height: height,
            scale: _imageInfo?.scale ?? 1.0,
            fit: widget.fit,
            alignment: widget.alignment,
            isAntiAlias: false,
            filterQuality: widget.filterQuality,
            invertColors: _invertColors,
          );

          result = SizedBox(
            width: width,
            height: height,
            child: Center(child: result),
          );
          return result;
        }

        // Loading placeholder.
        return SizedBox(
          width: width,
          height: height ?? 300,
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                backgroundColor: Colors.white24,
                strokeWidth: 3,
                value:
                    (_loadingProgress != null &&
                        _loadingProgress!.expectedTotalBytes != null &&
                        _loadingProgress!.expectedTotalBytes! != 0)
                    ? _loadingProgress!.cumulativeBytesLoaded /
                          _loadingProgress!.expectedTotalBytes!
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder description) {
    super.debugFillProperties(description);
    description.add(DiagnosticsProperty<ImageStream>('stream', _imageStream));
    description.add(DiagnosticsProperty<ImageInfo>('pixels', _imageInfo));
    description.add(
      DiagnosticsProperty<ImageChunkEvent>('loadingProgress', _loadingProgress),
    );
    description.add(DiagnosticsProperty<int>('frameNumber', _frameNumber));
    description.add(
      DiagnosticsProperty<bool>(
        'wasSynchronouslyLoaded',
        _wasSynchronouslyLoaded,
      ),
    );
  }
}
