import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme_context.dart';

class ChapterThumbnail extends StatefulWidget {
  const ChapterThumbnail({
    super.key,
    required this.load,
    this.headers,
    this.fit = BoxFit.cover,
  });

  final Future<String?> Function() load;
  final Map<String, dynamic>? headers;
  final BoxFit fit;

  @override
  State<ChapterThumbnail> createState() => _ChapterThumbnailState();
}

class _ChapterThumbnailState extends State<ChapterThumbnail> {
  late Future<String?> _future;

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
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null || url.isEmpty) return const _Placeholder();
        return CachedNetworkImage(
          imageUrl: url,
          httpHeaders: widget.headers?.cast<String, String>(),
          fit: widget.fit,
          placeholder: (_, __) => const _Placeholder(),
          errorBuilder: (_, __, ___) => const _Placeholder(),
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
