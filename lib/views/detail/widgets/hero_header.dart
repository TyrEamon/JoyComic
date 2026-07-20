/// Immersive cover header with backdrop, content-surface seam, and floating cover.
library;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_gradients.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import '../../common/widgets/comic_cover.dart';
import '../../common/widgets/rating_stars.dart';

class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.title,
    required this.subTitle,
    required this.backgroundCover,
    required this.frontCover,
    required this.rating,
    required this.tags,
    this.coverHeaders,
  });

  final String title;
  final String? subTitle;
  final String? backgroundCover;
  final String? frontCover;
  final double? rating;
  final List<String> tags;
  final Map<String, dynamic>? coverHeaders;

  /// Parallax distance cap; backdrop overscan must cover this fully.
  static const double maxParallax = 48;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final scrollOffset = constraints.scrollOffset;
        return SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth;
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final coverWidth = width >= 900
                  ? 188.0
                  : width >= 600
                  ? 164.0
                  : (width * 0.34).clamp(116.0, 144.0);
              final baseBackdrop = width >= 600 ? 340.0 : 300.0;
              // Grow the hero slightly under large text scale so the title band
              // keeps a safe gap below the floating app bar.
              final scaleBoost = ((textScale - 1.0).clamp(0.0, 0.6)) * 72;
              final backdropHeight = baseBackdrop + scaleBoost;
              final seamTop = backdropHeight - 34;
              final surfaceExtra = width >= 600 ? 190.0 : 170.0;
              final totalHeight = backdropHeight + surfaceExtra;

              final mediaPadding = MediaQuery.paddingOf(context);
              final appBarReserved = mediaPadding.top + 52 + AppSpacing.sm;
              final titleBandTop = appBarReserved;
              final titleBandBottom = seamTop - AppSpacing.sm;
              final titleBandHeight = (titleBandBottom - titleBandTop).clamp(
                56.0,
                200.0,
              );

              return SizedBox(
                height: totalHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      key: const ValueKey('detail-hero-backdrop'),
                      left: 0,
                      right: 0,
                      top: 0,
                      height: backdropHeight,
                      child: _HeroBackdrop(
                        imageUrl: backgroundCover ?? frontCover,
                        headers: coverHeaders,
                        scrollOffset: scrollOffset,
                      ),
                    ),
                    Positioned(
                      key: const ValueKey('detail-hero-surface'),
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
                      key: const ValueKey('detail-floating-cover'),
                      left: AppSpacing.md,
                      top: seamTop - coverWidth * 0.56,
                      width: coverWidth,
                      child: _FloatingCoverEntrance(
                        child: ComicCover(
                          url: frontCover,
                          width: coverWidth,
                          headers: coverHeaders,
                        ),
                      ),
                    ),
                    Positioned(
                      key: const ValueKey('detail-hero-title-band'),
                      left: AppSpacing.md + coverWidth + AppSpacing.md,
                      right: AppSpacing.md,
                      top: titleBandTop,
                      height: titleBandHeight,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: _HeroTitle(
                          title: title,
                          subTitle: subTitle,
                          tags: tags,
                          maxHeight: titleBandHeight,
                        ),
                      ),
                    ),
                    if (rating != null)
                      Positioned(
                        left: AppSpacing.md + coverWidth + AppSpacing.md,
                        right: AppSpacing.md,
                        top: seamTop + AppSpacing.lg,
                        child: _HeroRating(rating: rating!),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({
    required this.imageUrl,
    required this.headers,
    required this.scrollOffset,
  });

  final String? imageUrl;
  final Map<String, dynamic>? headers;
  final double scrollOffset;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final parallaxY = disableMotion
        ? 0.0
        : (scrollOffset * 0.12).clamp(0.0, HeroHeader.maxParallax);
    // Overscan the image so a positive Y translation never uncovers the top.
    final overscan = HeroHeader.maxParallax + 8;
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: -overscan,
          bottom: -overscan,
          child: Transform.translate(
            offset: Offset(0, parallaxY),
            child: CachedNetworkImage(
              imageUrl: imageUrl ?? '',
              httpHeaders: headers?.cast<String, String>(),
              fit: BoxFit.cover,
              alignment: Alignment.center,
              placeholder: (_, __) => ColoredBox(
                color: context.elevatedSurfaceColor,
                child: const SizedBox.expand(),
              ),
              errorBuilder: (_, __, ___) => ColoredBox(
                color: context.elevatedSurfaceColor,
                child: const Center(child: Icon(Icons.menu_book_rounded)),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 120,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.imageScrimTop(context.semanticColors),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 180,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.imageScrimBottom(context.semanticColors),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({
    required this.title,
    required this.subTitle,
    required this.tags,
    required this.maxHeight,
  });

  final String title;
  final String? subTitle;
  final List<String> tags;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final onImage = context.onImageColor;
    final compact = maxHeight < 96;
    final titleLines = compact ? 1 : 2;
    final showSubtitle =
        !compact && subTitle != null && subTitle!.trim().isNotEmpty;
    final showTags = maxHeight >= 120 && tags.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              title,
              maxLines: titleLines,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.hero(context).copyWith(color: onImage),
            ),
            if (showSubtitle) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.subtitle(
                  context,
                ).copyWith(color: onImage.withValues(alpha: 0.82)),
              ),
            ],
            if (showTags) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final tag in tags.take(compact ? 2 : 4))
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: context.semanticColors.imageScrimSoft,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: onImage.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        child: Text(
                          tag,
                          style: AppTypography.meta(
                            context,
                          ).copyWith(color: onImage, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroRating extends StatelessWidget {
  const _HeroRating({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          rating.toStringAsFixed(1),
          style: AppTypography.ratingNumber(context),
        ),
        const SizedBox(width: AppSpacing.xs),
        RatingStars(rating: rating / 2, size: 16),
      ],
    );
  }
}

class _FloatingCoverEntrance extends StatelessWidget {
  const _FloatingCoverEntrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    if (disableMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
