/// 阅读器单图 —— 与真机能出图的诊断版一致。
///
/// createPageImageProvider → 系统 [Image]（不要 Image.memory 状态机）。
/// 外层必须非零 [SizedBox]；真机日志 layout=0 会黑，有尺寸仍黑则用固定槽。
library;

import 'package:flutter/material.dart';

import '../image_pipeline/page_image_provider.dart';
import '../utils/reader_image_provider.dart' show ReaderImageBytesTransformer;
import '../utils/reader_pipeline.dart';

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
class ReaderImage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final mqW = MediaQuery.sizeOf(context).width;
    final w = (width != null && width!.isFinite && width! > 1)
        ? width!
        : (mqW > 1 ? mqW : 390.0);
    // 诊断版固定 520 能出图；默认用相近固定高，避免 0 高与乱跳。
    final h = (height != null && height!.isFinite && height! > 1)
        ? height!
        : 520.0;
    final idx = imageIndex ?? -1;
    final key = cacheKey ?? url;

    final provider = createPageImageProvider(
      url: url,
      cacheKey: key,
      fallbackUrls: fallbackUrls,
      headers: headers,
      bytesTransformer: bytesTransformer,
      traceId: traceId,
      imageIndex: imageIndex,
    );

    // 与 49069ac 诊断版相同结构：固定高槽 + Expanded 内 Image(provider)
    return SizedBox(
      width: w,
      height: h,
      child: Image(
        image: provider,
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              final box = context.findRenderObject() as RenderBox?;
              final sz = box?.size;
              ReaderPipeline.widgetFrame(
                idx,
                layoutW: sz?.width ?? w,
                layoutH: sz?.height ?? h,
              );
            });
            return child;
          }
          ReaderPipeline.widgetLoading(
            idx,
            loaded: progress.cumulativeBytesLoaded,
            total: progress.expectedTotalBytes,
          );
          return const ColoredBox(
            color: Color(0xFF1A1A1A),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
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
            color: const Color(0xFF3E2723),
            child: Center(
              child: Text(
                '失败 第${idx + 1}页',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          );
        },
      ),
    );
  }
}
