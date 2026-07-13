/// 评论组件（Comment Section）。
///
/// - 顶部栏："评论（总数）" + 右"更多评论 >"入口
/// - 评论卡片：头像 / 昵称 / 等级勋章 / 星级评分 / 多行评论文本 /
///   底部发表时间 + 带数字点赞 Icon
library comment_section;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_shadows.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import '../../common/widgets/rating_stars.dart';

/// 评论 UI 数据（与 ComicSource.Comment 解耦的视图模型）。
class CommentView {
  const CommentView({
    required this.userName,
    this.avatar,
    this.level,
    required this.content,
    this.time,
    this.rating,
    this.likes,
  });
  final String userName;
  final String? avatar;
  final int? level;
  final String content;
  final String? time;
  final double? rating; // 0~5
  final int? likes;
}

class CommentSection extends StatelessWidget {
  const CommentSection({
    super.key,
    required this.total,
    required this.comments,
    this.onShowAll,
  });

  final int total;
  final List<CommentView> comments;
  final VoidCallback? onShowAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('评论', style: AppTypography.section(context)),
              if (total > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '($total)',
                  style: AppTypography.section(context).copyWith(
                    color: AppColors.textLow,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
              const Spacer(),
              if (onShowAll != null)
                InkWell(
                  onTap: onShowAll,
                  borderRadius: AppRadius.brSm,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        Text('更多评论', style: AppTypography.sectionAction(context)),
                        const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textLow),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: Text('还没有评论', style: TextStyle(color: AppColors.textLow))),
            )
          else
            ...comments.map((c) => _CommentCard(c)),
        ],
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard(this.c);
  final CommentView c;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(url: c.avatar),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.cardTitle(context).copyWith(fontSize: 13),
                          ),
                        ),
                        if (c.level != null) ...[
                          const SizedBox(width: 6),
                          _LevelBadge(level: c.level!),
                        ],
                      ],
                    ),
                    if (c.rating != null) ...[
                      const SizedBox(height: 2),
                      RatingStars(rating: c.rating!, size: 11),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            c.content,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.body(context).copyWith(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              if (c.time != null)
                Text(c.time!, style: AppTypography.ratingCount(context)),
              const Spacer(),
              Icon(Icons.favorite_border_rounded, size: 14, color: AppColors.textLow),
              const SizedBox(width: 4),
              Text(
                c.likes != null ? '${c.likes}' : '0',
                style: AppTypography.ratingCount(context),
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
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceElevated,
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: url == null
          ? const Icon(Icons.person, size: 18, color: AppColors.textDisabled)
          : CachedNetworkImage(
              imageUrl: url!,
              fit: BoxFit.cover,
              placeholder: (_, __) => const ColoredBox(color: AppColors.surfaceElevated, child: SizedBox.expand()),
              errorWidget: (_, __, ___) => const Icon(Icons.person, size: 18, color: AppColors.textDisabled),
            ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brandPink, AppColors.brandViolet],
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        'Lv.$level',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
