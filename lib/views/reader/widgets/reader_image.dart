/// 漫画单图加载显示的通用组件。
///
/// 使用源感知网络图片 provider 或 [FileImage] 加载，以
/// [ResizeImage.resizeIfNeeded] 包裹保证缓存键与预加载一致。
/// 集成 [RetryForImage] 提供自动重试、进度指示和容错。
///
/// 加载中/失败时使用 3:4 占位高度，避免竖直列表 item 高度为 0 时
/// 整页只剩黑色 canvas（用户感知为“黑屏”）。
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

  static const double _fallbackAspectRatio = 3 / 4;

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

  Widget _placeholder(BuildContext context, Widget child) {
    return AspectRatio(
      aspectRatio: _fallbackAspectRatio,
      child: ColoredBox(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        child: Center(child: child),
      ),
    );
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
          final detail = _friendlyError(status.error);
          return _placeholder(
            context,
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(height: 10),
                  Text('图片加载失败', style: Theme.of(context).textTheme.titleSmall),
                  if (detail != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: status.retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        final chunk = status.chunk;
        double? progress;
        if (chunk != null) {
          final total = chunk.expectedTotalBytes;
          final loaded = chunk.cumulativeBytesLoaded;
          if (total != null && total > 0) {
            progress = (loaded / total).clamp(0.0, 1.0);
          }
        }
        return _placeholder(
          context,
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 3,
            constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
            strokeCap: StrokeCap.round,
          ),
        );
      },
    );
  }

  static String? _friendlyError(Object? error) {
    if (error == null) return null;
    var message = error.toString().trim();
    message = message.replaceFirst(RegExp(r'^Exception:\s*'), '');
    message = message.replaceFirst(RegExp(r'^Bad state:\s*'), '');
    message = message.replaceFirst(RegExp(r'^StateError:\s*'), '');
    if (message.isEmpty) return null;
    if (message.length > 160) {
      return '${message.substring(0, 157)}...';
    }
    return message;
  }
}
