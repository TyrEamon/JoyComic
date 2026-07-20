import 'package:flutter/material.dart';

import '../../../theme/app_theme_context.dart';
import '../../reader/utils/reader_image_provider.dart';
import '../../reader/utils/source_aware_image.dart';

class ChapterThumbnail extends StatefulWidget {
  const ChapterThumbnail({
    super.key,
    required this.load,
    this.fit = BoxFit.cover,
  });

  final Future<SourceAwareImageDescriptor?> Function() load;
  final BoxFit fit;

  @override
  State<ChapterThumbnail> createState() => _ChapterThumbnailState();
}

class _ChapterThumbnailState extends State<ChapterThumbnail> {
  late Future<SourceAwareImageDescriptor?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  void didUpdateWidget(covariant ChapterThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.load != widget.load) _future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SourceAwareImageDescriptor?>(
      future: _future,
      builder: (context, snapshot) {
        final descriptor = snapshot.data;
        if (descriptor == null || descriptor.url.isEmpty) {
          return const _Placeholder();
        }
        return Image(
          image: readerImageProvider(
            url: descriptor.url,
            cacheKey: descriptor.cacheKey,
            fallbackUrls: descriptor.fallbackUrls,
            headers: descriptor.headers,
            bytesTransformer: descriptor.bytesTransformer,
          ),
          fit: widget.fit,
          errorBuilder: (_, __, ___) => const _Placeholder(),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return const _Placeholder();
          },
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.elevatedSurfaceColor,
    child: Center(
      child: Icon(
        Icons.book_rounded,
        size: 22,
        color: context.disabledTextColor,
      ),
    ),
  );
}
