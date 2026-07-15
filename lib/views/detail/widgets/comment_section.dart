/// Typed comment list with reply previews and load-more support.
library;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../comic_source/detail_models.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';

class CommentSection extends StatelessWidget {
  const CommentSection({
    super.key,
    required this.comments,
    required this.loading,
    required this.hasMore,
    required this.onReply,
    required this.onLoadMore,
  });

  final List<Comment> comments;
  final bool loading;
  final bool hasMore;
  final ValueChanged<Comment> onReply;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        children: [
          if (loading && comments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text(
                '还没有评论',
                style: TextStyle(color: context.tertiaryTextColor),
              ),
            )
          else
            for (final comment in comments)
              _CommentCard(comment: comment, onReply: () => onReply(comment)),
          if (hasMore)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: loading ? null : onLoadMore,
                  child: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('加载更多评论'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.comment, required this.onReply});

  final Comment comment;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(url: comment.avatar),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  comment.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.cardTitle(context),
                ),
              ),
              TextButton(onPressed: onReply, child: const Text('回复')),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(comment.content, style: AppTypography.body(context)),
          if (comment.replies.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                color: context.semanticColors.surfaceMuted,
                borderRadius: AppRadius.brSm,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final reply in comment.replies.take(3))
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Text(
                          '${reply.userName}：${reply.content}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.cardMeta(context),
                        ),
                      ),
                    if (comment.replyCount > comment.replies.length)
                      Text(
                        '共 ${comment.replyCount} 条回复',
                        style: AppTypography.cardMeta(
                          context,
                        ).copyWith(color: context.colorScheme.primary),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              if (comment.time != null)
                Text(comment.time!, style: AppTypography.cardMeta(context)),
              const Spacer(),
              Icon(
                Icons.favorite_border_rounded,
                size: 14,
                color: context.tertiaryTextColor,
              ),
              const SizedBox(width: 4),
              Text(
                comment.likeCount.toString(),
                style: AppTypography.cardMeta(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: ClipOval(
        child: url == null
            ? ColoredBox(
                color: context.elevatedSurfaceColor,
                child: Icon(
                  Icons.person_rounded,
                  size: 18,
                  color: context.disabledTextColor,
                ),
              )
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: context.elevatedSurfaceColor,
                  child: Icon(
                    Icons.person_rounded,
                    size: 18,
                    color: context.disabledTextColor,
                  ),
                ),
              ),
      ),
    );
  }
}
