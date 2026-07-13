/// 漫画卡片网格通用组件。
///
/// 统一封装"列表/首页/搜索结果/收藏/排行"等页的网格渲染：
/// - 自动计算单元宽度传给 [ComicCard.poster]
/// - 下拉刷新 + 上拉加载更多（功能集成时接 ComicSource 分页契约）
/// - 三态切换：loading 显示 [LoadingGrid]，empty 显示 [EmptyState]
///
/// 功能集成说明：
///   传入 `loadPage: (int page) => Future<Res<List<BaseComic>>>`，
///   内部维护页码与累计结果，下拉刷新 reset page=1。
///   真实分页由各源的 ComicListBuilder / CategoryComicsLoader 提供。
library comic_grid;

import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';
import 'comic_card.dart';
import 'empty_state.dart';
import 'loading_grid.dart';
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
    this.crossAxisCount = 3,
    this.childAspectRatio = 0.55,
    this.emptyTitle = '暂无内容',
  });

  final List<ComicGridItem> items;
  final bool loading;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final void Function(ComicGridItem item)? onItemTap;
  final Map<String, dynamic>? coverHeaders;
  final int crossAxisCount;
  final double childAspectRatio;
  final String emptyTitle;

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
    final cellWidth = (MediaQuery.of(context).size.width -
            AppSpacing.md * 2 -
            AppSpacing.sm * (widget.crossAxisCount - 1)) /
        widget.crossAxisCount;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollEndNotification &&
            n.metrics.pixels >= n.metrics.maxScrollExtent * 0.9 &&
            widget.hasMore &&
            widget.onLoadMore != null &&
            !widget.loading) {
          widget.onLoadMore!();
        }
        return false;
      },
      child: RefreshIndicator(
        color: const Color(0xFFFF7BA9),
        onRefresh: () async => widget.onRefresh?.call(),
        child: GridView.builder(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: widget.crossAxisCount,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: widget.childAspectRatio,
          ),
          itemCount: widget.items.length + (widget.hasMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= widget.items.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8A8298)),
                ),
              );
            }
            final item = widget.items[i];
            return ComicCard.poster(
              title: item.title,
              coverUrl: item.coverUrl,
              subtitle: item.subtitle,
              rating: item.rating,
              width: cellWidth,
              headers: widget.coverHeaders,
              sourceKey: item.sourceKey,
              onTap: widget.onItemTap == null ? null : () => widget.onItemTap!(item),
            );
          },
        ),
      ),
    );
  }
}

/// 网格项视图数据（与 BaseComic 解耦，便于 mock 与多源统一）。
/// 功能集成时由 BaseComic 映射：id/title/cover/subTitle/tags → 本结构。
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
