/// Theme-derived semantic colors for JoyComic widgets.
library app_theme_context;

import 'package:flutter/material.dart';

extension AppThemeContext on BuildContext {
  ThemeData get appTheme => Theme.of(this);
  ColorScheme get colorScheme => appTheme.colorScheme;
  TextTheme get textTheme => appTheme.textTheme;

  Color get pageBackground => appTheme.scaffoldBackgroundColor;
  Color get surfaceColor => colorScheme.surface;
  Color get elevatedSurfaceColor => colorScheme.surfaceContainerHighest;
  Color get primaryTextColor => colorScheme.onSurface;
  Color get secondaryTextColor => colorScheme.onSurfaceVariant;
  Color get tertiaryTextColor =>
      colorScheme.onSurfaceVariant.withValues(alpha: 0.72);
  Color get disabledTextColor => colorScheme.onSurface.withValues(alpha: 0.38);
  Color get borderColor => colorScheme.outlineVariant;
  Color get dividerColor => appTheme.dividerColor;
}
