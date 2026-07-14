/// Chapter download management and offline reading entry.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../foundation/download_manager.dart';
import '../../foundation/download_task.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../common/widgets/comic_cover.dart';
import '../reader/state/comic_state.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadManager.instance,
      builder: (context, _) {
        final tasks = DownloadManager.instance.tasks;
        final active = tasks
            .where((task) => task.status != DownloadStatus.completed)
            .toList();
        final completed = tasks
            .where((task) => task.status == DownloadStatus.completed)
            .toList();
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('下载'),
            backgroundColor: AppColors.background,
            bottom: TabBar(
              controller: _tab,
              indicatorColor: AppColors.brandPink,
              labelColor: AppColors.textHigh,
              unselectedLabelColor: AppColors.textLow,
              tabs: <Widget>[
                Tab(text: '任务 (${active.length})'),
                Tab(text: '已下载 (${completed.length})'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: <Widget>[
              _GroupedTaskList(tasks: active, completed: false),
              _GroupedTaskList(tasks: completed, completed: true),
            ],
          ),
        );
      },
    );
  }
}

class _GroupedTaskList extends StatelessWidget {
  const _GroupedTaskList({required this.tasks, required this.completed});

  final List<DownloadTask> tasks;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Center(
        child: Text(
          completed ? '暂无已下载章节' : '暂无下载任务',
          style: const TextStyle(color: AppColors.textLow),
        ),
      );
    }
    final groups = <(String, String), List<DownloadTask>>{};
    for (final task in tasks) {
      groups
          .putIfAbsent((task.sourceKey, task.comicId), () => <DownloadTask>[])
          .add(task);
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.sm),
      children: <Widget>[
        for (final group in groups.values) _ComicDownloadGroup(tasks: group),
      ],
    );
  }
}

class _ComicDownloadGroup extends StatelessWidget {
  const _ComicDownloadGroup({required this.tasks});

  final List<DownloadTask> tasks;

  @override
  Widget build(BuildContext context) {
    final first = tasks.first;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: ComicCover(
          url: first.coverUrl,
          width: 42,
          radius: AppRadius.sm,
          elevation: false,
        ),
        title: Text(
          first.title.isEmpty ? first.comicId : first.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textHigh),
        ),
        subtitle: Text(
          '${tasks.length} 个章节 · ${first.sourceKey}',
          style: const TextStyle(color: AppColors.textLow, fontSize: 12),
        ),
        children: <Widget>[for (final task in tasks) _TaskTile(task: task)],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final completed = task.status == DownloadStatus.completed;
    return ListTile(
      onTap: completed ? () => _openOffline(context) : null,
      title: Text(
        task.chapterTitle.isEmpty ? task.chapterId : task.chapterTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textHigh, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 5),
          LinearProgressIndicator(
            value: task.progress,
            minHeight: 3,
            backgroundColor: AppColors.surfaceElevated,
            color: completed ? AppColors.success : AppColors.brandPink,
          ),
          const SizedBox(height: 4),
          Text(
            _statusText(task),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: task.status == DownloadStatus.failed
                  ? Colors.redAccent
                  : AppColors.textLow,
              fontSize: 11,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (task.status == DownloadStatus.downloading)
            IconButton(
              tooltip: '暂停',
              onPressed: () => DownloadManager.instance.pause(task.id!),
              icon: const Icon(Icons.pause_rounded),
            )
          else if (task.status == DownloadStatus.paused)
            IconButton(
              tooltip: '继续',
              onPressed: () => DownloadManager.instance.resume(task.id!),
              icon: const Icon(Icons.play_arrow_rounded),
            )
          else if (task.status == DownloadStatus.failed)
            IconButton(
              tooltip: '重试',
              onPressed: () => DownloadManager.instance.retry(task.id!),
              icon: const Icon(Icons.refresh_rounded, color: Colors.redAccent),
            )
          else if (completed)
            const Icon(Icons.menu_book_rounded, color: AppColors.success),
          IconButton(
            tooltip: '删除',
            onPressed: () => _showDeleteChoices(context),
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.textLow),
          ),
        ],
      ),
    );
  }

  void _openOffline(BuildContext context) {
    try {
      context.push('/reader', extra: ComicState.fromDownload(task));
    } on StateError catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message.toString())));
    }
  }

  Future<void> _showDeleteChoices(BuildContext context) async {
    final deleteFiles = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.playlist_remove_rounded),
              title: const Text('仅删除任务记录'),
              subtitle: const Text('保留已下载或临时文件'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_forever_rounded,
                color: Colors.redAccent,
              ),
              title: const Text('删除任务和文件'),
              subtitle: const Text('本地章节文件将一并删除'),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (deleteFiles == null) return;
    if (deleteFiles) {
      await DownloadManager.instance.deleteFiles(task.id!);
    } else {
      await DownloadManager.instance.deleteTask(task.id!);
    }
  }

  static String _statusText(DownloadTask task) {
    final count = '${task.completedCount}/${task.pageUrls.length} 页';
    return switch (task.status) {
      DownloadStatus.pending => '等待中',
      DownloadStatus.downloading => '下载中 · $count',
      DownloadStatus.paused => '已暂停 · $count',
      DownloadStatus.completed => '已完成 · $count · 点击离线阅读',
      DownloadStatus.failed => '失败 · $count · ${task.errorMessage ?? '未知错误'}',
    };
  }
}
