import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../reader_v2/reader_v2_runtime.dart';
import '../../reader_v2/widgets/reader_v2_page_image.dart';
import '../providers/reader_provider.dart' hide ReaderImage;
import '../utils/reader_image_provider.dart' show ReaderImageBytesTransformer;

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
  @override
  Widget build(BuildContext context) {
    final runtime = context.watch<ReaderV2Runtime>();
    final reader = context.watch<ReaderProvider>();
    final index =
        widget.imageIndex ??
        reader.images.indexWhere(
          (item) => item.cacheKey == (widget.cacheKey ?? widget.url),
        );
    final safeIndex = index < 0 ? 0 : index;
    final logicalAnchor = reader.pageNo.clamp(
      0,
      reader.pageCount == 0 ? 0 : reader.pageCount - 1,
    );
    final anchor = reader.readMode.isDoublePage
        ? logicalAnchor * 2
        : logicalAnchor;

    if (!runtime.shouldLoad(safeIndex, anchor)) {
      return const SizedBox(
        height: 300,
        child: ColoredBox(color: Colors.black),
      );
    }

    final page = runtime.pageFrom(
      index: safeIndex,
      url: widget.url,
      cacheKey: widget.cacheKey ?? widget.url,
      headers: widget.headers,
      fallbackUrls: widget.fallbackUrls,
      bytesTransformer: widget.bytesTransformer,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight =
            constraints.maxHeight.isFinite &&
            constraints.maxHeight > 0 &&
            constraints.maxHeight < 100000;
        return ReaderV2PageImage(
          page: page,
          session: runtime.session,
          scheduler: runtime.scheduler,
          priority: runtime.priorityFor(safeIndex, anchor),
          bytesLoader: runtime.bytesLoader,
          height: boundedHeight ? constraints.maxHeight : null,
          fit: widget.fit,
        );
      },
    );
  }
}
