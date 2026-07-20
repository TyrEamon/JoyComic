/// Pure geometry for the immersive detail hero.
///
/// Shared by [HeroHeader] and [DetailLoadingSkeleton] so loading and success
/// layouts share the same cover seam, title band and metadata origin.
library;

import '../../../theme/app_spacing.dart';

/// Immutable hero layout metrics computed from layout width and app-bar inset.
class DetailHeroGeometry {
  const DetailHeroGeometry({
    required this.layoutWidth,
    required this.coverWidth,
    required this.coverHeight,
    required this.coverTop,
    required this.coverBottom,
    required this.surfaceTop,
    required this.backdropHeight,
    required this.totalHeight,
    required this.appBarReserved,
    required this.titleBandTop,
    required this.titleBandBottom,
    required this.titleBandHeight,
    required this.metadataTop,
    required this.sectionSpacing,
  });

  final double layoutWidth;
  final double coverWidth;
  final double coverHeight;
  final double coverTop;
  final double coverBottom;

  /// Content surface seam — at two-thirds of the floating cover height.
  final double surfaceTop;

  final double backdropHeight;

  /// Height of the hero stack. Ends at the cover bottom so metadata can
  /// follow immediately with only [sectionSpacing].
  final double totalHeight;

  final double appBarReserved;
  final double titleBandTop;
  final double titleBandBottom;
  final double titleBandHeight;

  /// Y origin for the first content section after the hero (metadata).
  final double metadataTop;

  final double sectionSpacing;

  /// Cover width for the given content width (phone / tablet / desktop).
  static double coverWidthFor(double layoutWidth) {
    if (layoutWidth >= 900) return 188.0;
    if (layoutWidth >= 600) return 164.0;
    return (layoutWidth * 0.34).clamp(116.0, 144.0);
  }

  /// Base backdrop height before text-scale growth.
  static double baseBackdropHeightFor(double layoutWidth) {
    return layoutWidth >= 600 ? 340.0 : 300.0;
  }

  /// Calculate hero geometry for a layout width.
  ///
  /// Fixed rule: `surfaceTop = coverTop + coverHeight * 2 / 3`.
  /// Title band is clamped into the space between the app bar and cover bottom.
  static DetailHeroGeometry calculate({
    required double layoutWidth,
    required double appBarReserved,
    double coverAspectRatio = 3 / 4,
    double textScale = 1.0,
    double sectionSpacing = AppSpacing.md,
  }) {
    final coverWidth = coverWidthFor(layoutWidth);
    final coverHeight = coverWidth / coverAspectRatio;

    // Grow backdrop slightly under large text so the title band keeps room
    // below the floating app bar without inventing arbitrary blank height.
    final scaleBoost = ((textScale - 1.0).clamp(0.0, 0.6)) * 72;
    final baseBackdrop = baseBackdropHeightFor(layoutWidth) + scaleBoost;

    // Anchor the cover under the app bar with a small gap, clamped so most of
    // the cover still sits inside the backdrop region.
    final preferredCoverTop = appBarReserved + AppSpacing.sm;
    final maxCoverTop = (baseBackdrop - coverHeight * 0.78)
        .clamp(AppSpacing.md, baseBackdrop)
        .toDouble();
    final coverTop = preferredCoverTop
        .clamp(AppSpacing.md, maxCoverTop)
        .toDouble();
    final coverBottom = coverTop + coverHeight;

    // Content surface starts at two-thirds of the cover height so the lower
    // third of the cover floats above the surface.
    final surfaceTop = coverTop + coverHeight * 2 / 3;

    // Title band: top is the app-bar floor; bottom aligns with cover bottom.
    final titleBandTop = appBarReserved;
    final rawTitleBottom = coverBottom;
    final minTitleBottom = titleBandTop + 56.0;
    final titleBandBottom = rawTitleBottom < minTitleBottom
        ? minTitleBottom
        : rawTitleBottom;
    // Never let the title band extend past the cover bottom when there is room.
    final clampedTitleBottom = titleBandBottom > coverBottom &&
            coverBottom > titleBandTop
        ? coverBottom
        : titleBandBottom;
    final titleBandHeight =
        (clampedTitleBottom - titleBandTop).clamp(56.0, 200.0).toDouble();
    final safeTitleBandBottom = titleBandTop + titleBandHeight;

    // Metadata follows the cover bottom by only the declared section spacing.
    final metadataTop = coverBottom + sectionSpacing;

    // Hero stack ends at the cover bottom — no surfaceExtra dead space.
    // Backdrop must cover at least up to the surface seam.
    final backdropHeight =
        baseBackdrop < surfaceTop + 24 ? surfaceTop + 24 : baseBackdrop;
    final totalHeight = coverBottom;

    return DetailHeroGeometry(
      layoutWidth: layoutWidth,
      coverWidth: coverWidth,
      coverHeight: coverHeight,
      coverTop: coverTop,
      coverBottom: coverBottom,
      surfaceTop: surfaceTop,
      backdropHeight: backdropHeight,
      totalHeight: totalHeight,
      appBarReserved: appBarReserved,
      titleBandTop: titleBandTop,
      titleBandBottom: safeTitleBandBottom,
      titleBandHeight: titleBandHeight,
      metadataTop: metadataTop,
      sectionSpacing: sectionSpacing,
    );
  }
}
