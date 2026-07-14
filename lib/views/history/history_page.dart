/// 本地阅读历史页。
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../database/read_record_helper.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../common/utils/source_login_guard.dart';
import '../common/widgets/comic_cover.dart';
import '../common/widgets/empty_state.dart';
import '../reader/state/comic_state.dart';

class HistoryPageController extends ChangeNotifier {
  HistoryPageController(this.helper);

  final ReadRecordHelper helper;
  List<ReadRecord> _records = const [];
  List<ReadRecord> get records => List.unmodifiable(_records);

  void load() {
    _records = helper.list();
    notifyListeners();
  }

  void delete(ReadRecord record) {
    helper.delete(record.source, record.comic);
    load();
  }

  void clear() {
    helper.clear();
    load();
  }
}

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, this.readRecordHelper});

  final ReadRecordHelper? readRecordHelper;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final HistoryPageController _controller = HistoryPageController(
    widget.readRecordHelper ?? ReadRecordHelper(),
  )..load();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmClear() async {
    if (_controller.records.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('将删除全部本地阅读历史，此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) _controller.clear();
  }

  Future<void> _continueReading(ReadRecord record) async {
    await context.push('/reader', extra: ComicState.fromReadRecord(record));
    if (mounted) _controller.load();
  }

  Future<void> _openDetail(ReadRecord record) async {
    final source = ComicSource.find(record.source);
    if (source != null && !source.isLogin) {
      final allowed = await ensureSourceLoggedIn(context, record.source);
      if (!allowed) return;
    }
    if (!mounted) return;
    context.push('/detail/${record.source}/${record.comic}');
  }

  @override
  Widget build(BuildContext context) {
    final records = _controller.records;
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: Text('阅读历史 ${records.length}'),
        backgroundColor: context.pageBackground,
        actions: [
          IconButton(
            tooltip: '清空历史',
            onPressed: records.isEmpty ? null : _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: records.isEmpty
          ? const EmptyState(
              icon: Icons.history_rounded,
              title: '暂无阅读历史',
              subtitle: '开始阅读后，进度会自动保存在这里',
            )
          : RefreshIndicator(
              onRefresh: () async => _controller.load(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                itemCount: records.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final record = records[index];
                  return _HistoryCard(
                    record: record,
                    onContinue: () => _continueReading(record),
                    onDetail: () => _openDetail(record),
                    onDelete: () => _controller.delete(record),
                  );
                },
              ),
            ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.record,
    required this.onContinue,
    required this.onDetail,
    required this.onDelete,
  });

  final ReadRecord record;
  final VoidCallback onContinue;
  final VoidCallback onDetail;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final source = ComicSource.find(record.source);
    final sourceName = source?.name ?? record.source;
    final headers = record.cover.isEmpty
        ? null
        : source?.getThumbnailLoadingConfig?.call(record.cover);
    final currentPage = record.pageNo + 1;
    final pageText = record.pageCount > 0
        ? '$currentPage / ${record.pageCount} 页'
        : '第 $currentPage 页';
    final chapter = record.chapterTitle.isNotEmpty
        ? record.chapterTitle
        : record.chapterId.isNotEmpty
        ? record.chapterId
        : '全本';

    return Dismissible(
      key: ValueKey('${record.source}:${record.comic}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.colorScheme.error,
          borderRadius: AppRadius.brLg,
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: context.surfaceColor,
        borderRadius: AppRadius.brLg,
        child: InkWell(
          borderRadius: AppRadius.brLg,
          onTap: onContinue,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ComicCover(
                  url: record.cover,
                  width: 72,
                  radius: AppRadius.md,
                  headers: headers,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.title.isEmpty ? record.comic : record.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$sourceName · $chapter',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: context.secondaryTextColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$pageText · ${_formatUpdatedAt(record.updatedAt)}',
                        style: TextStyle(
                          color: context.tertiaryTextColor,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: onContinue,
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 18,
                            ),
                            label: const Text('继续阅读'),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: '查看详情',
                            visualDensity: VisualDensity.compact,
                            onPressed: onDetail,
                            icon: const Icon(Icons.info_outline_rounded),
                          ),
                          IconButton(
                            tooltip: '删除历史',
                            visualDensity: VisualDensity.compact,
                            onPressed: onDelete,
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatUpdatedAt(int milliseconds) {
  if (milliseconds <= 0) return '未知时间';
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final now = DateTime.now();
  final difference = now.difference(time);
  if (!difference.isNegative && difference.inMinutes < 1) return '刚刚';
  if (!difference.isNegative && difference.inHours < 1) {
    return '${difference.inMinutes} 分钟前';
  }
  if (!difference.isNegative && difference.inDays < 1) {
    return '${difference.inHours} 小时前';
  }
  if (!difference.isNegative && difference.inDays < 7) {
    return '${difference.inDays} 天前';
  }
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}
