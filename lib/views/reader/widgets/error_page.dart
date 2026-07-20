import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../utils/reader_utils.dart';

/// 通用错误+重试页（阅读器章节加载失败、网络异常等场景）。
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
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        spacing: 10,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              widget.errorMessage,
              maxLines: 3,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodyMedium,
            ),
          ),
          if (widget.traceId != null && widget.traceId!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SelectableText(
                'trace ${widget.traceId}',
                style: context.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          Row(
            spacing: 8,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: widget.onRetry, child: const Text('重新加载')),
              if (widget.canPop && context.canPop())
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('返回'),
                ),
            ],
          ),
          if (widget.onOpenLogs != null || widget.traceId != null)
            TextButton(
              onPressed: () {
                if (widget.onOpenLogs != null) {
                  widget.onOpenLogs!();
                  return;
                }
                final id = widget.traceId;
                if (id == null || id.isEmpty) return;
                Clipboard.setData(ClipboardData(text: id));
              },
              child: const Text('查看诊断日志'),
            ),
          ?widget.extraButton,
        ],
      ),
    );
  }
}
