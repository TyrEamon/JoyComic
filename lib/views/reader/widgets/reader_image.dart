/// 阅读器单图：标准 ImageProvider 链路上屏。
///
/// 下载/JM 重组 → [StreamImageProvider] → [ComicPageImage] (RawImage)。
/// 不再使用自研 Image.memory / 临时文件状态机。
library;

import 'package:flutter/material.dart';

import '../image_pipeline/comic_page_image.dart';
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
    this.fit = BoxFit.cover,
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

  static void clearSizeCache() => ComicPageImage.clearSizeCache();

  @override
  Widget build(BuildContext context) {
    final provider = createPageImageProvider(
      url: url,
      cacheKey: cacheKey ?? url,
      fallbackUrls: fallbackUrls,
      headers: headers,
      bytesTransformer: bytesTransformer,
      traceId: traceId,
      imageIndex: imageIndex,
    );

    final w = width ?? MediaQuery.sizeOf(context).width;
    final h = height ?? w * 1.2;

    return ComicPageImage(
      image: provider,
      width: w,
      height: h,
      fit: fit,
      filterQuality: filterQuality,
      alignment: alignment,
      cacheWidth: cacheWidth,
    );
  }
}
