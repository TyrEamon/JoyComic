import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../foundation/log_export.dart';
import '../utils/reader_utils.dart';

/// 通用错误+重试页（阅读器章节加载失败、网络异常等场景）。
///
/// 阅读器画布为纯黑：本页强制使用浅色文案与按钮，避免「全黑无操作」。
class ErrorPage extends StatefulWidget {
  const ErrorPage({
    super.key,
    required this.errorMessage,
    required this.onRetry,
    this.canPop = false,
    this.extraButton,
    this.traceId,
    this.onOpenLogs,
  });

  final String errorMessage;
  final Function() onRetry;
  final bool canPop;
  final Widget? extraButton;
  final String? traceId;
  final VoidCallback? onOpenLogs;

  @override
  State<ErrorPage> createState() => _ErrorPageState();
}

class _ErrorPageState extends State<ErrorPage> {
  static const Color _onDark = Color(0xFFECECEC);
  bool _exporting = false;

  Future<void> _exportTxt() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final note = widget.traceId == null || widget.traceId!.isEmpty
          ? 'from reader error page'
          : 'from reader error page; trace=${widget.traceId}';
      final ok = await exportJoyComicLogsTxt(context: context, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '已生成 TXT，请选择发送方式' : '暂无日志可导出'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: SafeArea(
        child: Stack(
          children: [
            if (widget.canPop && context.canPop())
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  tooltip: '返回',
                  color: _onDark,
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
              ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: _onDark,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.errorMessage,
                      maxLines: 4,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: _onDark,
                      ),
                    ),
                    if (widget.traceId != null &&
                        widget.traceId!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        'trace ${widget.traceId}',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: _onDark.withValues(alpha: 0.72),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            foregroundColor: _onDark,
                            backgroundColor: const Color(0x33FFFFFF),
                          ),
                          onPressed: widget.onRetry,
                          child: const Text('重新加载'),
                        ),
                        if (widget.canPop && context.canPop())
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _onDark,
                              side: const BorderSide(color: Color(0x66FFFFFF)),
                            ),
                            onPressed: () => context.pop(),
                            child: const Text('返回'),
                          ),
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            foregroundColor: _onDark,
                            backgroundColor: const Color(0x33FFFFFF),
                          ),
                          onPressed: () {
                            if (widget.onOpenLogs != null) {
                              widget.onOpenLogs!();
                              return;
                            }
                            final id = widget.traceId;
                            if (id == null || id.isEmpty) return;
                            Clipboard.setData(ClipboardData(text: id));
                          },
                          icon: const Icon(Icons.bug_report_outlined),
                          label: const Text('打开日志页'),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            foregroundColor: const Color(0xFF111111),
                            backgroundColor: _onDark,
                          ),
                          onPressed: _exporting ? null : _exportTxt,
                          icon: _exporting
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.ios_share_rounded),
                          label: Text(_exporting ? '导出中…' : '导出 TXT'),
                        ),
                        if (widget.extraButton != null) widget.extraButton!,
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
