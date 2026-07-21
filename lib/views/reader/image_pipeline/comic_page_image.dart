/// Page image widget: ImageProvider → ImageStream → RawImage + size cache.
///
/// This is the proven continuous-reader paint path (not Image.memory state
/// machines). List height is derived from decoded pixel size.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';

/// Single comic page display widget.
class ComicPageImage extends StatefulWidget {
  ComicPageImage({
    super.key,
    required ImageProvider image,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.medium,
    this.alignment = Alignment.center,
    this.gaplessPlayback = false,
    int? cacheWidth,
    int? cacheHeight,
  }) : image = ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, image);

  final ImageProvider image;
  final double? width;
  final double? height;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final AlignmentGeometry alignment;
  final bool gaplessPlayback;

  static void clearSizeCache() => _ComicPageImageState.clear();

  @override
  State<ComicPageImage> createState() => _ComicPageImageState();
}

class _ComicPageImageState extends State<ComicPageImage>
    with WidgetsBindingObserver {
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  ImageChunkEvent? _loadingProgress;
  bool _isListeningToStream = false;
  late bool _invertColors;
  late DisposableBuildContext<State<ComicPageImage>> _scrollAwareContext;
  Object? _lastException;
  ImageStreamCompleterHandle? _completerHandle;

  static final Map<int, Size> _cache = {};

  static void clear() => _cache.clear();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollAwareContext = DisposableBuildContext<State<ComicPageImage>>(this);
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
    // ignore: deprecated_member_use
    if (TickerMode.of(context)) {
      _listenToStream();
    } else {
      _stopListeningToStream(keepStreamAlive: true);
    }
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(ComicPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      _resolveImage();
    }
  }

  @override
  void didChangeAccessibilityFeatures() {
    super.didChangeAccessibilityFeatures();
    setState(_updateInvertColors);
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
    final provider = ScrollAwareImageProvider<Object>(
      context: _scrollAwareContext,
      imageProvider: widget.image,
    );
    final newStream = provider.resolve(
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
          setState(() => _lastException = error);
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
    });
  }

  void _handleImageChunk(ImageChunkEvent event) {
    setState(() {
      _loadingProgress = event;
      _lastException = null;
    });
  }

  void _replaceImage({required ImageInfo? info}) {
    final old = _imageInfo;
    SchedulerBinding.instance.addPostFrameCallback((_) => old?.dispose());
    _imageInfo = info;
  }

  void _updateSourceStream(ImageStream newStream) {
    if (_imageStream?.key == newStream.key) return;

    if (_isListeningToStream) {
      _imageStream!.removeListener(_getListener());
    }

    if (!widget.gaplessPlayback) {
      setState(() => _replaceImage(info: null));
    }

    setState(() {
      _loadingProgress = null;
    });

    _imageStream = newStream;
    if (_isListeningToStream) {
      _imageStream!.addListener(_getListener());
    }
  }

  void _listenToStream() {
    if (_isListeningToStream) return;
    _imageStream!.addListener(_getListener());
    _completerHandle?.dispose();
    _completerHandle = null;
    _isListeningToStream = true;
  }

  void _stopListeningToStream({bool keepStreamAlive = false}) {
    if (!_isListeningToStream) return;
    if (keepStreamAlive &&
        _completerHandle == null &&
        _imageStream?.completer != null) {
      _completerHandle = _imageStream!.completer!.keepAlive();
    }
    _imageStream!.removeListener(_getListener());
    _isListeningToStream = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_lastException != null) {
      final width = widget.width ?? MediaQuery.sizeOf(context).width;
      return SizedBox(
        width: width,
        height: widget.height ?? 300,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('图片加载失败', style: TextStyle(color: Colors.white70)),
              TextButton(
                onPressed: () {
                  setState(() => _lastException = null);
                  _resolveImage();
                },
                child: const Text('Retry', style: TextStyle(color: Colors.blue)),
              ),
            ],
          ),
        ),
      );
    }

    final width = widget.width ?? MediaQuery.sizeOf(context).width;
    double? height;
    final cacheSize = _cache[widget.image.hashCode];
    if (cacheSize != null) {
      height = (cacheSize.height * (width / cacheSize.width)).ceilToDouble();
    }

    if (_imageInfo != null) {
      _cache[widget.image.hashCode] = Size(
        _imageInfo!.image.width.toDouble(),
        _imageInfo!.image.height.toDouble(),
      );
      height = (_imageInfo!.image.height *
              (width / _imageInfo!.image.width))
          .ceilToDouble();

      final result = RawImage(
        image: _imageInfo?.image,
        debugImageLabel: _imageInfo?.debugLabel,
        width: width,
        height: height,
        scale: _imageInfo?.scale ?? 1.0,
        fit: widget.fit,
        alignment: widget.alignment,
        invertColors: _invertColors,
        filterQuality: widget.filterQuality,
      );

      return SizedBox(
        width: width,
        height: height,
        child: Center(child: result),
      );
    }

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
  }
}
