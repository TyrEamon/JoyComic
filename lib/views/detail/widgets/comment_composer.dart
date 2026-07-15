import 'package:flutter/material.dart';

import '../../../comic_source/detail_models.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme_context.dart';
import '../../../theme/app_typography.dart';

class CommentComposer extends StatefulWidget {
  const CommentComposer({
    super.key,
    required this.replyTarget,
    required this.sending,
    required this.error,
    required this.onCancelReply,
    required this.onSend,
  });

  final CommentReplyTarget? replyTarget;
  final bool sending;
  final String? error;
  final VoidCallback onCancelReply;
  final Future<bool> Function(String content) onSend;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (widget.sending || _controller.text.trim().isEmpty) return;
    final success = await widget.onSend(_controller.text.trim());
    if (success && mounted) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.replyTarget != null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '回复 ${widget.replyTarget!.userName}',
                    style: AppTypography.meta(context),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('comment-cancel-reply'),
                  tooltip: '取消回复',
                  onPressed: widget.onCancelReply,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !widget.sending,
                  decoration: InputDecoration(
                    hintText: widget.replyTarget == null ? '写下评论' : '写下回复',
                    filled: true,
                    fillColor: context.surfaceColor,
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.brMd,
                      borderSide: BorderSide(color: context.borderColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 52,
                height: 52,
                child: FilledButton(
                  key: const ValueKey<String>('comment-send-button'),
                  onPressed: widget.sending ? null : _send,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.brMd,
                    ),
                  ),
                  child: widget.sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ),
            ],
          ),
          if (widget.error != null && widget.error!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.error!,
              style: AppTypography.cardMeta(
                context,
              ).copyWith(color: context.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
