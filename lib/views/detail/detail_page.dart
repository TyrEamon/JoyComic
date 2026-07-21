/// 漫画详情页主框架。
///
/// 结构：沉浸头图 + 元数据/简介/最近章节/内联操作/评论预览/推荐的单列信息流。
/// 数据由 [DetailViewModel] 驱动（Provider 注入）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../comic_source/comic_source.dart';
import '../../theme/app_spacing.dart';
import 'detail_navigation.dart';
import 'detail_view_model.dart';
import 'widgets/comment_preview.dart';
import 'widgets/detail_actions.dart';
import 'widgets/detail_app_bar.dart';
import 'widgets/detail_loading_skeleton.dart';
import 'widgets/detail_metadata.dart';
import 'widgets/hero_header.dart';
import 'widgets/recent_chapter_strip.dart';
import 'widgets/recommendation_carousel.dart';
import 'widgets/synopsis_block.dart';

class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.sourceKey, required this.comicId});

  final String sourceKey;
  final String comicId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          DetailViewModel(sourceKey: sourceKey, comicId: comicId)..load(),
      child: const _DetailScaffold(),
    );
  }
}

class _DetailScaffold extends StatefulWidget {
  const _DetailScaffold();

  @override
  State<_DetailScaffold> createState() => _DetailScaffoldState();
}

class _DetailScaffoldState extends State<_DetailScaffold> {
  bool _scrolledUnder = false;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DetailViewModel>();
    final ready = vm.state == DetailLoadState.success && vm.data != null;
    return Scaffold(
      backgroundColor: context.pageBackground,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              final next = notification.metrics.pixels > 260;
              if (next != _scrolledUnder) {
                setState(() => _scrolledUnder = next);
              }
              return false;
            },
            child: switch (vm.state) {
              DetailLoadState.loading => const DetailLoadingSkeleton(),
              DetailLoadState.error => _Error(
                message: vm.error ?? '加载失败',
                onRetry: vm.reload,
              ),
              DetailLoadState.idle => const SizedBox.shrink(),
              DetailLoadState.success => const _Content(),
            },
          ),
          DetailAppBar(
            title: ready ? vm.data!.info.title : null,
            scrolledUnder: _scrolledUnder,
            onBack: () => Navigator.of(context).maybePop(),
            onMore: ready ? () => _showMore(context, vm) : null,
          ),
        ],
      ),
    );
  }

  Future<void> _share(DetailViewModel vm) async {
    final info = vm.data!.info;
    final idLabel = vm.sourceKey == 'jm' ? 'JM${info.comicId}' : info.comicId;
    final author = vm.author.isEmpty ? '未知作者' : vm.author;
    await Share.share(
      '${info.title}\n作者：$author\n来源：${vm.sourceKey}\nID：$idLabel',
      subject: info.title,
    );
  }

  void _showMore(BuildContext context, DetailViewModel vm) {
    final info = vm.data!.info;
    final source = ComicSource.find(vm.sourceKey);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surfaceColor,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: const Text('分享'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _share(vm);
              },
            ),
            ListTile(
              leading: const Icon(Icons.title_rounded),
              title: const Text('复制标题'),
              onTap: () => _copyAndClose(sheetContext, info.title, '已复制标题'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(vm.sourceKey == 'jm' ? '复制车号' : '复制 ID'),
              onTap: () => _copyAndClose(
                sheetContext,
                info.comicId,
                vm.sourceKey == 'jm' ? '已复制车号 JM${info.comicId}' : '已复制 ID',
              ),
            ),
            if (info.authors.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.person_search_rounded),
                title: const Text('搜索作者'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  openDetailKeywordSearch(
                    context,
                    sourceKey: vm.sourceKey,
                    keyword: info.authors.first,
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('下载管理'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/download');
              },
            ),
            if (source != null && Uri.tryParse(source.url)?.hasScheme == true)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('打开源主页'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await launchUrl(
                    Uri.parse(source.url),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyAndClose(
    BuildContext context,
    String value,
    String message,
  ) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.pageBackground,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: context.tertiaryTextColor,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.secondaryTextColor),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

List<T> rotateRecommendationItems<T>(
  List<T> items,
  int offset, {
  int batchSize = 4,
}) {
  if (items.isEmpty || batchSize <= 0) return <T>[];
  final start = offset % items.length;
  final count = batchSize.clamp(0, items.length);
  return List<T>.generate(
    count,
    (index) => items[(start + index) % items.length],
  );
}

class _Content extends StatefulWidget {
  const _Content();

  @override
  State<_Content> createState() => _ContentState();
}

class _ContentState extends State<_Content> {
  int _recommendationOffset = 0;
  bool _requestedCommentPreview = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requestedCommentPreview) {
      _requestedCommentPreview = true;
      unawaited(context.read<DetailViewModel>().activateComments());
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DetailViewModel>();
    final info = vm.data!.info;

    final recommends =
        info.suggestions
            ?.map(
              (comic) => RecommendItem(
                id: comic.id,
                title: comic.title,
                cover: comic.cover,
                author: comic.subTitle,
                sourceKey: vm.sourceKey,
              ),
            )
            .toList() ??
        const <RecommendItem>[];
    final visibleRecommends = rotateRecommendationItems(
      recommends,
      _recommendationOffset,
    );
    final tags = <String>[
      ...info.categories,
      ...info.labels,
    ].take(4).toList(growable: false);

    return CustomScrollView(
      key: PageStorageKey<String>('detail-${vm.sourceKey}-${info.comicId}'),
      slivers: <Widget>[
        HeroHeader(
          title: info.title,
          subTitle: vm.author,
          backgroundCover: info.cover,
          frontCover: info.cover,
          rating: vm.rating,
          tags: tags,
          coverHeaders: vm.coverHeaders,
        ),
        SliverToBoxAdapter(
          child: _constrainedDetailContent(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Metadata starts after the floating cover bottom; hero stack
                // ends at coverBottom so only this design spacing remains.
                const SizedBox(height: AppSpacing.md),
                DetailMetadata(
                  authors: info.authors,
                  categories: info.categories,
                  labels: info.labels,
                  viewCount: info.viewCount,
                  likeCount: info.likeCount,
                  commentCount: info.commentCount,
                  chapterCount: vm.chapters.length,
                  jmNumber: vm.sourceKey == 'jm' ? info.comicId : null,
                  onAuthorTap: (value) => openDetailKeywordSearch(
                    context,
                    sourceKey: vm.sourceKey,
                    keyword: value,
                  ),
                  onCategoryTap: (value) => openDetailCategory(
                    context,
                    sourceKey: vm.sourceKey,
                    category: value,
                  ),
                  onLabelTap: (value) => openDetailKeywordSearch(
                    context,
                    sourceKey: vm.sourceKey,
                    keyword: value,
                  ),
                  onJmNumberTap: vm.sourceKey == 'jm'
                      ? () => _copyJmNumber(context, info.comicId)
                      : null,
                ),
                const SizedBox(height: AppSpacing.sectionGap),
                SynopsisBlock(text: info.description),
                const SizedBox(height: AppSpacing.sectionGap),
                RecentChapterStrip(
                  chapters: vm.chapters,
                  loadThumbnail: vm.loadChapterThumbnailDescriptor,
                  onSelect: (chapter) => openDetailReader(context, vm, chapter),
                  onShowAll: () => openDetailChapters(
                    context,
                    sourceKey: vm.sourceKey,
                    comicId: info.comicId,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DetailActions(
                  isFavorite: vm.isFavorite,
                  canRead: vm.chapters.isNotEmpty,
                  readLabel: vm.readActionLabel,
                  onFavorite: vm.toggleFavorite,
                  onRead: () => openDetailReader(context, vm, null),
                ),
                const SizedBox(height: AppSpacing.sectionGap),
                CommentPreview(
                  comments: vm.comments,
                  loading: vm.commentsLoading,
                  canOpenAll: vm.canLoadComments,
                  onOpenAll: () => openDetailComments(
                    context,
                    sourceKey: vm.sourceKey,
                    comicId: info.comicId,
                  ),
                ),
                if (visibleRecommends.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sectionGap),
                  RecommendationCarousel(
                    items: visibleRecommends,
                    coverHeaders: vm.coverHeaders,
                    onRefresh: recommends.length > 1
                        ? () => setState(() {
                            _recommendationOffset =
                                (_recommendationOffset + 4) % recommends.length;
                          })
                        : null,
                    onSelect: (item) => context.push(
                      '/detail/${item.sourceKey ?? vm.sourceKey}/${item.id}',
                    ),
                  ),
                ],
                // System bottom inset + design spacing; no fixed action bar.
                SizedBox(
                  key: const ValueKey('detail-bottom-safe-padding'),
                  height:
                      MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copyJmNumber(BuildContext context, String comicId) async {
    await Clipboard.setData(ClipboardData(text: comicId));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制车号 JM$comicId')));
  }
}

Widget _constrainedDetailContent(BuildContext context, Widget child) {
  return LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: constraints.maxWidth >= 1100 ? 1040 : double.infinity,
        ),
        child: child,
      ),
    ),
  );
}
