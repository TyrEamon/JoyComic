/// Loading skeleton matching the immersive hero/content geometry.
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import 'detail_hero_geometry.dart';

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
        final mediaPadding = MediaQuery.paddingOf(context);
        final appBarReserved = mediaPadding.top + 52 + AppSpacing.sm;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final geometry = DetailHeroGeometry.calculate(
          layoutWidth: width,
          appBarReserved: appBarReserved,
          textScale: textScale,
          sectionSpacing: AppSpacing.md,
        );

        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('detail-skeleton-hero'),
                height: geometry.totalHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: geometry.backdropHeight,
                      child: ColoredBox(color: elevated),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: geometry.surfaceTop,
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
                      top: geometry.coverTop,
                      width: geometry.coverWidth,
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
                      left: AppSpacing.md + geometry.coverWidth + AppSpacing.md,
                      right: AppSpacing.md,
                      top: geometry.titleBandTop,
                      height: geometry.titleBandHeight,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Bone(
                              width: width * 0.42,
                              height: 22,
                              color: muted,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            _Bone(
                              width: width * 0.28,
                              height: 14,
                              color: muted,
                            ),
                          ],
                        ),
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
                    SizedBox(height: geometry.sectionSpacing),
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
