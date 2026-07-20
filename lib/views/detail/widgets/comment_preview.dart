/// Compact 1–2 comment preview for the detail page.
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../comic_source/detail_models.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import 'comment_section.dart';

class CommentPreview extends StatelessWidget {
  const CommentPreview({
    super.key,
    required this.comments,
    required this.loading,
    required this.canOpenAll,
    required this.onOpenAll,
  });

  final List<Comment> comments;
  final bool loading;
  final bool canOpenAll;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final preview = comments.take(2).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('最新评论', style: AppTypography.section(context)),
              const Spacer(),
              if (canOpenAll && comments.isNotEmpty)
                Semantics(
                  button: true,
                  label: '全部评论',
                  child: TextButton(
                    onPressed: onOpenAll,
                    child: const Text('全部评论'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (loading && preview.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (preview.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                canOpenAll ? '还没有评论' : '当前漫画源不支持评论',
                style: TextStyle(color: context.tertiaryTextColor),
              ),
            )
          else
            for (final comment in preview)
              CommentTile(comment: comment, compact: true),
        ],
      ),
    );
  }
}
