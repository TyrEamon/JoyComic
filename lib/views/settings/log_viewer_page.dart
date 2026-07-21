/// 诊断日志查看页。
///
/// 展示 Log 系统持久化的日志条目，按时间倒序排列。
/// 支持：按级别筛选、单条复制、一键导出为 TXT 并分享。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:share_plus/share_plus.dart';

import '../../foundation/log.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  List<JoyLogEntry> _logs = const [];
  bool _loading = true;
  bool _exporting = false;
  String? _levelFilter;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final logs = await Log.getLogs();
    if (!mounted) return;
    setState(() {
      _logs = logs.reversed.toList();
      _loading = false;
    });
  }

  List<JoyLogEntry> get _filtered {
    if (_levelFilter == null) return _logs;
    return _logs.where((l) => l.level == _levelFilter).toList();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除日志'),
        content: const Text('确定删除全部诊断日志？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Log.clear();
    if (!mounted) return;
    _showMessage('日志已清除');
    await _loadLogs();
  }

  Future<void> _copyLog(JoyLogEntry log) async {
    await Clipboard.setData(ClipboardData(text: log.toString()));
    if (!mounted) return;
    _showMessage('已复制');
  }

  /// 一键导出当前列表（尊重级别筛选）为 TXT 并打开系统分享。
  Future<void> _exportLogs() async {
    if (_exporting) return;
    final source = _filtered;
    if (source.isEmpty) {
      _showMessage('暂无日志可导出');
      return;
    }

    setState(() => _exporting = true);
    try {
      // List is newest-first; TXT is chronological for easier reading.
      final chronological = source.reversed.toList(growable: false);
      final note = _levelFilter == null ? null : '筛选级别：$_levelFilter';
      final file = await Log.writeExportTxtFile(
        logs: chronological,
        note: note,
      );
      if (!mounted) return;
      if (file == null) {
        _showMessage('暂无日志可导出');
        return;
      }

      final box = context.findRenderObject();
      final origin = box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      final name = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'joycomic_logs.txt';

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/plain', name: name)],
        subject: 'JoyComic 诊断日志',
        text: 'JoyComic 诊断日志（TXT）',
        sharePositionOrigin: origin,
        fileNameOverrides: [name],
      );
      if (!mounted) return;
      _showMessage('已生成 TXT，请选择微信/文件等发出');
    } catch (error, stackTrace) {
      Log.e('Log export failed', error: error, stackTrace: stackTrace);
      if (mounted) {
        _showMessage('日志导出失败：${_readableError(error)}');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _readableError(Object error) {
    final message = error.toString().trim();
    if (message.isEmpty) return '未知错误';
    return message.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  Color _levelColor(String level) => switch (level) {
    'error' || 'fatal' => context.colorScheme.error,
    'warn' || 'warning' => context.warningColor,
    'info' => context.colorScheme.primary,
    _ => context.secondaryTextColor,
  };

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text('诊断日志'),
        backgroundColor: context.pageBackground,
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: context.secondaryTextColor,
            ),
            onPressed: _loadLogs,
            tooltip: '刷新',
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              color: context.secondaryTextColor,
            ),
            onPressed: filtered.isNotEmpty ? _clear : null,
            tooltip: '清除日志',
          ),
        ],
      ),
      body: Column(
        children: [
          // 一键导出条：比右上角图标更醒目，避免找不到。
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('log-export-txt-button'),
                onPressed: _exporting || filtered.isEmpty ? null : _exportLogs,
                icon: _exporting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.ios_share_rounded),
                label: Text(
                  _exporting
                      ? '正在导出…'
                      : '一键导出为 TXT（${filtered.length} 条）',
                ),
              ),
            ),
          ),
          // 级别筛选栏
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                _LevelChip(
                  label: '全部',
                  active: _levelFilter == null,
                  onTap: () => setState(() => _levelFilter = null),
                ),
                const SizedBox(width: 6),
                _LevelChip(
                  label: '错误',
                  active: _levelFilter == 'error',
                  onTap: () => setState(() => _levelFilter = 'error'),
                ),
                const SizedBox(width: 6),
                _LevelChip(
                  label: '警告',
                  active: _levelFilter == 'warn',
                  onTap: () => setState(() => _levelFilter = 'warn'),
                ),
                const SizedBox(width: 6),
                _LevelChip(
                  label: '信息',
                  active: _levelFilter == 'info',
                  onTap: () => setState(() => _levelFilter = 'info'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.borderColor),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: context.colorScheme.primary,
                      strokeWidth: 2.5,
                    ),
                  )
                : filtered.isEmpty
                ? Center(
                    child: Text(
                      '暂无日志',
                      style: TextStyle(color: context.tertiaryTextColor),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (_, i) {
                      final log = filtered[i];
                      return _LogCard(
                        log: log,
                        color: _levelColor(log.level),
                        onCopy: () => _copyLog(log),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? context.colorScheme.primary : context.surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? context.colorScheme.primary : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active
                ? context.colorScheme.onPrimary
                : context.secondaryTextColor,
          ),
        ),
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({
    required this.log,
    required this.color,
    required this.onCopy,
  });
  final JoyLogEntry log;
  final Color color;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: AppRadius.brSm,
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: AppRadius.brSm,
                ),
                child: Text(
                  log.level.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  log.time,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.tertiaryTextColor,
                  ),
                ),
              ),
              InkWell(
                onTap: onCopy,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: context.tertiaryTextColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            log.message,
            style: TextStyle(
              fontSize: 12,
              color: context.primaryTextColor,
              fontFamily: 'monospace',
            ),
          ),
          if (log.error != null && log.error!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              log.error!,
              style: TextStyle(
                fontSize: 11,
                color: context.colorScheme.error,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
