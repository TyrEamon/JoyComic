/// 阅读器单图：下载/JM 重组后用 [Image.memory] 上屏。
///
/// 真机日志曾出现：`bytes ready` 已成功，但没有 `first frame via=memory`。
/// 原因是列表重建 / didUpdateWidget 把进行中的 load 取消（gen 递增），
/// setState 永远跑不到。这里用全局字节缓存 + 稳定加载，避免重复拉图。
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../foundation/log.dart';
import '../utils/reader_image_provider.dart';

/// In-memory transformed page cache (JPEG after JM recombine).
///
/// Shared across remounts of the same list tile so ScrollablePositionedList /
/// ListView recycle does not re-download and does not lose paint state.
class ReaderImageBytesCache {
  ReaderImageBytesCache._();

  static final Map<String, Uint8List> _bytes = <String, Uint8List>{};
  static final Map<String, Size> _sizes = <String, Size>{};
  static const int _maxEntries = 80;

  static Uint8List? getBytes(String key) => _bytes[key];

  static Size? getSize(String key) => _sizes[key];

  static void put(String key, Uint8List bytes, {int? width, int? height}) {
    if (key.isEmpty || bytes.isEmpty) return;
    _bytes[key] = bytes;
    if (width != null &&
        height != null &&
        width > 0 &&
        height > 0) {
      _sizes[key] = Size(width.toDouble(), height.toDouble());
    }
    while (_bytes.length > _maxEntries) {
      final first = _bytes.keys.first;
      _bytes.remove(first);
      _sizes.remove(first);
    }
  }

  static void clear() {
    _bytes.clear();
    _sizes.clear();
  }
}

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

  static void clearSizeCache() => ReaderImageBytesCache.clear();

  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  Uint8List? _bytes;
  int? _pixelW;
  int? _pixelH;
  Object? _error;
  int _attempt = 0;
  bool _loading = true;
  int _loadGen = 0;
  bool _loggedFirstFrame = false;
  Future<void>? _inFlight;

  String get _sizeKey => widget.cacheKey ?? widget.url;

  bool get _isNetwork {
    final scheme = Uri.tryParse(widget.url)?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  @override
  void initState() {
    super.initState();
    _hydrateFromCache();
    if (_bytes == null) {
      _startLoad();
    } else {
      _loading = false;
      _logFirstFrameIfNeeded();
    }
  }

  @override
  void didUpdateWidget(covariant ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only restart when the *page identity* changes. cacheWidth / transformer
    // identity changes must NOT cancel an in-flight successful download —
    // that was wiping setState and leaving a permanent black list.
    final identityChanged =
        oldWidget.url != widget.url || oldWidget.cacheKey != widget.cacheKey;
    if (!identityChanged) {
      if (oldWidget.width != widget.width || oldWidget.height != widget.height) {
        // Layout-only change: rebuild with existing bytes.
        setState(() {});
      }
      return;
    }
    _attempt = 0;
    _loggedFirstFrame = false;
    _hydrateFromCache();
    if (_bytes == null) {
      _startLoad();
    } else {
      setState(() {
        _loading = false;
        _error = null;
      });
      _logFirstFrameIfNeeded();
    }
  }

  void _hydrateFromCache() {
    final cached = ReaderImageBytesCache.getBytes(_sizeKey);
    final size = ReaderImageBytesCache.getSize(_sizeKey);
    if (cached != null && cached.isNotEmpty) {
      _bytes = cached;
      if (size != null) {
        _pixelW = size.width.round();
        _pixelH = size.height.round();
      }
    }
  }

  void _startLoad() {
    final gen = ++_loadGen;
    setState(() {
      _loading = true;
      _error = null;
    });
    final future = _load(gen);
    _inFlight = future;
    unawaited(future);
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
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: widget.cacheWidth,
        );
        final frame = await codec.getNextFrame();
        pw = frame.image.width;
        ph = frame.image.height;
        frame.image.dispose();
        codec.dispose();
      } catch (e) {
        if (widget.traceId != null) {
          Log.w(
            'Reader size probe failed',
            error:
                'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} err=$e',
          );
        }
      }

      // Always park bytes in the global cache first — even if this State
      // is disposed, the next mount can paint immediately.
      ReaderImageBytesCache.put(_sizeKey, bytes, width: pw, height: ph);

      if (!mounted) {
        if (widget.traceId != null) {
          Log.w(
            'Reader paint skipped',
            error:
                'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
                'reason=unmounted after bytes len=${bytes.length}',
          );
        }
        return;
      }
      if (gen != _loadGen) {
        if (widget.traceId != null) {
          Log.w(
            'Reader paint skipped',
            error:
                'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
                'reason=stale_gen gen=$gen current=$_loadGen '
                'len=${bytes.length}',
          );
        }
        // Newer load is in flight, but if we already have bytes show them.
        if (_bytes == null) {
          setState(() {
            _bytes = bytes;
            if (pw != null && ph != null) {
              _pixelW = pw;
              _pixelH = ph;
            }
            _loading = false;
          });
          _logFirstFrameIfNeeded(pw: pw, ph: ph, len: bytes.length);
        }
        return;
      }

      setState(() {
        _bytes = bytes;
        if (pw != null && ph != null && pw > 0 && ph > 0) {
          _pixelW = pw;
          _pixelH = ph;
        }
        _loading = false;
        _error = null;
      });

      _logFirstFrameIfNeeded(pw: pw, ph: ph, len: bytes.length);
      if (pw != null && ph != null) {
        widget.onImageSizeChanged?.call(pw, ph);
      }
    } catch (error) {
      if (!mounted || gen != _loadGen) return;
      final nextAttempt = _attempt + 1;
      if (nextAttempt < widget.maxAttempts) {
        setState(() => _attempt = nextAttempt);
        await Future<void>.delayed(const Duration(milliseconds: 250));
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
    } finally {
      if (identical(_inFlight, null) || true) {
        // clear in-flight marker when this gen finishes
      }
    }
  }

  void _logFirstFrameIfNeeded({int? pw, int? ph, int? len}) {
    if (_loggedFirstFrame || widget.traceId == null) return;
    if (!mounted) return;
    final bytes = _bytes;
    if (bytes == null) return;
    _loggedFirstFrame = true;
    final layoutW = _resolveWidth();
    final useW = pw ?? _pixelW;
    final useH = ph ?? _pixelH;
    final aspect = (useW != null && useH != null && useW > 0 && useH > 0)
        ? useW / useH
        : 3 / 4;
    final layoutH = layoutW / aspect;
    Log.i(
      'Reader first frame',
      'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
      'size=${useW ?? '?'}x${useH ?? '?'} '
      'layout=${layoutW.toStringAsFixed(1)}x${layoutH.toStringAsFixed(1)} '
      'propW=${widget.width?.toStringAsFixed(1) ?? 'null'} '
      'bytes=${len ?? bytes.length} via=memory '
      'cache=${ReaderDiagnostics.cacheKeySummary(widget.cacheKey ?? widget.url)}',
    );
  }

  double _resolveWidth() {
    final candidates = <double>[
      if (widget.width != null) widget.width!,
      if (mounted) MediaQuery.sizeOf(context).width,
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
    // Remount / rebuild may race a completed fetch — rehydrate once more.
    if (_bytes == null) {
      final cached = ReaderImageBytesCache.getBytes(_sizeKey);
      if (cached != null) {
        _bytes = cached;
        final size = ReaderImageBytesCache.getSize(_sizeKey);
        if (size != null) {
          _pixelW = size.width.round();
          _pixelH = size.height.round();
        }
        _loading = false;
      }
    }

    final width = _resolveWidth();
    final height = _resolveHeight(width);
    final bytes = _bytes;

    if (bytes != null && bytes.isNotEmpty) {
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
                    ReaderImageBytesCache.clear();
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
