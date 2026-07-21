/// 阅读器单图：下载/JM 重组后用 [Image.memory] 上屏。
///
/// 真机日志已证明解码与布局都成功（size=960x1378 layout=440x631）仍黑屏，
/// 说明问题在 ImageStream/RawImage 绘制路径。这里改为最稳妥的
/// `Image.memory(jpegBytes)`，由 Flutter 内置 Image 组件负责解码与上屏。
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  static void clearSizeCache() => _ReaderImageState.clear();

  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  /// Pixel-size cache keyed by cacheKey/url for list height.
  static final Map<String, Size> _sizeCache = {};

  static void clear() => _sizeCache.clear();

  Uint8List? _bytes;
  int? _pixelW;
  int? _pixelH;
  Object? _error;
  int _attempt = 0;
  bool _loading = true;
  int _loadGen = 0;
  bool _loggedFirstFrame = false;

  String get _sizeKey => widget.cacheKey ?? widget.url;

  bool get _isNetwork {
    final scheme = Uri.tryParse(widget.url)?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  @override
  void initState() {
    super.initState();
    final cached = _sizeCache[_sizeKey];
    if (cached != null) {
      _pixelW = cached.width.round();
      _pixelH = cached.height.round();
    }
    _startLoad();
  }

  @override
  void didUpdateWidget(covariant ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.bytesTransformer != widget.bytesTransformer ||
        oldWidget.cacheWidth != widget.cacheWidth) {
      _attempt = 0;
      _loggedFirstFrame = false;
      _startLoad();
    }
  }

  void _startLoad() {
    final gen = ++_loadGen;
    setState(() {
      _loading = true;
      _error = null;
    });
    unawaited(_load(gen));
  }

  Future<void> _load(int gen) async {
    try {
      final Uint8List bytes;
      if (_isNetwork) {
        final provider = ReaderNetworkImageProvider(
          url: widget.url,
          cacheKey: widget.cacheKey ?? widget.url,
          fallbackUrls: widget.fallbackUrls,
          headers: widget.headers,
          bytesTransformer: widget.bytesTransformer,
          traceId: widget.traceId,
          imageIndex: widget.imageIndex,
        );
        bytes = await provider.fetchBytes();
      } else {
        bytes = await File(widget.url).readAsBytes();
      }

      int? pw;
      int? ph;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        pw = frame.image.width;
        ph = frame.image.height;
        frame.image.dispose();
        codec.dispose();
      } catch (_) {
        // Image.memory can still try; layout falls back to 3:4.
      }

      if (!mounted || gen != _loadGen) return;

      setState(() {
        _bytes = bytes;
        if (pw != null && ph != null && pw > 0 && ph > 0) {
          _pixelW = pw;
          _pixelH = ph;
          _sizeCache[_sizeKey] = Size(pw.toDouble(), ph.toDouble());
        }
        _loading = false;
        _error = null;
      });

      if (!_loggedFirstFrame && widget.traceId != null) {
        _loggedFirstFrame = true;
        final layoutW = _resolveWidth();
        final aspect = (pw != null && ph != null && pw > 0 && ph > 0)
            ? pw / ph
            : 3 / 4;
        final layoutH = layoutW / aspect;
        Log.i(
          'Reader first frame',
          'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
          'size=${pw ?? '?'}x${ph ?? '?'} '
          'layout=${layoutW.toStringAsFixed(1)}x${layoutH.toStringAsFixed(1)} '
          'propW=${widget.width?.toStringAsFixed(1) ?? 'null'} '
          'bytes=${bytes.length} via=memory '
          'cache=${ReaderDiagnostics.cacheKeySummary(widget.cacheKey ?? widget.url)}',
        );
      }
      if (pw != null && ph != null) {
        widget.onImageSizeChanged?.call(pw, ph);
      }
    } catch (error) {
      if (!mounted || gen != _loadGen) return;
      final nextAttempt = _attempt + 1;
      if (nextAttempt < widget.maxAttempts) {
        setState(() => _attempt = nextAttempt);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (!mounted || gen != _loadGen) return;
        await _load(gen);
        return;
      }
      setState(() {
        _loading = false;
        _error = error;
        _attempt = nextAttempt;
      });
      if (widget.traceId != null) {
        Log.w(
          'Reader image exhausted',
          error:
              'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} err=$error',
        );
      }
    }
  }

  double _resolveWidth() {
    final candidates = <double>[
      if (widget.width != null) widget.width!,
      MediaQuery.sizeOf(context).width,
      390,
    ];
    for (final w in candidates) {
      if (w.isFinite && w > 1) return w;
    }
    return 390;
  }

  double _resolveHeight(double width) {
    final w = _pixelW;
    final h = _pixelH;
    if (w != null && h != null && w > 0 && h > 0) {
      final out = (width * h / w).ceilToDouble();
      if (out.isFinite && out > 0) return out;
    }
    final propH = widget.height;
    if (propH != null && propH.isFinite && propH > 0) return propH;
    return width * 1.2;
  }

  @override
  Widget build(BuildContext context) {
    final width = _resolveWidth();
    final height = _resolveHeight(width);
    final bytes = _bytes;

    if (bytes != null) {
      // Bright underlay makes "painted but black bitmap" vs empty obvious.
      return ColoredBox(
        color: const Color(0xFF2A2A2A),
        child: Image.memory(
          bytes,
          key: ValueKey('$_sizeKey:${bytes.length}'),
          width: width,
          height: height,
          fit: BoxFit.fitWidth,
          alignment: widget.alignment is Alignment
              ? widget.alignment as Alignment
              : Alignment.center,
          filterQuality: widget.filterQuality,
          gaplessPlayback: true,
          // Decode closer to display size to avoid huge GPU uploads.
          cacheWidth: widget.cacheWidth,
          errorBuilder: (context, error, stack) {
            if (widget.traceId != null) {
              Log.w(
                'Reader Image.memory failed',
                error:
                    'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
                    'err=$error',
              );
            }
            return SizedBox(
              width: width,
              height: height,
              child: const Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.white70),
              ),
            );
          },
        ),
      );
    }

    if (_error != null && !_loading) {
      return SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: const Color(0xFF2A2A2A),
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
                FilledButton.tonalIcon(
                  onPressed: () {
                    _attempt = 0;
                    _startLoad();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Loading: slate + spinner (not pure black).
    return SizedBox(
      width: width,
      height: height,
      child: const ColoredBox(
        color: Color(0xFF2A2A2A),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFFECECEC),
            ),
          ),
        ),
      ),
    );
  }
}
