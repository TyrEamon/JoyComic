/// 通用骨架加载网格。
///
/// 列表/首页/搜索结果等页加载时显示，呼应设计 token 的卡片质感。
/// 与 EmptyState 一起覆盖 loading/empty/data 三态。
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import 'shimmer.dart';

class LoadingGrid extends StatelessWidget {
  const LoadingGrid({
    super.key,
    this.crossAxisCount = 3,
    this.itemCount = 9,
    this.childAspectRatio = 0.55,
  });

  final int crossAxisCount;
  final int itemCount;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: itemCount,
      itemBuilder: (_, __) => const Shimmer(child: _SkeletonCard()),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: AppRadius.brMd,
            child: Container(color: context.elevatedSurfaceColor),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: 12,
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.elevatedSurfaceColor,
            borderRadius: AppRadius.brSm,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 10,
          width: 60,
          decoration: BoxDecoration(
            color: context.elevatedSurfaceColor,
            borderRadius: AppRadius.brSm,
          ),
        ),
      ],
    );
  }
}
