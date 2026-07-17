/// 详情页封面信息叠加层：标题、作者与可选评分。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme_context.dart';
import '../../../theme/app_typography.dart';
import '../../common/widgets/comic_cover.dart';
import '../../common/widgets/rating_stars.dart';

class InfoOverlay extends StatelessWidget {
  const InfoOverlay({
    super.key,
    required this.title,
    required this.subTitle,
    required this.frontCover,
    required this.rating,
    this.coverHeaders,
  });

  final String title;
  final String? subTitle;
  final String? frontCover;
  final double? rating;
  final Map<String, dynamic>? coverHeaders;

  static const double _coverWidth = 132;

  @override
  Widget build(BuildContext context) {
    final onImage = context.onImageColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 56, AppSpacing.md, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ComicCover(
            url: frontCover,
            width: _coverWidth,
            headers: coverHeaders,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.hero(context).copyWith(color: onImage),
                ),
                if (subTitle != null && subTitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subTitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.subtitle(
                      context,
                    ).copyWith(color: onImage.withValues(alpha: 0.82)),
                  ),
                ],
                if (rating != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Text(
                        rating!.toStringAsFixed(1),
                        style: AppTypography.ratingNumber(
                          context,
                        ).copyWith(color: onImage),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      RatingStars(rating: rating! / 2, size: 14),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
