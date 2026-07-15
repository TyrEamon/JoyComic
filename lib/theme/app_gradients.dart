import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';

class AppGradients {
  AppGradients._();

  static LinearGradient imageScrimBottom(AppSemanticColors colors) =>
      LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          colors.imageScrimStrong,
          colors.imageScrimSoft,
          colors.imageScrimClear,
        ],
      );

  static LinearGradient imageScrimTop(AppSemanticColors colors) =>
      LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [colors.imageScrimSoft, colors.imageScrimClear],
      );

  static LinearGradient readerScrimTop(AppSemanticColors colors) =>
      LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [colors.readerScrimStrong, colors.imageScrimClear],
      );

  static LinearGradient readerScrimBottom(AppSemanticColors colors) =>
      LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [colors.readerScrimStrong, colors.imageScrimClear],
      );

  static LinearGradient shimmer(AppSemanticColors colors) => LinearGradient(
    colors: [colors.shimmerBase, colors.shimmerHighlight, colors.shimmerBase],
    stops: const [0.1, 0.5, 0.9],
  );
}
