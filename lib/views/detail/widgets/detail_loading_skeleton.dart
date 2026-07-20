/// Loading skeleton matching the immersive hero/content geometry.
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';

class DetailLoadingSkeleton extends StatelessWidget {
  const DetailLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = context.semanticColors.surfaceMuted;
    final elevated = context.elevatedSurfaceColor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final coverWidth = width >= 900
            ? 188.0
            : width >= 600
            ? 164.0
            : (width * 0.34).clamp(116.0, 144.0);
        final backdropHeight = width >= 600 ? 340.0 : 300.0;
        final seamTop = backdropHeight - 34;
        final totalHeight = backdropHeight + (width >= 600 ? 190.0 : 170.0);

        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('detail-skeleton-hero'),
                height: totalHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: backdropHeight,
                      child: ColoredBox(color: elevated),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: seamTop,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.pageBackground,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      key: const ValueKey('detail-skeleton-cover'),
                      left: AppSpacing.md,
                      top: seamTop - coverWidth * 0.56,
                      width: coverWidth,
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: muted,
                            borderRadius: AppRadius.brLg,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.md + coverWidth + AppSpacing.md,
                      right: AppSpacing.md,
                      top: seamTop - 72,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Bone(width: width * 0.42, height: 22, color: muted),
                          const SizedBox(height: AppSpacing.sm),
                          _Bone(width: width * 0.28, height: 14, color: muted),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (var i = 0; i < 4; i++)
                          _Bone(
                            width:
                                (width - AppSpacing.md * 2 - AppSpacing.sm) / 2,
                            height: 18,
                            color: muted,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sectionGap),
                    _Bone(width: 64, height: 18, color: muted),
                    const SizedBox(height: AppSpacing.sm),
                    _Bone(width: double.infinity, height: 14, color: muted),
                    const SizedBox(height: AppSpacing.xs),
                    _Bone(width: width * 0.7, height: 14, color: muted),
                    const SizedBox(height: AppSpacing.sectionGap),
                    _Bone(width: 88, height: 18, color: muted),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      key: const ValueKey('detail-skeleton-chapters'),
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 4,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: AppSpacing.sm),
                        itemBuilder: (_, __) => SizedBox(
                          width: 140,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: muted,
                              borderRadius: AppRadius.brMd,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Bone extends StatelessWidget {
  const _Bone({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: AppRadius.brSm),
      ),
    );
  }
}
