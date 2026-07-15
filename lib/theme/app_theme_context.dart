/// Theme-derived semantic colors for JoyComic widgets.
library;

import 'package:flutter/material.dart';

import 'app_semantic_colors.dart';

extension AppThemeContext on BuildContext {
  ThemeData get appTheme => Theme.of(this);
  ColorScheme get colorScheme => appTheme.colorScheme;
  TextTheme get textTheme => appTheme.textTheme;

  AppSemanticColors get semanticColors {
    final colors = appTheme.extension<AppSemanticColors>();
    return colors ?? AppSemanticColors.fallback(colorScheme.brightness);
  }

  Color get pageBackground => appTheme.scaffoldBackgroundColor;
  Color get surfaceColor => colorScheme.surface;
  Color get elevatedSurfaceColor => semanticColors.surfaceRaised;
  Color get primaryTextColor => colorScheme.onSurface;
  Color get secondaryTextColor => colorScheme.onSurfaceVariant;
  Color get tertiaryTextColor =>
      colorScheme.onSurfaceVariant.withValues(alpha: 0.72);
  Color get disabledTextColor => colorScheme.onSurface.withValues(alpha: 0.38);
  Color get borderColor => colorScheme.outlineVariant;
  Color get dividerColor => appTheme.dividerColor;
  Color get successColor => semanticColors.success;
  Color get warningColor => semanticColors.warning;
  Color get infoColor => semanticColors.info;
  Color get ratingColor => semanticColors.rating;
  Color get onImageColor => semanticColors.onImage;
}
