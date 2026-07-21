/// 漫画单图加载显示组件（对齐  [ComicImage] 生命周期）。
///
/// 管道：
/// 1. 源感知 [ImageProvider]（JM 重组在 provider 内完成）
/// 2. 本 State 直接订阅 [ImageStream]，持有 [ImageStreamCompleterHandle]
///    防止缓存驱逐后 ui.Image 被 dispose 导致黑屏
/// 3. 解码后按屏宽 + 像素宽高比给出显式宽高，再用 [RawImage] 绘制
///
/// 加载中/失败时使用非纯黑占位，避免与 [readerCanvas] 融为一体。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../foundation/log.dart';
import '../utils/reader_image_provider.dart';

/// 漫画单图加载显示组件。
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
    this.onImageSizeChanged,
    this.traceId,
    this.imageIndex,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 200),
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
  final void Function(int width, int height)? onImageSizeChanged;
  final String? traceId;
  final int? imageIndex;
  final int maxAttempts;
  final Duration retryDelay;

  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  static const double _fallbackAspectRatio = 3 / 4;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageStreamCompleterHandle? _completerHandle;
  ImageInfo? _imageInfo;
  ImageChunkEvent? _chunk;
  Object? _error;
  int _attempt = 0;
  bool _resolvedLogged = false;
  Timer? _retryTimer;

  ImageProvider get _provider {
    final scheme = Uri.tryParse(widget.url)?.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      return readerImageProvider(
        url: widget.url,
        cacheKey: widget.cacheKey ?? widget.url,
        fallbackUrls: widget.fallbackUrls,
        headers: widget.headers,
        bytesTransformer: widget.bytesTransformer,
        cacheWidth: widget.cacheWidth,
        traceId: widget.traceId,
        imageIndex: widget.imageIndex,
      );
    }
    return ResizeImage.resizeIfNeeded(
      widget.cacheWidth,
      null,
      FileImage(File(widget.url)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final providerChanged =
        oldWidget.url != widget.url ||
        oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.cacheWidth != widget.cacheWidth ||
        oldWidget.bytesTransformer != widget.bytesTransformer;
    if (providerChanged) {
      _attempt = 0;
      _resolvedLogged = false;
      _error = null;
      _chunk = null;
      _resolve(force: true);
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    // Drop our owned clone first, then release stream keepAlive.
    _replaceImage(null);
    _stopListening(keepStreamAlive: false);
    _completerHandle?.dispose();
    _completerHandle = null;
    super.dispose();
  }

  void _resolve({bool force = false}) {
    final provider = _provider;
    final config = createLocalImageConfiguration(context);
    final newStream = provider.resolve(config);
    if (!force && _stream?.key == newStream.key) {
      _listen();
      return;
    }
    _stopListening(keepStreamAlive: false);
    _stream = newStream;
    _listen();
  }

  void _listen() {
    final stream = _stream;
    if (stream == null) return;
    if (_listener != null) return;

    final listener = ImageStreamListener(
      _handleImage,
      onChunk: _handleChunk,
      onError: _handleError,
    );
    _listener = listener;
    stream.addListener(listener);

    // Keep the completer (and its decoded frames) alive even if the image
    // cache tries to evict under memory pressure — critical on iOS.
    _completerHandle?.dispose();
    _completerHandle = stream.completer?.keepAlive();
  }

  void _stopListening({required bool keepStreamAlive}) {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      if (keepStreamAlive &&
          _completerHandle == null &&
          stream.completer != null) {
        _completerHandle = stream.completer!.keepAlive();
      }
      stream.removeListener(listener);
    }
    _listener = null;
  }

  void _replaceImage(ImageInfo? next) {
    final previous = _imageInfo;
    _imageInfo = next;
    if (previous != null && !identical(previous, next)) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        previous.dispose();
      });
    }
  }

  void _handleImage(ImageInfo info, bool synchronousCall) {
    if (!mounted) return;
    // Clone so ImageCache / MultiFrameImageStreamCompleter can dispose the
    // stream's ImageInfo without zeroing the pixels under RawImage (black tile).
    // keepAlive keeps the completer resident; the clone owns the painted buffer.
    final owned = info.clone();
    setState(() {
      _replaceImage(owned);
      _error = null;
      _chunk = null;
    });
    if (!_resolvedLogged) {
      _resolvedLogged = true;
      final w = owned.image.width;
      final h = owned.image.height;
      final layoutW = _layoutWidth(context);
      final aspect = w > 0 && h > 0 ? w / h : _fallbackAspectRatio;
      final layoutH = (layoutW / aspect).ceilToDouble();
      if (widget.traceId != null) {
        final debugLabel = owned.image.debugDisposed
            ? 'DISPOSED'
            : 'live';
        Log.i(
          'Reader first frame',
          'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
          'size=${w}x$h layout=${layoutW.toStringAsFixed(1)}x'
          '${layoutH.toStringAsFixed(1)} img=$debugLabel '
          'cache=${ReaderDiagnostics.cacheKeySummary(widget.cacheKey ?? widget.url)}',
        );
      }
      widget.onImageSizeChanged?.call(w, h);
    }
  }

  void _handleChunk(ImageChunkEvent event) {
    if (!mounted) return;
    setState(() => _chunk = event);
  }

  void _handleError(Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    final shouldSchedule =
        _attempt < widget.maxAttempts && _retryTimer?.isActive != true;
    setState(() {
      _error = error;
      _chunk = null;
      if (shouldSchedule) _attempt++;
    });
    if (shouldSchedule) {
      _retryTimer = Timer(widget.retryDelay, _autoRetry);
    } else if (widget.traceId != null) {
      Log.w(
        'Reader image exhausted',
        error:
            'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
            'err=${_friendlyError(error) ?? error}',
      );
    }
  }

  Future<void> _autoRetry() async {
    if (!mounted) return;
    _stopListening(keepStreamAlive: false);
    setState(() {
      _error = null;
      _chunk = null;
    });
    if (!mounted) return;
    _resolve(force: true);
  }

  Future<void> _manualRetry() async {
    _retryTimer?.cancel();
    _stopListening(keepStreamAlive: false);
    setState(() {
      _attempt = 0;
      _resolvedLogged = false;
      _error = null;
      _chunk = null;
      _replaceImage(null);
    });
    await _provider.evict();
    if (!mounted) return;
    _resolve(force: true);
  }

  double _layoutWidth(BuildContext context) {
    final mq = MediaQuery.sizeOf(context).width;
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize && box.constraints.hasBoundedWidth) {
      final w = box.constraints.maxWidth;
      if (w.isFinite && w > 0) return w;
    }
    // Parent list often gives tight width via constraints in build.
    return mq > 0 ? mq : 390;
  }

  double _layoutWidthFromConstraints(BoxConstraints constraints) {
    if (constraints.hasBoundedWidth && constraints.maxWidth.isFinite) {
      final w = constraints.maxWidth;
      if (w > 0) return w;
    }
    final mq = MediaQuery.sizeOf(context).width;
    return mq > 0 ? mq : 390;
  }

  Widget _placeholder(double width, Widget child) {
    final height = width / _fallbackAspectRatio;
    // Distinct from pure-black readerCanvas so loading is never invisible.
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: const Color(0xFF2A2A2A),
        child: Center(
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Color(0xFFECECEC)),
            child: IconTheme.merge(
              data: const IconThemeData(color: Color(0xFFECECEC)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFrame(double width) {
    final info = _imageInfo!;
    final pixelW = info.image.width;
    final pixelH = info.image.height;
    final aspect = pixelW > 0 && pixelH > 0
        ? pixelW / pixelH
        : _fallbackAspectRatio;
    final height = (width / aspect).ceilToDouble();
    final align = widget.alignment is Alignment
        ? widget.alignment as Alignment
        : Alignment.center;

    // Prefer Flutter [Image] for the paint path (same as ). It owns a
    // proper ImageStreamListener and is known-good on iOS Impeller. We still
    // keep our own stream + keepAlive so loading/error/retry and size logs
    // work, and so the cache entry stays live while this item is mounted.
    // Explicit width/height prevent zero-height list items.
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: const Color(0xFF1A1A1A),
        child: Image(
          image: _provider,
          width: width,
          height: height,
          fit: widget.fit,
          alignment: align,
          filterQuality: widget.filterQuality,
          gaplessPlayback: true,
          // If Image's secondary resolve is still settling, fall back to the
          // already-decoded frame we hold (avoids a blank flash).
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null || wasSynchronouslyLoaded) {
              return child;
            }
            return RawImage(
              image: info.image,
              scale: info.scale,
              width: width,
              height: height,
              fit: widget.fit,
              alignment: align,
              filterQuality: widget.filterQuality,
            );
          },
          errorBuilder: (context, error, stackTrace) {
            // Stream already decoded once; paint the held frame if Image fails.
            return RawImage(
              image: info.image,
              scale: info.scale,
              width: width,
              height: height,
              fit: widget.fit,
              alignment: align,
              filterQuality: widget.filterQuality,
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _layoutWidthFromConstraints(constraints);

        if (_imageInfo != null) {
          return _buildFrame(width);
        }

        final exhausted =
            _error != null && _attempt >= widget.maxAttempts && _imageInfo == null;
        if (exhausted) {
          final detail = _friendlyError(_error);
          return _placeholder(
            width,
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined, size: 40),
                  const SizedBox(height: 10),
                  const Text('图片加载失败'),
                  if (detail != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _manualRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }

        double? progress;
        final chunk = _chunk;
        if (chunk != null) {
          final total = chunk.expectedTotalBytes;
          final loaded = chunk.cumulativeBytesLoaded;
          if (total != null && total > 0) {
            progress = (loaded / total).clamp(0.0, 1.0);
          }
        }
        return _placeholder(
          width,
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 3,
            color: const Color(0xFFECECEC),
            constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
            strokeCap: StrokeCap.round,
          ),
        );
      },
    );
  }

  static String? _friendlyError(Object? error) {
    if (error == null) return null;
    var message = error.toString().trim();
    message = message.replaceFirst(RegExp(r'^Exception:\s*'), '');
    message = message.replaceFirst(RegExp(r'^Bad state:\s*'), '');
    message = message.replaceFirst(RegExp(r'^StateError:\s*'), '');
    if (message.isEmpty) return null;
    if (message.length > 160) {
      return '${message.substring(0, 157)}...';
    }
    return message;
  }
}
