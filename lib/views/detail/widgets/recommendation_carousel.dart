/// 相关推荐组件（Recommendation Carousel）。
///
/// - 顶部栏："相关推荐" + 右"换一换"（旋转 Icon）
/// - 下方横向滑动卡片流，每卡 = 竖版海报(3:4) + 作品名 + 评分数字
library recommendation_carousel;

import 'package:flutter/material.dart';

import '../../../foundation/palette_extractor.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import '../../common/widgets/comic_card.dart';

class RecommendationCarousel extends StatelessWidget {
  const RecommendationCarousel({
    super.key,
    required this.items,
    this.onRefresh,
    this.onSelect,
    this.coverHeaders,
    this.palette,
  });

  final List<RecommendItem> items;
  final VoidCallback? onRefresh;
  final void Function(RecommendItem item)? onSelect;
  final Map<String, dynamic>? coverHeaders;
  final ComicPalette? palette;

  @override
  Widget build(BuildContext context) {
    final accent = palette?.accent ?? AppColors.brandPink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Text('相关推荐', style: AppTypography.section(context)),
              const Spacer(),
              if (onRefresh != null)
                InkWell(
                  onTap: onRefresh,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        Text('换一换', style: AppTypography.sectionAction(context).copyWith(color: accent)),
                        const SizedBox(width: 2),
                        Icon(Icons.refresh_rounded, size: 16, color: accent),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: items.isEmpty ? 1 : items.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) {
              if (items.isEmpty) {
                return const SizedBox(
                  width: 220,
                  child: Center(child: Text('暂无推荐', style: TextStyle(color: AppColors.textLow))),
                );
              }
              final e = items[i];
              return ComicCard.poster(
                title: e.title,
                coverUrl: e.cover,
                subtitle: e.author,
                rating: e.rating,
                width: 132,
                headers: coverHeaders,
                onTap: onSelect == null ? null : () => onSelect!(e),
              );
            },
          ),
        ),
      ],
    );
  }
}

class RecommendItem {
  const RecommendItem({
    required this.id,
    required this.title,
    required this.cover,
    this.author,
    this.rating,
    this.sourceKey,
  });
  final String id;
  final String title;
  final String? cover;
  final String? author;
  final double? rating;
  final String? sourceKey;
}
