/// Reusable comic grid with refresh and guarded load-more hooks.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';
import '../source_content_models.dart';
import 'comic_card.dart';
import 'empty_state.dart';
import 'loading_grid.dart';

typedef ComicCoverHeadersBuilder =
    Map<String, dynamic>? Function(ComicGridItem item);

class ComicGrid extends StatefulWidget {
  const ComicGrid({
    super.key,
    required this.items,
    this.loading = false,
    this.onRefresh,
    this.onLoadMore,
    this.hasMore = false,
    this.onItemTap,
    this.coverHeaders,
    this.coverHeadersBuilder,
    this.crossAxisCount = 3,
    this.childAspectRatio = 0.55,
    this.emptyTitle = '暂无内容',
    this.shrinkWrap = false,
    this.physics,
  });

  final List<ComicGridItem> items;
  final bool loading;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final void Function(ComicGridItem item)? onItemTap;
  final Map<String, dynamic>? coverHeaders;
  final ComicCoverHeadersBuilder? coverHeadersBuilder;
  final int crossAxisCount;
  final double childAspectRatio;
  final String emptyTitle;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  State<ComicGrid> createState() => _ComicGridState();
}

class _ComicGridState extends State<ComicGrid> {
  @override
  Widget build(BuildContext context) {
    if (widget.loading && widget.items.isEmpty) {
      return LoadingGrid(
        crossAxisCount: widget.crossAxisCount,
        childAspectRatio: widget.childAspectRatio,
      );
    }
    if (widget.items.isEmpty) {
      return EmptyState(title: widget.emptyTitle);
    }

    final cellWidth =
        (MediaQuery.of(context).size.width -
            AppSpacing.md * 2 -
            AppSpacing.sm * (widget.crossAxisCount - 1)) /
        widget.crossAxisCount;
    Widget grid = GridView.builder(
      shrinkWrap: widget.shrinkWrap,
      physics:
          widget.physics ??
          (widget.onRefresh == null
              ? null
              : const AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.crossAxisCount,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: widget.childAspectRatio,
      ),
      itemCount: widget.items.length + (widget.loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= widget.items.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF8A8298),
              ),
            ),
          );
        }
        final item = widget.items[index];
        return ComicCard.poster(
          title: item.title,
          coverUrl: item.coverUrl,
          subtitle: item.subtitle,
          rating: item.rating,
          width: cellWidth,
          headers:
              widget.coverHeadersBuilder?.call(item) ?? widget.coverHeaders,
          sourceKey: item.sourceKey,
          onTap: widget.onItemTap == null
              ? null
              : () => widget.onItemTap!(item),
        );
      },
    );

    final refresh = widget.onRefresh;
    if (refresh != null) {
      grid = RefreshIndicator(
        color: const Color(0xFFFF7BA9),
        onRefresh: refresh,
        child: grid,
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification &&
            shouldRequestNextPage(
              depth: notification.depth,
              scrollDelta: notification.scrollDelta ?? 0.0,
              pixels: notification.metrics.pixels,
              minScrollExtent: notification.metrics.minScrollExtent,
              maxScrollExtent: notification.metrics.maxScrollExtent,
              extentAfter: notification.metrics.extentAfter,
            ) &&
            widget.hasMore &&
            widget.onLoadMore != null &&
            !widget.loading) {
          widget.onLoadMore!();
        }
        return false;
      },
      child: grid,
    );
  }
}

class ComicGridItem {
  const ComicGridItem({
    required this.id,
    required this.title,
    this.coverUrl,
    this.subtitle,
    this.rating,
    this.sourceKey,
  });

  final String id;
  final String title;
  final String? coverUrl;
  final String? subtitle;
  final double? rating;
  final String? sourceKey;
}
