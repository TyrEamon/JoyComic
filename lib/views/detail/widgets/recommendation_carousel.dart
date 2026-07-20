/// 相关推荐组件（Recommendation Carousel）。
///
/// - 顶部栏："相关推荐" + 右"换一换"
/// - 下方横向滑动卡片流；无数据时整块隐藏
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

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
  });

  final List<RecommendItem> items;
  final VoidCallback? onRefresh;
  final void Function(RecommendItem item)? onSelect;
  final Map<String, dynamic>? coverHeaders;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final accent = context.colorScheme.primary;
    final motionDisabled = MediaQuery.disableAnimationsOf(context);
    final batchKey = ValueKey<String>(items.map((item) => item.id).join('|'));

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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '换一换',
                          style: AppTypography.sectionAction(
                            context,
                          ).copyWith(color: accent),
                        ),
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
        AnimatedSwitcher(
          duration: motionDisabled
              ? Duration.zero
              : const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: SizedBox(
            key: batchKey,
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, index) {
                final item = items[index];
                return ComicCard.poster(
                  title: item.title,
                  coverUrl: item.cover,
                  subtitle: item.author,
                  rating: item.rating,
                  width: 132,
                  headers: coverHeaders,
                  onTap: onSelect == null ? null : () => onSelect!(item),
                );
              },
            ),
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
