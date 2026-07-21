/// 阅读器单图：用已验证的「字节 → Image.memory」路径上屏。
///
/// 不再走 RetryForImage + Image(provider) 二次 resolve（真机日志显示
/// first frame / codec 已成功但仍黑屏）。JM 重组后的 JPEG 字节直接交给
/// [Image.memory]，与 Flutter 最基础用法一致。
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
  final void Function(int width, int height)? onImageSizeChanged;
  final String? traceId;
  final int? imageIndex;
  final int maxAttempts;

  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  static const double _fallbackAspect = 3 / 4;

  Uint8List? _bytes;
  int? _pixelW;
  int? _pixelH;
  Object? _error;
  int _attempt = 0;
  bool _loading = true;
  int _loadGen = 0;

  bool get _isNetwork {
    final scheme = Uri.tryParse(widget.url)?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  @override
  void initState() {
    super.initState();
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
      _startLoad();
    }
  }

  void _startLoad() {
    final gen = ++_loadGen;
    setState(() {
      _loading = true;
      _error = null;
      // Keep previous bytes until new ones arrive (gapless).
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

      // Read pixel size once for list layout ( ComicImage pattern).
      int? pw;
      int? ph;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        pw = frame.image.width;
        ph = frame.image.height;
        frame.image.dispose();
      } catch (_) {
        // Image.memory can still decode; layout falls back to 3:4.
      }

      if (!mounted || gen != _loadGen) return;

      setState(() {
        _bytes = bytes;
        _pixelW = pw;
        _pixelH = ph;
        _loading = false;
        _error = null;
      });

      if (widget.traceId != null) {
        final layoutW = MediaQuery.sizeOf(context).width;
        final aspect = (pw != null && ph != null && pw > 0 && ph > 0)
            ? pw / ph
            : _fallbackAspect;
        final layoutH = (layoutW / aspect).ceilToDouble();
        Log.i(
          'Reader first frame',
          'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
          'size=${pw ?? '?'}x${ph ?? '?'} '
          'layout=${layoutW.toStringAsFixed(1)}x${layoutH.toStringAsFixed(1)} '
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

  double _width(BoxConstraints c) {
    if (c.hasBoundedWidth && c.maxWidth.isFinite && c.maxWidth > 0) {
      return c.maxWidth;
    }
    final mq = MediaQuery.sizeOf(context).width;
    return mq > 0 ? mq : 390;
  }

  double _height(double width) {
    final w = _pixelW;
    final h = _pixelH;
    if (w != null && h != null && w > 0 && h > 0) {
      return (width * h / w).ceilToDouble();
    }
    return width / _fallbackAspect;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _width(constraints);
        final height = _height(width);
        final bytes = _bytes;

        if (bytes != null) {
          // Flutter stock path: paint decoded file bytes. No ImageProvider
          // re-resolve, no RawImage lifecycle, no custom completer.
          return ColoredBox(
            color: const Color(0xFF1A1A1A),
            child: Image.memory(
              bytes,
              key: ValueKey(
                '${widget.cacheKey ?? widget.url}:${bytes.length}',
              ),
              width: width,
              height: height,
              fit: widget.fit,
              alignment: widget.alignment is Alignment
                  ? widget.alignment as Alignment
                  : Alignment.center,
              filterQuality: widget.filterQuality,
              gaplessPlayback: true,
              // cacheWidth reduces GPU upload on large JM JPEGs.
              cacheWidth: widget.cacheWidth,
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

        // Loading: visible slate + spinner (not pure black).
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
      },
    );
  }
}
