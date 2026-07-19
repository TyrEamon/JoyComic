/// 漫画单图加载显示的通用组件。
///
/// 使用源感知网络图片 provider 或 [FileImage] 加载，以
/// [ResizeImage.resizeIfNeeded] 包裹保证缓存键与预加载一致。
/// 集成 [RetryForImage] 提供自动重试、进度指示和容错。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/reader_image_provider.dart';
import 'retry_for_image.dart';

/// 漫画单图加载显示组件。
///
/// [url] 可为网络地址（http/https）或本地文件路径。
/// [onImageSizeChanged] 在图片解码成功时回调（当前仅记录，留阶段4 写 DB）。
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
    this.alignment = Alignment.center,
    this.onImageSizeChanged,
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

  bool get _isNetwork {
    final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  ImageProvider _buildProvider() {
    final ImageProvider base = _isNetwork
        ? readerImageProvider(
            url: url,
            cacheKey: cacheKey ?? url,
            fallbackUrls: fallbackUrls,
            headers: headers,
            bytesTransformer: bytesTransformer,
            cacheWidth: cacheWidth,
          )
        : FileImage(File(url));
    return base is ResizeImage
        ? base
        : ResizeImage.resizeIfNeeded(cacheWidth, null, base);
  }

  @override
  Widget build(BuildContext context) {
    return RetryForImage(
      imageProvider: _buildProvider(),
      onImageResolved: (info) {
        onImageSizeChanged?.call(info.image.width, info.image.height);
      },
      builder: (context, status) {
        if (status.isLoaded) {
          return Image(
            image: status.provider,
            fit: fit,
            filterQuality: filterQuality,
            alignment: alignment,
          );
        }
        if (status.isExhausted) {
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 220),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined, size: 40),
                    const SizedBox(height: 10),
                    Text(
                      '图片加载失败',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: status.retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        // loading: show progress indicator
        final chunk = status.chunk;
        double? progress;
        if (chunk != null) {
          final total = chunk.expectedTotalBytes;
          final loaded = chunk.cumulativeBytesLoaded;
          if (total != null && total > 0) {
            progress = (loaded / total).clamp(0.0, 1.0);
          }
        }
        return Center(
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 3,
            constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
            strokeCap: StrokeCap.round,
          ),
        );
      },
    );
  }
}
