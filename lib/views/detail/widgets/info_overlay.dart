/// 详情页信息叠加层。
///
/// 围绕前景完整封面展开排布：
/// - 热度胶囊标签（[PillBadge]）置顶
/// - 主标题 + 两行副标题
/// - 元数据组：作者名（带跳转箭头）/ tags / 热度·收藏量
/// - 评分复合组件：大号数字 + 五星 + 评价人数
library info_overlay;

import 'package:flutter/material.dart';

import '../../../foundation/palette_extractor.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/widgets/pill_badge.dart';
import '../../common/widgets/comic_cover.dart';
import '../../common/widgets/rating_stars.dart';

class InfoOverlay extends StatelessWidget {
  const InfoOverlay({
    super.key,
    required this.title,
    required this.subTitle,
    required this.frontCover,
    required this.author,
    required this.tags,
    required this.hotValue,
    required this.favoriteCount,
    required this.rating,
    required this.ratingCount,
    required this.palette,
    this.coverHeaders,
  });

  final String title;
  final String? subTitle;
  final String? frontCover;
  final String? author;
  final List<String> tags;
  final String? hotValue;
  final String? favoriteCount;
  final double rating;
  final String ratingCount;
  final ComicPalette palette;
  final Map<String, dynamic>? coverHeaders;

  static const double _coverWidth = 132;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 前层完整封面。
          Padding(
            padding: const EdgeInsets.only(top: 56),
            child: ComicCover(
              url: frontCover,
              width: _coverWidth,
              headers: coverHeaders,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // 信息文本列。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hotValue != null) ...[
                  PillBadge(
                    label: '热度 $hotValue',
                    gradient: palette.gradient,
                    leadingDotColor: AppColors.hotAccent,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.hero(context),
                ),
                if (subTitle != null && subTitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subTitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.subtitle(context),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                _RatingChip(
                  rating: rating,
                  count: ratingCount,
                  palette: palette,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 评分复合组件：大号数字 + 五星 + 评价人数。
class _RatingChip extends StatelessWidget {
  const _RatingChip({
    required this.rating,
    required this.count,
    required this.palette,
  });

  final double rating;
  final String count;
  final ComicPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          rating.toStringAsFixed(1),
          style: AppTypography.ratingNumber(
            context,
          ).copyWith(color: palette.accent),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: RatingStars(
            rating: rating / 2,
            color: palette.accent,
            size: 13,
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('$count 人评价', style: AppTypography.ratingCount(context)),
        ),
      ],
    );
  }
}
