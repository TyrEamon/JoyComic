import 'dart:math' as math;

double? calculateDetailRating({int? views, int? likes, double? sourceRating}) {
  if (sourceRating != null) {
    return sourceRating.clamp(0.0, 10.0).toDouble();
  }

  final positiveViews = views != null && views > 0 ? views : 0;
  final positiveLikes = likes != null && likes > 0 ? likes : 0;
  if (positiveViews == 0 && positiveLikes == 0) return null;

  if (positiveViews > 0) {
    final engagement = (positiveLikes / positiveViews).clamp(0.0, 0.20) / 0.20;
    final popularity =
        (math.log(1 + positiveViews + positiveLikes * 10) /
                math.log(1 + 10000000))
            .clamp(0.0, 1.0);
    return (5.5 + 2.8 * math.sqrt(engagement) + 1.5 * popularity)
        .clamp(5.5, 9.8)
        .toDouble();
  }

  final popularity = (math.log(1 + positiveLikes) / math.log(1 + 100000)).clamp(
    0.0,
    1.0,
  );
  return (5.8 + 3.0 * popularity).clamp(5.5, 9.8).toDouble();
}
