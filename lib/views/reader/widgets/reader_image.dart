/// 阅读器单图。
///
/// 真机日志铁证：S17 已收到帧但 layout=0x0 → 黑屏。
/// 诊断版能出图是因为固定了非零槽位。这里强制 SizedBox(width, height>0)
/// 包住系统 [Image]，与能出图路径一致。
library;

import 'package:flutter/material.dart';

import '../image_pipeline/page_image_provider.dart';
import '../utils/reader_image_provider.dart' show ReaderImageBytesTransformer;
import '../utils/reader_pipeline.dart';

/// 像素宽高比缓存（key → Size(pxW, pxH)）。
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

  /// 永远返回 > 1 的布局宽。
  static double safeWidth(BuildContext context, double? preferred) {
    if (preferred != null && preferred.isFinite && preferred > 1) {
      return preferred;
    }
    final mq = MediaQuery.sizeOf(context).width;
    if (mq.isFinite && mq > 1) return mq;
    return 390;
  }

  /// 永远返回 > 1 的布局高。
  static double safeHeight(double width, double? preferred, String cacheKey) {
    if (preferred != null && preferred.isFinite && preferred > 1) {
      return preferred;
    }
    final cached = ReaderImageSizeCache.get(cacheKey);
    if (cached != null && cached.width > 0 && cached.height > 0) {
      final h = width * cached.height / cached.width;
      if (h.isFinite && h > 1) return h;
    }
    // 默认 3:4 竖图占位（与诊断版固定 520 同理：非零）
    final h = width / (3 / 4);
    return h.isFinite && h > 1 ? h : 520;
  }

  @override
  Widget build(BuildContext context) {
    final key = cacheKey ?? url;
    final w = safeWidth(context, width);
    final h = safeHeight(w, height, key);
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

    // 强制非零槽位——诊断版能出图的关键差异。
    return SizedBox(
      width: w,
      height: h,
      child: Image(
        image: provider,
        width: w,
        height: h,
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              final box = context.findRenderObject() as RenderBox?;
              final sz = box?.size;
              final lw = (sz != null && sz.width > 1) ? sz.width : w;
              final lh = (sz != null && sz.height > 1) ? sz.height : h;
              ReaderPipeline.widgetFrame(idx, layoutW: lw, layoutH: lh);
              // 用布局比例更新缓存，供下次占位
              if (lw > 1 && lh > 1) {
                ReaderImageSizeCache.put(key, lw.round(), lh.round());
                onImageSizeChanged?.call(lw.round(), lh.round());
              }
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
            color: const Color(0xFF1A1A1A),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '加载失败 第${idx + 1}页',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
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
