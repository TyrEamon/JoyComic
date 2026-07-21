/// 阅读器单图。
///
/// 策略（针对「转圈后黑屏」）：
/// 1. 下载 + JM 重组后的字节写入临时文件
/// 2. 用 [Image.file] 上屏（比 Image.memory 在 iOS 上更稳）
/// 3. 加载成功时显示绿色状态条，便于确认组件已挂上且有数据
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../../foundation/log.dart';
import '../utils/reader_image_provider.dart';

/// Transformed page bytes + optional on-disk path.
class CachedReaderPage {
  const CachedReaderPage({
    required this.bytes,
    this.filePath,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String? filePath;
  final int? width;
  final int? height;
}

class ReaderImageBytesCache {
  ReaderImageBytesCache._();

  static final Map<String, CachedReaderPage> _pages =
      <String, CachedReaderPage>{};
  static const int _maxEntries = 60;

  static CachedReaderPage? get(String key) => _pages[key];

  static void put(String key, CachedReaderPage page) {
    if (key.isEmpty || page.bytes.isEmpty) return;
    _pages[key] = page;
    while (_pages.length > _maxEntries) {
      final first = _pages.keys.first;
      final old = _pages.remove(first);
      final path = old?.filePath;
      if (path != null) {
        try {
          final f = File(path);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
  }

  static void clear() {
    for (final page in _pages.values) {
      final path = page.filePath;
      if (path == null) continue;
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _pages.clear();
  }
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
  String? _filePath;
  int? _pixelW;
  int? _pixelH;
  Object? _error;
  int _attempt = 0;
  bool _loading = true;
  int _loadGen = 0;
  bool _loggedPaint = false;

  String get _sizeKey => widget.cacheKey ?? widget.url;

  bool get _isNetwork {
    final scheme = Uri.tryParse(widget.url)?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  @override
  void initState() {
    super.initState();
    if (_applyCache()) {
      _loading = false;
      _logPaint('cache-hit');
    } else {
      _startLoad();
    }
  }

  @override
  void didUpdateWidget(covariant ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final identityChanged =
        oldWidget.url != widget.url || oldWidget.cacheKey != widget.cacheKey;
    if (!identityChanged) return;

    _attempt = 0;
    _loggedPaint = false;
    if (_applyCache()) {
      setState(() {
        _loading = false;
        _error = null;
      });
      _logPaint('cache-hit-update');
    } else {
      _bytes = null;
      _filePath = null;
      _startLoad();
    }
  }

  bool _applyCache() {
    final page = ReaderImageBytesCache.get(_sizeKey);
    if (page == null || page.bytes.isEmpty) return false;
    _bytes = page.bytes;
    _filePath = page.filePath;
    _pixelW = page.width;
    _pixelH = page.height;
    return true;
  }

  void _startLoad() {
    final gen = ++_loadGen;
    setState(() {
      _loading = true;
      _error = null;
    });
    unawaited(_load(gen));
  }

  Future<String?> _writeTempFile(Uint8List bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final safe = _sizeKey.hashCode.toUnsigned(32).toRadixString(16);
      final isJpeg = bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8;
      final ext = isJpeg ? 'jpg' : 'img';
      final file = File('${dir.path}/jc_reader_$safe.$ext');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      if (widget.traceId != null) {
        Log.w(
          'Reader temp write failed',
          error: 'trace=${widget.traceId} err=$e',
        );
      }
      return null;
    }
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
      } catch (e) {
        if (widget.traceId != null) {
          Log.w(
            'Reader size probe failed',
            error:
                'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} err=$e',
          );
        }
      }

      final path = await _writeTempFile(bytes);
      ReaderImageBytesCache.put(
        _sizeKey,
        CachedReaderPage(bytes: bytes, filePath: path, width: pw, height: ph),
      );

      if (!mounted || gen != _loadGen) {
        if (widget.traceId != null) {
          Log.w(
            'Reader paint skipped',
            error:
                'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
                'mounted=$mounted gen=$gen/$_loadGen len=${bytes.length}',
          );
        }
        // Still try to show if mounted with stale gen.
        if (mounted && _bytes == null) {
          setState(() {
            _bytes = bytes;
            _filePath = path;
            _pixelW = pw;
            _pixelH = ph;
            _loading = false;
          });
          _logPaint('stale-gen-show', pw: pw, ph: ph, len: bytes.length);
        }
        return;
      }

      setState(() {
        _bytes = bytes;
        _filePath = path;
        if (pw != null && ph != null && pw > 0 && ph > 0) {
          _pixelW = pw;
          _pixelH = ph;
        }
        _loading = false;
        _error = null;
      });
      _logPaint('ready', pw: pw, ph: ph, len: bytes.length);
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
    }
  }

  void _logPaint(String via, {int? pw, int? ph, int? len}) {
    if (_loggedPaint || widget.traceId == null || !mounted) return;
    if (_bytes == null) return;
    _loggedPaint = true;
    final layoutW = _resolveWidth();
    final useW = pw ?? _pixelW;
    final useH = ph ?? _pixelH;
    final aspect = (useW != null && useH != null && useW > 0 && useH > 0)
        ? useW / useH
        : 3 / 4;
    Log.i(
      'Reader first frame',
      'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
      'size=${useW ?? '?'}x${useH ?? '?'} '
      'layout=${layoutW.toStringAsFixed(1)}x${(layoutW / aspect).toStringAsFixed(1)} '
      'propW=${widget.width?.toStringAsFixed(1) ?? 'null'} '
      'bytes=${len ?? _bytes!.length} via=$via file=${_filePath != null} '
      'cache=${ReaderDiagnostics.cacheKeySummary(widget.cacheKey ?? widget.url)}',
    );
  }

  double _resolveWidth() {
    for (final w in <double>[
      if (widget.width != null) widget.width!,
      if (mounted) MediaQuery.sizeOf(context).width,
      390,
    ]) {
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

  Widget _statusBar(String text, Color color) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      _applyCache();
    }

    final width = _resolveWidth();
    final height = _resolveHeight(width);
    final bytes = _bytes;
    final path = _filePath;

    if (bytes != null && bytes.isNotEmpty) {
      final idx = widget.imageIndex ?? -1;
      final imageChild = path != null && File(path).existsSync()
          ? Image.file(
              File(path),
              key: ValueKey('file:$path:${bytes.length}'),
              width: width,
              height: height,
              fit: BoxFit.fitWidth,
              alignment: Alignment.center,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) {
                Log.w(
                  'Reader Image.file failed',
                  error:
                      'trace=${widget.traceId} idx=$idx err=$error → memory',
                );
                return Image.memory(
                  bytes,
                  width: width,
                  height: height,
                  fit: BoxFit.fitWidth,
                  gaplessPlayback: true,
                  errorBuilder: (c, e, s) => _statusBar(
                    '图片解码失败 idx=$idx',
                    Colors.red.shade800,
                  ),
                );
              },
            )
          : Image.memory(
              bytes,
              key: ValueKey('mem:$_sizeKey:${bytes.length}'),
              width: width,
              height: height,
              fit: BoxFit.fitWidth,
              alignment: Alignment.center,
              filterQuality: FilterQuality.low,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) {
                Log.w(
                  'Reader Image.memory failed',
                  error: 'trace=${widget.traceId} idx=$idx err=$error',
                );
                return _statusBar('图片解码失败 idx=$idx', Colors.red.shade800);
              },
            );

      // Green bar MUST be visible if this widget paints — proves tile is alive.
      return ColoredBox(
        color: const Color(0xFF1E1E1E),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statusBar(
              '已加载 第${idx + 1}页 ${bytes.length}B'
              '${path != null ? ' file' : ' mem'}',
              const Color(0xFF1B5E20),
            ),
            imageChild,
          ],
        ),
      );
    }

    if (_error != null && !_loading) {
      return SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: const Color(0xFF3E2723),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, color: Colors.white, size: 40),
                const SizedBox(height: 8),
                const Text('图片加载失败', style: TextStyle(color: Colors.white)),
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

    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: const Color(0xFF263238),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '加载中 第${(widget.imageIndex ?? 0) + 1}页…',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
