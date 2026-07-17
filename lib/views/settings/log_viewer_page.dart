/// 诊断日志查看页。
///
/// 展示 Log 系统持久化的日志条目，按时间倒序排列。
/// 支持：按级别筛选、单条复制、全部导出为 TXT。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
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
    await Log.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('日志已清除')));
    await _loadLogs();
  }

  /// 复制单条日志到剪贴板。
  Future<void> _copyLog(JoyLogEntry log) async {
    await Clipboard.setData(ClipboardData(text: log.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
    );
  }

  /// 导出全部日志为 TXT 文件并分享。
  Future<void> _exportLogs() async {
    if (_exporting) return;
    if (_logs.isEmpty) {
      _showMessage('暂无日志可导出');
      return;
    }

    final renderObject = context.findRenderObject();
    final shareOrigin = renderObject is RenderBox && renderObject.hasSize
        ? renderObject.localToGlobal(Offset.zero) & renderObject.size
        : null;
    setState(() => _exporting = true);

    try {
      final buffer = StringBuffer();
      buffer.writeln('JoyComic 诊断日志');
      buffer.writeln('导出时间：${DateTime.now().toIso8601String()}');
      buffer.writeln('条目数：${_logs.length}');
      buffer.writeln('=' * 60);
      buffer.writeln();

      for (final log in _logs.reversed) {
        buffer.writeln('[${log.time}][${log.level.toUpperCase()}]');
        buffer.writeln(log.message);
        if (log.error != null && log.error!.isNotEmpty) {
          buffer.writeln('Error: ${log.error}');
        }
        if (log.stackTrace != null && log.stackTrace!.isNotEmpty) {
          buffer.writeln('Stack: ${log.stackTrace}');
        }
        buffer.writeln();
        buffer.writeln('-' * 40);
        buffer.writeln();
      }

      final dir = await getTemporaryDirectory();
      final fileName =
          'joycomic_logs_${DateTime.now().millisecondsSinceEpoch}.txt';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(buffer.toString(), flush: true);
      if (!mounted) return;

      final result = await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/plain')],
        subject: 'JoyComic 诊断日志',
        text: 'JoyComic 诊断日志',
        sharePositionOrigin: shareOrigin,
        fileNameOverrides: [fileName],
      );
      if (!mounted) return;

      switch (result.status) {
        case ShareResultStatus.success:
          _showMessage('日志导出成功');
        case ShareResultStatus.dismissed:
          _showMessage('已取消日志导出');
        case ShareResultStatus.unavailable:
          _showMessage('日志已生成并交给系统分享');
      }
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
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.file_upload_outlined,
                    color: context.secondaryTextColor,
                  ),
            onPressed: _exporting ? null : _exportLogs,
            tooltip: _exporting ? '正在导出日志' : '导出日志',
          ),
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
          // 日志列表
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
