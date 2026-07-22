/// 阅读器单图：标准 [Image] + 宽高比缓存（图贴图、加载不跳变）。
library;

import 'package:flutter/material.dart';

import '../image_pipeline/page_image_provider.dart';
import '../utils/reader_image_provider.dart' show ReaderImageBytesTransformer;
import '../utils/reader_pipeline.dart';

/// 像素尺寸缓存（跨列表回收复用，避免高度跳变）。
class ReaderImageSizeCache {
  ReaderImageSizeCache._();

  static final Map<String, Size> _sizes = <String, Size>{};

  static Size? get(String key) => _sizes[key];

  static void put(String key, int width, int height) {
    if (key.isEmpty || width <= 0 || height <= 0) return;
    _sizes[key] = Size(width.toDouble(), height.toDouble());
  }

  static void clear() => _sizes.clear();
}

/// 漫画单图（列表项）。
class ReaderImage extends StatefulWidget {
  const ReaderImage({
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
    this.maxAttempts = 3,
  });

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
  final int maxAttempts;

  static void clearSizeCache() => ReaderImageSizeCache.clear();

  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  static const double _fallbackAspect = 3 / 4; // w/h

  ImageStream? _stream;
  ImageStreamListener? _listener;
  bool _sizeReported = false;

  String get _key => widget.cacheKey ?? widget.url;

  double get _aspect {
    final s = ReaderImageSizeCache.get(_key);
    if (s != null && s.width > 0 && s.height > 0) {
      return s.width / s.height;
    }
    return _fallbackAspect;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenForSize();
  }

  @override
  void didUpdateWidget(covariant ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.cacheKey != widget.cacheKey) {
      _sizeReported = false;
      _stopListen();
      _listenForSize();
    }
  }

  @override
  void dispose() {
    _stopListen();
    super.dispose();
  }

  void _stopListen() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _listenForSize() {
    if (_sizeReported && ReaderImageSizeCache.get(_key) != null) return;
    final provider = createPageImageProvider(
      url: widget.url,
      cacheKey: widget.cacheKey ?? widget.url,
      fallbackUrls: widget.fallbackUrls,
      headers: widget.headers,
      bytesTransformer: widget.bytesTransformer,
      traceId: widget.traceId,
      imageIndex: widget.imageIndex,
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, sync) {
        final w = info.image.width;
        final h = info.image.height;
        if (w > 0 && h > 0) {
          ReaderImageSizeCache.put(_key, w, h);
          if (!_sizeReported) {
            _sizeReported = true;
            widget.onImageSizeChanged?.call(w, h);
            if (mounted) setState(() {});
          }
        }
      },
      onError: (_, __) {},
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final w = (widget.width != null &&
            widget.width!.isFinite &&
            widget.width! > 1)
        ? widget.width!
        : (screenW > 1 ? screenW : 390.0);
    final aspect = _aspect;
    final h = w / aspect;
    final idx = widget.imageIndex ?? -1;

    final provider = createPageImageProvider(
      url: widget.url,
      cacheKey: widget.cacheKey ?? widget.url,
      fallbackUrls: widget.fallbackUrls,
      headers: widget.headers,
      bytesTransformer: widget.bytesTransformer,
      traceId: widget.traceId,
      imageIndex: widget.imageIndex,
    );

    // 固定宽高比槽位：加载前后高度一致 → 无跳变、图贴图。
    return SizedBox(
      width: w,
      height: h,
      child: Image(
        image: provider,
        width: w,
        height: h,
        fit: BoxFit.fitWidth,
        alignment: widget.alignment is Alignment
            ? widget.alignment as Alignment
            : Alignment.topCenter,
        filterQuality: widget.filterQuality,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ReaderPipeline.widgetFrame(idx, layoutW: w, layoutH: h);
            });
            return child;
          }
          ReaderPipeline.widgetLoading(
            idx,
            loaded: progress.cumulativeBytesLoaded,
            total: progress.expectedTotalBytes,
          );
          final total = progress.expectedTotalBytes;
          final value = (total != null && total > 0)
              ? (progress.cumulativeBytesLoaded / total).clamp(0.0, 1.0)
              : null;
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 3,
                  color: Colors.white54,
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stack) {
          ReaderPipeline.widgetError(idx, error: error);
          return ColoredBox(
            color: const Color(0xFF111111),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined, color: Colors.white38),
                  const SizedBox(height: 6),
                  Text(
                    '第${idx + 1}页失败',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
