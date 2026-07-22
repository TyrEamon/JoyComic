/// 阅读器单图（与诊断版能出图路径对齐）。
///
/// 1. 固定非零 [SizedBox] 槽位（避免 layout=0 黑屏）
/// 2. [createPageImageProvider] 下载 + JM 重组拿 JPEG 字节
/// 3. [Image.memory] 上屏（不用 ImageProvider→Image 二次流，真机更稳）
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../image_pipeline/page_image_provider.dart';
import '../utils/reader_image_provider.dart' show ReaderImageBytesTransformer;
import '../utils/reader_pipeline.dart';

/// 已重组 JPEG + 像素尺寸缓存。
class CachedReaderPage {
  CachedReaderPage(this.bytes, this.pxW, this.pxH);
  final Uint8List bytes;
  final int pxW;
  final int pxH;
}

class ReaderImageSizeCache {
  ReaderImageSizeCache._();
  static final Map<String, CachedReaderPage> _map =
      <String, CachedReaderPage>{};

  static CachedReaderPage? get(String key) => _map[key];

  static void put(String key, Uint8List bytes, int w, int h) {
    if (key.isEmpty || bytes.isEmpty || w <= 0 || h <= 0) return;
    _map[key] = CachedReaderPage(bytes, w, h);
    while (_map.length > 60) {
      _map.remove(_map.keys.first);
    }
  }

  static Size? sizeOf(String key) {
    final p = _map[key];
    if (p == null) return null;
    return Size(p.pxW.toDouble(), p.pxH.toDouble());
  }

  static void clear() => _map.clear();
}

/// 漫画单图。
class ReaderImage extends StatefulWidget {
  const ReaderImage({
    super.key,
    required this.url,
    this.cacheKey,
    this.headers,
    this.fallbackUrls = const <String>[],
    this.bytesTransformer,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
    this.cacheWidth,
    this.alignment = Alignment.topCenter,
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
  Uint8List? _bytes;
  int? _pxW;
  int? _pxH;
  Object? _error;
  bool _loading = true;
  int _gen = 0;
  int _attempt = 0;

  String get _key => widget.cacheKey ?? widget.url;
  int get _idx => widget.imageIndex ?? -1;

  double _safeW(BuildContext context) {
    if (widget.width != null && widget.width!.isFinite && widget.width! > 1) {
      return widget.width!;
    }
    final mq = MediaQuery.sizeOf(context).width;
    return mq > 1 ? mq : 390;
  }

  double _safeH(double w) {
    if (widget.height != null && widget.height!.isFinite && widget.height! > 1) {
      return widget.height!;
    }
    if (_pxW != null && _pxH != null && _pxW! > 0 && _pxH! > 0) {
      final h = w * _pxH! / _pxW!;
      if (h.isFinite && h > 1) return h;
    }
    final cached = ReaderImageSizeCache.sizeOf(_key);
    if (cached != null && cached.width > 0 && cached.height > 0) {
      final h = w * cached.height / cached.width;
      if (h.isFinite && h > 1) return h;
    }
    // 诊断版固定 520；默认 4:3 竖图
    final h = w / (3 / 4);
    return h.isFinite && h >= 200 ? h : 520;
  }

  @override
  void initState() {
    super.initState();
    final hit = ReaderImageSizeCache.get(_key);
    if (hit != null) {
      _bytes = hit.bytes;
      _pxW = hit.pxW;
      _pxH = hit.pxH;
      _loading = false;
    } else {
      _start();
    }
  }

  @override
  void didUpdateWidget(covariant ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.cacheKey != widget.cacheKey) {
      _attempt = 0;
      final hit = ReaderImageSizeCache.get(_key);
      if (hit != null) {
        setState(() {
          _bytes = hit.bytes;
          _pxW = hit.pxW;
          _pxH = hit.pxH;
          _loading = false;
          _error = null;
        });
      } else {
        _bytes = null;
        _start();
      }
    }
  }

  void _start() {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    unawaited(_load(gen));
  }

  Future<void> _load(int gen) async {
    final page = _idx;
    try {
      ReaderPipeline.mark(
        ReaderStage.providerLoad,
        pageIndex: page,
        detail: 'memory_path',
      );

      // 复用流水线：progress 流最终带 data
      Uint8List? data;
      await for (final p in pageImageDownloadStream(
        url: widget.url,
        cacheKey: _key,
        fallbackUrls: widget.fallbackUrls,
        headers: widget.headers,
        bytesTransformer: widget.bytesTransformer,
        traceId: widget.traceId,
        imageIndex: widget.imageIndex,
      )) {
        if (p.data != null && p.data!.isNotEmpty) {
          data = p.data;
        }
      }
      if (data == null || data.isEmpty) {
        throw StateError('empty page bytes');
      }

      // 解码拿真实像素尺寸
      int pw = 0;
      int ph = 0;
      try {
        final codec = await ui.instantiateImageCodec(data);
        final frame = await codec.getNextFrame();
        pw = frame.image.width;
        ph = frame.image.height;
        frame.image.dispose();
        codec.dispose();
        ReaderPipeline.codecOk(page, width: pw, height: ph);
      } catch (e) {
        ReaderPipeline.codecFail(page, error: e);
        // 仍尝试 Image.memory
      }

      ReaderImageSizeCache.put(
        _key,
        data,
        pw > 0 ? pw : 960,
        ph > 0 ? ph : 1280,
      );

      if (!mounted || gen != _gen) return;
      setState(() {
        _bytes = data;
        if (pw > 0 && ph > 0) {
          _pxW = pw;
          _pxH = ph;
        }
        _loading = false;
        _error = null;
      });
      if (pw > 0 && ph > 0) {
        widget.onImageSizeChanged?.call(pw, ph);
      }
      final w = _safeW(context);
      final h = _safeH(w);
      ReaderPipeline.widgetFrame(page, layoutW: w, layoutH: h);
    } catch (e) {
      if (!mounted || gen != _gen) return;
      final next = _attempt + 1;
      if (next < widget.maxAttempts) {
        _attempt = next;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!mounted || gen != _gen) return;
        await _load(gen);
        return;
      }
      setState(() {
        _loading = false;
        _error = e;
        _attempt = next;
      });
      ReaderPipeline.widgetError(page, error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _safeW(context);
    final h = _safeH(w);
    final bytes = _bytes;

    // 与诊断版相同：强制非零槽位
    return SizedBox(
      width: w,
      height: h,
      child: ColoredBox(
        // 深灰底：若图黑/空仍能看出槽位在画
        color: const Color(0xFF101010),
        child: () {
          if (bytes != null && bytes.isNotEmpty) {
            return Image.memory(
              bytes,
              key: ValueKey('${_key}_${bytes.length}'),
              width: w,
              height: h,
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
              filterQuality: widget.filterQuality,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) {
                ReaderPipeline.widgetError(_idx, error: error);
                return Center(
                  child: Text(
                    '解码失败 第${_idx + 1}页',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                );
              },
            );
          }
          if (_error != null && !_loading) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined, color: Colors.white54),
                  const SizedBox(height: 8),
                  Text(
                    '加载失败 第${_idx + 1}页',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  TextButton(
                    onPressed: () {
                      _attempt = 0;
                      _start();
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white54,
              ),
            ),
          );
        }(),
      ),
    );
  }
}
