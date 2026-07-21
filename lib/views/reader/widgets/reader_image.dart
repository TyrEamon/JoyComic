/// 阅读器单图：与可用阅读器相同的标准路径。
///
/// [ImageProvider] → Flutter 内置 [Image] 组件。
/// 不做自研 ImageStream / RawImage / Image.memory 状态机。
/// JM 重组在 [createPageImageProvider] 的下载流里完成。
library;

import 'package:flutter/material.dart';

import '../image_pipeline/page_image_provider.dart';
import '../utils/reader_image_provider.dart' show ReaderImageBytesTransformer;

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

  static void clearSizeCache() {}

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final w = (width != null && width!.isFinite && width! > 1)
        ? width!
        : (screenW > 1 ? screenW : 390.0);
    final placeholderH = (height != null && height!.isFinite && height! > 1)
        ? height!
        : w * 1.2;

    final provider = createPageImageProvider(
      url: url,
      cacheKey: cacheKey ?? url,
      fallbackUrls: fallbackUrls,
      headers: headers,
      bytesTransformer: bytesTransformer,
      traceId: traceId,
      imageIndex: imageIndex,
    );

    // 与可用阅读器一致：系统 [Image] 组件，不手写 stream 监听。
    return Image(
      image: provider,
      width: w,
      fit: fit,
      alignment: alignment is Alignment
          ? alignment as Alignment
          : Alignment.center,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) {
          // 已解码：直接返回 child（系统 Image 会按宽高比占位）。
          return child;
        }
        final total = progress.expectedTotalBytes;
        final value = (total != null && total > 0)
            ? (progress.cumulativeBytesLoaded / total).clamp(0.0, 1.0)
            : null;
        return SizedBox(
          width: w,
          height: placeholderH,
          child: ColoredBox(
            color: const Color(0xFF1A1A1A),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 3,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) {
        return SizedBox(
          width: w,
          height: placeholderH,
          child: ColoredBox(
            color: const Color(0xFF3E2723),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined, color: Colors.white70),
                  const SizedBox(height: 8),
                  Text(
                    '加载失败 第${(imageIndex ?? 0) + 1}页',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
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
