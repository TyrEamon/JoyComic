/// 阅读器单图：与已验证出图版本相同的标准路径。
///
/// [createPageImageProvider] → 系统 [Image]。
/// 不做 InteractiveViewer、不二次 ImageStream 订阅。
library;

import 'package:flutter/material.dart';

import '../image_pipeline/page_image_provider.dart';
import '../utils/reader_image_provider.dart' show ReaderImageBytesTransformer;
import '../utils/reader_pipeline.dart';

/// 像素尺寸缓存（仅占位，避免列表高度乱跳）。
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
class ReaderImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final w = (width != null && width!.isFinite && width! > 1)
        ? width!
        : (screenW > 1 ? screenW : 390.0);
    final key = cacheKey ?? url;
    final cached = ReaderImageSizeCache.get(key);
    final aspect = (cached != null && cached.width > 0 && cached.height > 0)
        ? cached.width / cached.height
        : 3 / 4;
    final placeholderH = (height != null && height!.isFinite && height! > 1)
        ? height!
        : w / aspect;
    final idx = imageIndex ?? -1;

    final provider = createPageImageProvider(
      url: url,
      cacheKey: key,
      fallbackUrls: fallbackUrls,
      headers: headers,
      bytesTransformer: bytesTransformer,
      traceId: traceId,
      imageIndex: imageIndex,
    );

    return Image(
      image: provider,
      width: w,
      fit: fit,
      alignment: alignment is Alignment
          ? alignment as Alignment
          : Alignment.topCenter,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final box = context.findRenderObject() as RenderBox?;
            final sz = box?.size;
            if (sz != null &&
                sz.width > 1 &&
                sz.height > 1 &&
                ReaderImageSizeCache.get(key) == null) {
              // 用布局比例缓存占位（非二次解码）
              ReaderImageSizeCache.put(
                key,
                sz.width.round(),
                sz.height.round(),
              );
              onImageSizeChanged?.call(sz.width.round(), sz.height.round());
            }
            ReaderPipeline.widgetFrame(
              idx,
              layoutW: sz?.width ?? w,
              layoutH: sz?.height ?? placeholderH,
            );
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
        return SizedBox(
          width: w,
          height: placeholderH,
          child: ColoredBox(
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
          ),
        );
      },
      errorBuilder: (context, error, stack) {
        ReaderPipeline.widgetError(idx, error: error);
        return SizedBox(
          width: w,
          height: placeholderH,
          child: ColoredBox(
            color: const Color(0xFF1A1A1A),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined, color: Colors.white54),
                  const SizedBox(height: 8),
                  Text(
                    '加载失败 第${idx + 1}页',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
