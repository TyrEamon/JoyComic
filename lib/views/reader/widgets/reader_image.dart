/// 漫画单图加载显示的通用组件。
///
/// 使用源感知网络图片 provider 或 [FileImage] 加载，以
/// [ResizeImage.resizeIfNeeded] 包裹保证缓存键与预加载一致。
/// 集成 [RetryForImage] 提供自动重试、进度指示和容错。
///
/// 加载中/失败时使用 3:4 占位高度，避免竖直列表 item 高度为 0 时
/// 整页只剩黑色 canvas（用户感知为“黑屏”）。
///
/// 解码成功后按屏宽与像素宽高比给出显式 [SizedBox] 尺寸（对齐 
/// [ComicImage]），避免 [RawImage] 在竖直列表 / [InteractiveViewer] 下
/// 内在尺寸为 0 而不上屏。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../foundation/log.dart';
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
    this.fit = BoxFit.fitWidth,
    this.filterQuality = FilterQuality.medium,
    this.cacheWidth,
    this.alignment = Alignment.center,
    this.onImageSizeChanged,
    this.traceId,
    this.imageIndex,
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
  final String? traceId;
  final int? imageIndex;

  static const double _fallbackAspectRatio = 3 / 4;

  bool get _isNetwork {
    final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  ImageProvider _buildProvider() {
    // readerImageProvider already applies ResizeImage when cacheWidth is set.
    if (_isNetwork) {
      return readerImageProvider(
        url: url,
        cacheKey: cacheKey ?? url,
        fallbackUrls: fallbackUrls,
        headers: headers,
        bytesTransformer: bytesTransformer,
        cacheWidth: cacheWidth,
        traceId: traceId,
        imageIndex: imageIndex,
      );
    }
    final file = FileImage(File(url));
    return ResizeImage.resizeIfNeeded(cacheWidth, null, file);
  }

  /// Prefer parent max width (list / FractionallySizedBox); fall back to screen.
  double _layoutWidth(BuildContext context, BoxConstraints constraints) {
    if (constraints.hasBoundedWidth && constraints.maxWidth.isFinite) {
      final w = constraints.maxWidth;
      if (w > 0) return w;
    }
    final mq = MediaQuery.sizeOf(context).width;
    return mq > 0 ? mq : 390;
  }

  Widget _placeholder(
    BuildContext context,
    BoxConstraints constraints,
    Widget child,
  ) {
    // Avoid near-black-on-black: reader canvas is pure black.
    final scheme = Theme.of(context).colorScheme;
    final width = _layoutWidth(context, constraints);
    final height = width / _fallbackAspectRatio;
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
        child: Center(
          child: DefaultTextStyle.merge(
            style: TextStyle(color: scheme.onSurface),
            child: IconTheme.merge(
              data: IconThemeData(color: scheme.onSurface),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// Explicit layout box from decoded pixel size — required for vertical
  /// continuous lists so [RawImage] never collapses to zero height.
  Widget _sizedFrame(
    BuildContext context,
    BoxConstraints constraints,
    ImageInfo frame, {
    required int pixelW,
    required int pixelH,
  }) {
    final width = _layoutWidth(context, constraints);
    final aspect = pixelW > 0 && pixelH > 0
        ? pixelW / pixelH
        : _fallbackAspectRatio;
    // Match : ceil height so list items never sub-pixel-collapse.
    final height = (width / aspect).ceilToDouble();
    final align = alignment is Alignment
        ? alignment as Alignment
        : Alignment.center;

    return SizedBox(
      width: width,
      height: height,
      child: RawImage(
        image: frame.image,
        scale: frame.scale,
        width: width,
        height: height,
        fit: fit,
        alignment: align,
        filterQuality: filterQuality,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RetryForImage(
          // Avoid a second blank decode after ImageStream already resolved:
          // paint the decoded frame immediately with RawImage.
          fadeDuration: Duration.zero,
          imageProvider: _buildProvider(),
          onImageResolved: (info) {
            final w = info.image.width;
            final h = info.image.height;
            if (traceId != null) {
              final layoutW = _layoutWidth(context, constraints);
              final aspect = w > 0 && h > 0 ? w / h : _fallbackAspectRatio;
              final layoutH = (layoutW / aspect).ceilToDouble();
              Log.i(
                'Reader first frame',
                'trace=$traceId idx=${imageIndex ?? '-'} '
                'size=${w}x$h layout=${layoutW.toStringAsFixed(1)}x'
                '${layoutH.toStringAsFixed(1)} '
                'cache=${ReaderDiagnostics.cacheKeySummary(cacheKey ?? url)}',
              );
            }
            onImageSizeChanged?.call(w, h);
          },
          builder: (context, status) {
            final frame = status.imageInfo;
            if (frame != null) {
              // Direct paint of the already-decoded ui.Image — no second resolve.
              // Always pin width/height so vertical list items cannot paint at 0×0.
              return _sizedFrame(
                context,
                constraints,
                frame,
                pixelW: frame.image.width,
                pixelH: frame.image.height,
              );
            }
            if (status.isExhausted) {
              final detail = _friendlyError(status.error);
              return _placeholder(
                context,
                constraints,
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
                      Text(
                        '图片加载失败',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
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
              constraints,
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                color: const Color(0xFFECECEC),
                constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
                strokeCap: StrokeCap.round,
              ),
            );
          },
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
