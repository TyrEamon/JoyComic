/// Chapter download queue sheet and single-chapter enqueue helpers.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../comic_source/comic_source.dart';
import '../../../foundation/download_manager.dart';
import '../../../foundation/download_task.dart';
import '../../../theme/app_spacing.dart';
import '../../reader/state/comic_state.dart';
import '../detail_view_model.dart';

Future<void> showChapterDownloadSheet(
  BuildContext context, {
  required DetailViewModel viewModel,
  required List<ComicChapter> chapters,
}) async {
  final manager = DownloadManager.instance;
  await showModalBottomSheet<void>(
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
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
                      viewModel.sourceKey,
                      viewModel.data!.info.comicId,
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
                      trailing: _DownloadAction(
                        viewModel: viewModel,
                        chapter: chapter,
                        task: task,
                      ),
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

Future<void> enqueueDetailChapter(
  BuildContext context, {
  required DetailViewModel viewModel,
  required ComicChapter chapter,
}) async {
  final source = ComicSource.find(viewModel.sourceKey);
  if (source?.loadComicPages == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('当前漫画源不可用或不支持章节下载')));
    return;
  }
  try {
    await DownloadManager.instance.enqueue(
      sourceKey: viewModel.sourceKey,
      comicId: viewModel.data!.info.comicId,
      chapterId: chapter.id,
      title: viewModel.data!.info.title,
      coverUrl: viewModel.data!.info.cover,
      chapterTitle: chapter.title,
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('加入下载失败：$error')));
  }
}

class _DownloadAction extends StatelessWidget {
  const _DownloadAction({
    required this.viewModel,
    required this.chapter,
    required this.task,
  });

  final DetailViewModel viewModel;
  final ComicChapter chapter;
  final DownloadTask? task;

  @override
  Widget build(BuildContext context) {
    if (task == null) {
      return IconButton(
        tooltip: '加入下载',
        icon: const Icon(Icons.add_circle_outline_rounded),
        onPressed: () => enqueueDetailChapter(
          context,
          viewModel: viewModel,
          chapter: chapter,
        ),
      );
    }
    return switch (task!.status) {
      DownloadStatus.downloading => IconButton(
        tooltip: '暂停',
        icon: const Icon(Icons.pause_rounded),
        onPressed: () => DownloadManager.instance.pause(task!.id!),
      ),
      DownloadStatus.paused || DownloadStatus.failed => IconButton(
        tooltip: task!.status == DownloadStatus.failed ? '重试' : '继续',
        icon: Icon(
          task!.status == DownloadStatus.failed
              ? Icons.refresh_rounded
              : Icons.play_arrow_rounded,
        ),
        onPressed: () => DownloadManager.instance.resume(task!.id!),
      ),
      DownloadStatus.completed => const Icon(Icons.menu_book_rounded),
      DownloadStatus.pending => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    };
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
