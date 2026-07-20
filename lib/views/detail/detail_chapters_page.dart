import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_theme_context.dart';
import 'detail_navigation.dart';
import 'detail_view_model.dart';
import 'widgets/chapter_download_sheet.dart';
import 'widgets/chapter_grid.dart';

class DetailChaptersPage extends StatelessWidget {
  const DetailChaptersPage({
    super.key,
    required this.sourceKey,
    required this.comicId,
  });

  final String sourceKey;
  final String comicId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) =>
          DetailViewModel(sourceKey: sourceKey, comicId: comicId)..load(),
      child: const _DetailChaptersScaffold(),
    );
  }
}

class _DetailChaptersScaffold extends StatelessWidget {
  const _DetailChaptersScaffold();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DetailViewModel>();
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(title: const Text('全部章节')),
      body: switch (vm.state) {
        DetailLoadState.loading || DetailLoadState.idle => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        DetailLoadState.error => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  vm.error ?? '章节加载失败',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.secondaryTextColor),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: vm.reload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        DetailLoadState.success => ListView(
          padding: const EdgeInsets.only(
            top: AppSpacing.md,
            bottom: AppSpacing.xl,
          ),
          children: [
            ChapterGrid(
              chapters: vm.chapters,
              loadThumbnail: vm.loadChapterThumbnail,
              coverHeaders: vm.coverHeaders,
              onSelect: (chapter) => openDetailReader(context, vm, chapter),
              onDownload: (chapter) => enqueueDetailChapter(
                context,
                viewModel: vm,
                chapter: chapter,
              ),
              onDownloadAll: vm.chapters.isEmpty
                  ? null
                  : () => showChapterDownloadSheet(
                      context,
                      viewModel: vm,
                      chapters: vm.chapters,
                    ),
            ),
          ],
        ),
      },
    );
  }
}
