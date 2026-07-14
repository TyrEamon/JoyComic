/// 漫画详情页主框架。
///
/// 结构：[CustomScrollView] 沉浸头 Sliver + 4 区块 SliverList，
/// 底部常驻 [StickyActionBar]，顶部常驻 [DetailAppBar]。
///
/// 数据由 [DetailViewModel] 驱动（Provider 注入），支持
/// loading / error / success 三态，error 态提供重试。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/download_manager.dart';
import '../../foundation/download_task.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../reader/state/comic_state.dart';
import 'detail_view_model.dart';
import 'widgets/chapter_grid.dart';
import 'widgets/comment_section.dart';
import 'widgets/detail_app_bar.dart';
import 'widgets/hero_header.dart';
import 'widgets/recommendation_carousel.dart';
import 'widgets/sticky_action_bar.dart';
import 'widgets/synopsis_block.dart';

class DetailPage extends StatelessWidget {
  const DetailPage({
    super.key,
    required this.sourceKey,
    required this.comicId,
    this.demoData,
  });

  final String sourceKey;
  final String comicId;

  /// 演示数据旁路：非 null 时详情页跳过网络加载，直接用此数据渲染。
  final ComicInfoData? demoData;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DetailViewModel(
        sourceKey: sourceKey,
        comicId: comicId,
        demoData: demoData,
      )..load(),
      child: const _DetailScaffold(),
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DetailViewModel>();
    return Scaffold(
      backgroundColor: AppColors.background,
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
          // 顶部导航栏常驻。
          DetailAppBar(
            scrolledUnder: false,
            onBack: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: const Center(
        child: CircularProgressIndicator(
          color: AppColors.brandPink,
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
      color: AppColors.background,
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: AppColors.textLow,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMedium),
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

class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DetailViewModel>();
    final info = vm.data!.info;
    final palette = vm.data!.palette;

    // 章节映射 → 有序列表 + chapter entry 列表。
    // 注意 ComicInfoData.chapters 的 key 是各源章节标识（禁漫=chapterId，
    // 哔咔=order.toString()），与 ReaderChapter.fromChapterMap 的顺序一致。
    final chapters = ReaderChapter.fromChapterMap(info.chapters);
    final chapterEntries = <ChapterEntry>[];
    var idx = 0;
    info.chapters?.forEach((id, name) {
      chapterEntries.add(
        ChapterEntry(
          id: id,
          name: name.isEmpty ? '第${idx + 1}话' : name,
          cover: info.thumbnails?.elementAtOrNull(idx),
        ),
      );
      idx++;
    });
    final latestName = chapterEntries.isNotEmpty
        ? chapterEntries.last.name
        : null;

    // 作者：tags 中"作者"/"author"键首个值；禁漫可能多作者，取第一个展示。
    final author = (info.tags['作者'] ?? info.tags['author'])?.firstOrNull;

    // 相关推荐：从 ComicInfoData.suggestions 映射。
    final List<RecommendItem> recommends =
        info.suggestions
            ?.map(
              (b) => RecommendItem(
                id: b.id,
                title: b.title,
                cover: b.cover,
                author: b.subTitle,
                sourceKey: vm.sourceKey,
              ),
            )
            .toList() ??
        const [];

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            // 1. 沉浸头。
            HeroHeader(
              title: info.title,
              subTitle: info.subTitle,
              backgroundCover: info.cover,
              frontCover: info.cover,
              author: author,
              tags: _flattenTags(info.tags),
              hotValue: _hotValue(info.tags),
              favoriteCount: _favCount(info.tags),
              rating: _rating(info.tags),
              ratingCount: _ratingCount(info.tags),
              palette: palette,
              coverHeaders: vm.coverHeaders,
            ),
            // 2. 内容主体。
            SliverPadding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  SynopsisBlock(text: info.description, palette: palette),
                  const SizedBox(height: AppSpacing.sectionGap),
                  ChapterGrid(
                    chapters: chapterEntries,
                    latestChapterName: latestName,
                    onSelect: (e) => _openReader(context, vm, e, chapters),
                    onShowAll: () =>
                        _showDownloadSheet(context, vm, chapterEntries),
                    palette: palette,
                    coverHeaders: vm.coverHeaders,
                  ),
                  const SizedBox(height: AppSpacing.sectionGap),
                  CommentSection(
                    total: vm.commentTotal,
                    comments: vm.comments
                        .map(
                          (c) => CommentView(
                            userName: c.userName,
                            avatar: c.avatar,
                            content: c.content,
                            time: c.time,
                            likes: c.replyCount,
                          ),
                        )
                        .toList(),
                    onShowAll: () {},
                  ),
                  const SizedBox(height: AppSpacing.sectionGap),
                  RecommendationCarousel(
                    items: recommends,
                    coverHeaders: vm.coverHeaders,
                    palette: palette,
                    onRefresh: () {},
                    onSelect: (i) => context.push(
                      '/detail/${i.sourceKey ?? vm.sourceKey}/${i.id}',
                    ),
                  ),
                  // 底栏留白，避免悬浮底栏遮挡末项。
                  const SizedBox(height: 96),
                ]),
              ),
            ),
          ],
        ),
        // 4. 悬浮底栏。
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: StickyActionBar(
            isFavorite: vm.isFavorite,
            readHint: latestName != null ? '最新 $latestName' : '',
            palette: palette,
            onFavorite: vm.toggleFavorite,
            onRead: () => _openReader(context, vm, null, chapters),
          ),
        ),
      ],
    );
  }

  void _showDownloadSheet(
    BuildContext context,
    DetailViewModel vm,
    List<ChapterEntry> chapters,
  ) {
    final manager = DownloadManager.instance;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
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
                        title: Text(chapter.name),
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
                              ? AppColors.success
                              : AppColors.brandPink,
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
    ChapterEntry chapter,
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
    ChapterEntry chapter,
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
        chapterTitle: chapter.name,
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
    ChapterEntry? entry,
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

  List<String> _flattenTags(Map<String, List<String>> tags) {
    final exclude = {'作者', 'author', '热度', '评分', '评价人数', '收藏'};
    final out = <String>[];
    tags.forEach((k, v) {
      if (exclude.contains(k)) return;
      out.addAll(v.take(2));
    });
    return out.take(4).toList();
  }

  String? _hotValue(Map<String, List<String>> tags) =>
      (tags['热度'] ?? tags['hot'])?.firstOrNull;
  String? _favCount(Map<String, List<String>> tags) =>
      (tags['收藏'] ?? tags['favorite'])?.firstOrNull;

  double _rating(Map<String, List<String>> tags) {
    final v = (tags['评分'] ?? tags['rating'])?.firstOrNull;
    return double.tryParse(v ?? '') ?? 8.0;
  }

  String _ratingCount(Map<String, List<String>> tags) =>
      (tags['评价人数'] ?? tags['ratingCount'])?.firstOrNull ?? '0';
}
