/// 漫画单图加载显示（对齐  [ReaderImage] + 显式宽高）。
///
/// - [RetryForImage] 只负责订阅 / 重试 / 是否已解码
/// - 上屏一律用 Flutter [Image]（iOS Impeller 已知可用路径）
/// - 解码后按像素宽高比给出固定 [SizedBox]，避免竖直列表高度为 0
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../foundation/log.dart';
import '../utils/reader_image_provider.dart';
import 'retry_for_image.dart';

/// 漫画单图加载显示组件。
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

  @override
  State<ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<ReaderImage> {
  static const double _fallbackAspectRatio = 3 / 4;

  /// Pixel size of the last decoded frame (for layout height).
  int? _pixelW;
  int? _pixelH;

  bool get _isNetwork {
    final scheme = Uri.tryParse(widget.url)?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  ImageProvider _buildProvider() {
    if (_isNetwork) {
      return readerImageProvider(
        url: widget.url,
        cacheKey: widget.cacheKey ?? widget.url,
        fallbackUrls: widget.fallbackUrls,
        headers: widget.headers,
        bytesTransformer: widget.bytesTransformer,
        cacheWidth: widget.cacheWidth,
        traceId: widget.traceId,
        imageIndex: widget.imageIndex,
      );
    }
    return ResizeImage.resizeIfNeeded(
      widget.cacheWidth,
      null,
      FileImage(File(widget.url)),
    );
  }

  double _layoutWidth(BoxConstraints constraints) {
    if (constraints.hasBoundedWidth &&
        constraints.maxWidth.isFinite &&
        constraints.maxWidth > 0) {
      return constraints.maxWidth;
    }
    final mq = MediaQuery.sizeOf(context).width;
    return mq > 0 ? mq : 390;
  }

  double _layoutHeight(double width) {
    final w = _pixelW;
    final h = _pixelH;
    if (w != null && h != null && w > 0 && h > 0) {
      return (width * h / w).ceilToDouble();
    }
    return width / _fallbackAspectRatio;
  }

  Widget _box({
    required double width,
    required double height,
    required Widget child,
    Color color = const Color(0xFF2A2A2A),
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: color,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = _buildProvider();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _layoutWidth(constraints);
        final height = _layoutHeight(width);

        return RetryForImage(
          fadeDuration: Duration.zero,
          imageProvider: provider,
          onImageResolved: (info) {
            final w = info.image.width;
            final h = info.image.height;
            if (mounted) {
              setState(() {
                _pixelW = w;
                _pixelH = h;
              });
            }
            final layoutH = (width * h / (w > 0 ? w : 1)).ceilToDouble();
            if (widget.traceId != null) {
              Log.i(
                'Reader first frame',
                'trace=${widget.traceId} idx=${widget.imageIndex ?? '-'} '
                'size=${w}x$h layout=${width.toStringAsFixed(1)}x'
                '${layoutH.toStringAsFixed(1)} '
                'cache=${ReaderDiagnostics.cacheKeySummary(widget.cacheKey ?? widget.url)}',
              );
            }
            widget.onImageSizeChanged?.call(w, h);
          },
          builder: (context, status) {
            if (status.isLoaded) {
              //  path: paint with Image(provider). Explicit size for list.
              return _box(
                width: width,
                height: height,
                color: const Color(0xFF1A1A1A),
                child: Image(
                  image: status.provider,
                  width: width,
                  height: height,
                  fit: widget.fit,
                  alignment: widget.alignment,
                  filterQuality: widget.filterQuality,
                  gaplessPlayback: true,
                ),
              );
            }

            if (status.isExhausted) {
              final detail = _friendlyError(status.error);
              return _box(
                width: width,
                height: height,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.broken_image_outlined,
                          size: 40,
                          color: Color(0xFFECECEC),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '图片加载失败',
                          style: TextStyle(color: Color(0xFFECECEC)),
                        ),
                        if (detail != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            detail,
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFBDBDBD),
                              fontSize: 12,
                            ),
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
                ),
              );
            }

            double? progress;
            final chunk = status.chunk;
            if (chunk != null) {
              final total = chunk.expectedTotalBytes;
              final loaded = chunk.cumulativeBytesLoaded;
              if (total != null && total > 0) {
                progress = (loaded / total).clamp(0.0, 1.0);
              }
            }
            return _box(
              width: width,
              height: height,
              child: Center(
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  color: const Color(0xFFECECEC),
                  constraints: const BoxConstraints(
                    maxWidth: 28,
                    maxHeight: 28,
                  ),
                  strokeCap: StrokeCap.round,
                ),
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
