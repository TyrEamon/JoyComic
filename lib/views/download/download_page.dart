/// 下载管理页。
///
/// 顶部 2 Tab：下载中 / 已下载。
/// 集成真实下载管理器（DownloadManager）。
library download_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../foundation/download_manager.dart';
import '../../foundation/download_task.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

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
        final mgr = DownloadManager.instance;
        final downloading = mgr.tasks
            .where((t) => t.status == DownloadStatus.pending ||
                t.status == DownloadStatus.downloading)
            .toList();
        final completed = mgr.tasks
            .where((t) => t.status == DownloadStatus.completed)
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
              tabs: [
                Tab(text: '下载中 (${downloading.length})'),
                Tab(text: '已下载 (${completed.length})'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: [
              _DownloadingList(items: downloading),
              _CompletedList(items: completed),
            ],
          ),
        );
      },
    );
  }
}

class _DownloadingList extends StatelessWidget {
  const _DownloadingList({required this.items});
  final List<DownloadItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text('暂无下载任务', style: TextStyle(color: AppColors.textLow)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      itemCount: items.length,
      itemBuilder: (_, i) => _DownloadCard(item: items[i]),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.item});
  final DownloadItem item;

  @override
  Widget build(BuildContext context) {
    final mgr = DownloadManager.instance;
    final isActive = item.status == DownloadStatus.downloading;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        children: [
          // 缩略封面占位
          Container(
            width: 48, height: 64,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: AppRadius.brSm,
            ),
            child: const Icon(Icons.image_outlined, color: AppColors.textLow),
          ),
          const SizedBox(width: AppSpacing.sm),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.fileName ?? '图片',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textHigh),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: item.progress,
                  backgroundColor: AppColors.surfaceElevated,
                  color: AppColors.brandPink,
                ),
                const SizedBox(height: 2),
                Text(
                  '${(item.progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textLow),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // 操作按钮
          if (isActive)
            IconButton(
              icon: const Icon(Icons.pause_rounded, size: 20),
              color: AppColors.textMedium,
              onPressed: () => mgr.pause(item.id!),
            )
          else if (item.status == DownloadStatus.paused)
            IconButton(
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              color: AppColors.textMedium,
              onPressed: () => mgr.resume(item.id!),
            )
          else if (item.status == DownloadStatus.failed)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              color: Colors.redAccent,
              onPressed: () => mgr.retry(item.id!),
            ),
        ],
      ),
    );
  }
}

class _CompletedList extends StatelessWidget {
  const _CompletedList({required this.items});
  final List<DownloadItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Text('暂无已下载内容', style: TextStyle(color: AppColors.textLow)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      itemCount: items.length,
      itemBuilder: (_, i) => ListTile(
        leading: Icon(Icons.check_circle, color: AppColors.success),
        title: Text(items[i].fileName ?? '',
            style: const TextStyle(color: AppColors.textHigh)),
        subtitle: Text('${(items[i].progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: AppColors.textLow)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: AppColors.textLow),
          onPressed: () => DownloadManager.instance.delete(items[i].id!),
        ),
      ),
    );
  }
}
