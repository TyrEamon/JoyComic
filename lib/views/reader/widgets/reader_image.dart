/// 阅读器单图 —— 对齐 HakaComic / PicaComic 可工作结构。
///
/// ## 设计要点
/// - **竖读**：解码后按像素宽高比撑开高度，列表形成连续条带
/// - **横读 / Expanded**：父级有有界高度时填满约束，[BoxFit.contain]
/// - 不用固定槽 + [Expanded] 包系统 [Image]（真机多次黑屏）
/// - 尺寸只写 [ReaderImageSizeCache]，不触发父列表 setState 改槽高
library;

import 'package:flutter/material.dart';

import '../image_pipeline/page_image_provider.dart';
import '../utils/reader_image_provider.dart' show ReaderImageBytesTransformer;
import '../utils/reader_pipeline.dart';

/// 进程内宽高缓存。
class ReaderImageSizeCache {
  ReaderImageSizeCache._();
  static final Map<String, Size> _sizes = <String, Size>{};

  static Size? get(String key) => _sizes[key];

  static void put(String key, int w, int h) {
    if (key.isEmpty || w <= 0 || h <= 0) return;
    _sizes[key] = Size(w.toDouble(), h.toDouble());
  }

  static void clear() => _sizes.clear();
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
  final String? traceId;
  final int? imageIndex;
  final int maxAttempts;

  static void clearSizeCache() => ReaderImageSizeCache.clear();

  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  /// 未缓存时默认宽/高（竖图）。
  static const double _kFallbackAspect = 1 / 1.41;

  late ImageProvider _provider;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  ImageChunkEvent? _chunk;
  Object? _error;
  int _attempt = 0;
  bool _sizeReported = false;

  String get _key => widget.cacheKey ?? widget.url;
  int get _idx => widget.imageIndex ?? -1;

  @override
  void initState() {
    super.initState();
    _provider = _buildProvider();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.cacheWidth != widget.cacheWidth ||
        oldWidget.headers != widget.headers ||
        oldWidget.bytesTransformer != widget.bytesTransformer) {
      _resetAndResolve();
    }
  }

  @override
  void dispose() {
    _detach();
    _info?.dispose();
    _info = null;
    super.dispose();
  }

  ImageProvider _buildProvider() {
    final base = createPageImageProvider(
      url: widget.url,
      cacheKey: _key,
      fallbackUrls: widget.fallbackUrls,
      headers: widget.headers,
      bytesTransformer: widget.bytesTransformer,
      traceId: widget.traceId,
      imageIndex: widget.imageIndex,
    );
    return ResizeImage.resizeIfNeeded(widget.cacheWidth, null, base);
  }

  void _resetAndResolve() {
    _attempt = 0;
    _error = null;
    _chunk = null;
    _sizeReported = false;
    final old = _info;
    _info = null;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _provider = _buildProvider();
    _resolve();
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  void _resolve() {
    _detach();
    final stream = _provider.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener(
      (ImageInfo info, bool sync) {
        final old = _info;
        _info = info;
        if (old != null && !identical(old, info)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
        }
        if (!_sizeReported) {
          _sizeReported = true;
          ReaderImageSizeCache.put(_key, info.image.width, info.image.height);
          ReaderPipeline.widgetFrame(
            _idx,
            layoutW: info.image.width.toDouble(),
            layoutH: info.image.height.toDouble(),
          );
        }
        if (mounted) {
          setState(() {
            _chunk = null;
            _error = null;
          });
        }
      },
      onChunk: (event) {
        if (mounted) setState(() => _chunk = event);
      },
      onError: (Object error, StackTrace? stack) {
        ReaderPipeline.widgetError(_idx, error: error);
        if (!mounted) return;
        setState(() => _error = error);
        if (_attempt < widget.maxAttempts) {
          Future<void>.delayed(const Duration(milliseconds: 300), () {
            if (!mounted) return;
            _attempt += 1;
            setState(() => _error = null);
            _provider = _buildProvider();
            _resolve();
          });
        }
      },
    );
    _stream = stream;
    stream.addListener(_listener!);
  }

  void _manualRetry() {
    _resetAndResolve();
    if (mounted) setState(() {});
  }

  double get _aspectRatio {
    final cached = ReaderImageSizeCache.get(_key);
    if (cached != null && cached.width > 0 && cached.height > 0) {
      return cached.width / cached.height;
    }
    if (_info != null &&
        _info!.image.width > 0 &&
        _info!.image.height > 0) {
      return _info!.image.width / _info!.image.height;
    }
    return _kFallbackAspect;
  }

  Widget _placeholder(double width, {double? height, required Widget child}) {
    if (height != null && height.isFinite && height > 0) {
      return SizedBox(
        width: width,
        height: height,
        child: ColoredBox(color: Colors.black, child: Center(child: child)),
      );
    }
    return AspectRatio(
      aspectRatio: _aspectRatio,
      child: ColoredBox(color: Colors.black, child: Center(child: child)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mqW = MediaQuery.sizeOf(context).width;
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : mqW;
        // Expanded / PhotoView 子项：有有界高度 → 填满父级
        final boundedH =
            constraints.maxHeight.isFinite &&
            constraints.maxHeight > 0 &&
            constraints.maxHeight < 100000;

        if (_error != null && _attempt >= widget.maxAttempts) {
          return _placeholder(
            width,
            height: boundedH ? constraints.maxHeight : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '加载失败 第${_idx + 1}页',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                TextButton(
                  onPressed: _manualRetry,
                  child: const Text(
                    '重试',
                    style: TextStyle(color: Colors.lightBlue),
                  ),
                ),
              ],
            ),
          );
        }

        if (_info != null) {
          final img = _info!.image;
          if (boundedH) {
            // 横向 / 固定视口：contain 填满
            return SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: RawImage(
                image: img,
                width: width,
                height: constraints.maxHeight,
                fit: widget.fit,
                alignment: widget.alignment,
                filterQuality: widget.filterQuality,
                scale: _info!.scale,
              ),
            );
          }

          // 竖读连续：按真实比例撑开（Haka / Pica type4）
          final imgW = img.width.toDouble();
          final imgH = img.height.toDouble();
          final height =
              imgW > 0 ? (width * imgH / imgW) : width / _kFallbackAspect;
          final h = (height.isFinite && height > 1) ? height : width * 1.41;

          return SizedBox(
            width: width,
            height: h,
            child: RawImage(
              image: img,
              width: width,
              height: h,
              fit: BoxFit.fitWidth,
              alignment: widget.alignment,
              filterQuality: widget.filterQuality,
              scale: _info!.scale,
            ),
          );
        }

        double? progress;
        final total = _chunk?.expectedTotalBytes;
        final loaded = _chunk?.cumulativeBytesLoaded;
        if (total != null && total > 0 && loaded != null) {
          progress = (loaded / total).clamp(0.0, 1.0);
        }

        return _placeholder(
          width,
          height: boundedH ? constraints.maxHeight : null,
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 3,
              color: Colors.white54,
            ),
          ),
        );
      },
    );
  }
}
