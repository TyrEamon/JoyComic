/// 漫画详情页主框架。
///
/// 结构：[CustomScrollView] 沉浸头 Sliver + 4 区块 SliverList，
/// 底部常驻 [StickyActionBar]，顶部常驻 [DetailAppBar]。
///
/// 数据由 [DetailViewModel] 驱动（Provider 注入），支持
/// loading / error / success 三态，error 态提供重试。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/download_manager.dart';
import '../../foundation/download_task.dart';
import '../../theme/app_spacing.dart';
import '../reader/state/comic_state.dart';
import 'detail_navigation.dart';
import 'detail_view_model.dart';
import 'widgets/chapter_grid.dart';
import 'widgets/comment_composer.dart';
import 'widgets/comment_section.dart';
import 'widgets/detail_app_bar.dart';
import 'widgets/detail_metadata.dart';
import 'widgets/detail_tab_bar.dart';
import 'widgets/hero_header.dart';
import 'widgets/recommendation_carousel.dart';
import 'widgets/sticky_action_bar.dart';
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

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DetailViewModel>();
    final ready = vm.state == DetailLoadState.success && vm.data != null;
    return Scaffold(
      backgroundColor: context.pageBackground,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          switch (vm.state) {
            DetailLoadState.loading => const _Loading(),
            DetailLoadState.error => _Error(
              message: vm.error ?? '加载失败',
              onRetry: vm.reload,
            ),
            DetailLoadState.idle => const SizedBox.shrink(),
            DetailLoadState.success => const _Content(),
          },
          DetailAppBar(
            scrolledUnder: false,
            onBack: () => Navigator.of(context).maybePop(),
            onShare: ready ? () => _share(vm) : null,
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
              leading: const Icon(Icons.download_rounded),
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

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.pageBackground,
      child: Center(
        child: CircularProgressIndicator(
          color: context.colorScheme.primary,
          strokeWidth: 2.5,
        ),
      ),
    );
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
  DetailTab _selectedTab = DetailTab.chapters;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DetailViewModel>();
    final info = vm.data!.info;
    final readerChapters = ReaderChapter.fromComicChapters(vm.chapters);
    final latestName = vm.chapters.isEmpty ? null : vm.chapters.last.title;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final bodyBottomPadding =
        StickyActionBar.contentHeight + bottomInset + AppSpacing.md;

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

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            HeroHeader(
              title: info.title,
              subTitle: vm.author,
              backgroundCover: info.cover,
              frontCover: info.cover,
              rating: vm.rating,
              coverHeaders: vm.coverHeaders,
            ),
            SliverPadding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  DetailMetadata(
                    authors: info.authors,
                    categories: info.categories,
                    labels: info.labels,
                    rating: vm.rating,
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
                  const SizedBox(height: AppSpacing.md),
                ]),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: DetailTabBarDelegate(
                selected: _selectedTab,
                commentTotal: vm.commentTotal,
                onChanged: (tab) => _selectTab(vm, tab),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
            if (_selectedTab == DetailTab.chapters) ...[
              SliverToBoxAdapter(
                child: ChapterGrid(
                  chapters: vm.chapters,
                  onSelect: (chapter) =>
                      _openReader(context, vm, chapter, readerChapters),
                  loadThumbnail: vm.loadChapterThumbnail,
                  onDownload: (chapter) =>
                      _enqueueChapter(context, vm, chapter),
                  onDownloadAll: () =>
                      _showDownloadSheet(context, vm, vm.chapters),
                  coverHeaders: vm.coverHeaders,
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.sectionGap),
              ),
              SliverToBoxAdapter(
                child: RecommendationCarousel(
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
              ),
            ] else ...[
              SliverToBoxAdapter(
                child: CommentSection(
                  comments: vm.comments,
                  loading: vm.commentsLoading,
                  hasMore: vm.hasMoreComments,
                  onReply: vm.beginReply,
                  onLoadMore: vm.loadMoreComments,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.md)),
              SliverToBoxAdapter(
                child: CommentComposer(
                  replyTarget: vm.replyTarget,
                  sending: vm.commentSending,
                  error: vm.commentSendError,
                  onCancelReply: vm.cancelReply,
                  onSend: vm.sendComment,
                ),
              ),
            ],
            SliverToBoxAdapter(child: SizedBox(height: bodyBottomPadding)),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: StickyActionBar(
            isFavorite: vm.isFavorite,
            readHint: latestName == null ? '' : '最新 $latestName',
            onFavorite: vm.toggleFavorite,
            onRead: () => _openReader(context, vm, null, readerChapters),
          ),
        ),
      ],
    );
  }

  void _selectTab(DetailViewModel vm, DetailTab tab) {
    if (_selectedTab == tab) return;
    setState(() => _selectedTab = tab);
    if (tab == DetailTab.comments) unawaited(vm.activateComments());
  }

  void _showDownloadSheet(
    BuildContext context,
    DetailViewModel vm,
    List<ComicChapter> chapters,
  ) {
    final manager = DownloadManager.instance;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surfaceColor,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: Column(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.download_for_offline_rounded),
                    SizedBox(width: AppSpacing.sm),
                    Text(
                      '选择下载章节',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListenableBuilder(
                  listenable: manager,
                  builder: (context, _) => ListView.builder(
                    itemCount: chapters.length,
                    itemBuilder: (context, index) {
                      final chapter = chapters[index];
                      final task = manager.findTask(
                        vm.sourceKey,
                        vm.data!.info.comicId,
                        chapter.id,
                      );
                      return ListTile(
                        title: Text(chapter.title),
                        subtitle: task == null
                            ? const Text('未加入队列')
                            : Text(_downloadStatusLabel(task)),
                        leading: Icon(
                          task?.status == DownloadStatus.completed
                              ? Icons.check_circle_rounded
                              : task == null
                              ? Icons.download_outlined
                              : Icons.downloading_rounded,
                          color: task?.status == DownloadStatus.completed
                              ? context.successColor
                              : context.colorScheme.primary,
                        ),
                        trailing: _downloadAction(context, vm, chapter, task),
                        onTap: task?.status == DownloadStatus.completed
                            ? () => context.push(
                                '/reader',
                                extra: ComicState.fromDownload(task!),
                              )
                            : null,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _downloadAction(
    BuildContext context,
    DetailViewModel vm,
    ComicChapter chapter,
    DownloadTask? task,
  ) {
    if (task == null) {
      return IconButton(
        tooltip: '加入下载',
        icon: const Icon(Icons.add_circle_outline_rounded),
        onPressed: () => _enqueueChapter(context, vm, chapter),
      );
    }
    return switch (task.status) {
      DownloadStatus.downloading => IconButton(
        tooltip: '暂停',
        icon: const Icon(Icons.pause_rounded),
        onPressed: () => DownloadManager.instance.pause(task.id!),
      ),
      DownloadStatus.paused || DownloadStatus.failed => IconButton(
        tooltip: task.status == DownloadStatus.failed ? '重试' : '继续',
        icon: Icon(
          task.status == DownloadStatus.failed
              ? Icons.refresh_rounded
              : Icons.play_arrow_rounded,
        ),
        onPressed: () => DownloadManager.instance.resume(task.id!),
      ),
      DownloadStatus.completed => const Icon(Icons.menu_book_rounded),
      DownloadStatus.pending => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    };
  }

  Future<void> _enqueueChapter(
    BuildContext context,
    DetailViewModel vm,
    ComicChapter chapter,
  ) async {
    final source = ComicSource.find(vm.sourceKey);
    if (source?.loadComicPages == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前漫画源不可用或不支持章节下载')));
      return;
    }
    try {
      await DownloadManager.instance.enqueue(
        sourceKey: vm.sourceKey,
        comicId: vm.data!.info.comicId,
        chapterId: chapter.id,
        title: vm.data!.info.title,
        coverUrl: vm.data!.info.cover,
        chapterTitle: chapter.title,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加入下载失败：$error')));
    }
  }

  String _downloadStatusLabel(DownloadTask task) {
    final pages = '${task.completedCount}/${task.pageUrls.length} 页';
    return switch (task.status) {
      DownloadStatus.pending => '等待下载',
      DownloadStatus.downloading => '下载中 · $pages',
      DownloadStatus.paused => '已暂停 · $pages',
      DownloadStatus.completed => '已完成 · 点击离线阅读',
      DownloadStatus.failed => '失败 · ${task.errorMessage ?? '可重试'}',
    };
  }

  void _openReader(
    BuildContext context,
    DetailViewModel vm,
    ComicChapter? entry,
    List<ReaderChapter> chapters,
  ) {
    if (chapters.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无章节')));
      return;
    }
    ReaderChapter start;
    if (entry == null) {
      start = chapters.last;
    } else {
      start = chapters.firstWhere(
        (c) => c.id == entry.id,
        orElse: () => chapters.last,
      );
    }
    context.push(
      '/reader',
      extra: ComicState(
        id: vm.data!.info.comicId,
        title: vm.data!.info.title,
        coverUrl: vm.data!.info.cover,
        author: vm.author,
        chapters: chapters,
        // 章节标识（禁漫 chapterId / 哔咔 order）作为 ep 传给 loadComicPages。
        chapter: start,
        pageNo: 0,
        sourceKey: vm.sourceKey,
      ),
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
