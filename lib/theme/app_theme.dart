/// JoyComic 主题组装。
///
/// 提供深色与亮色双主题。切换由 `AppData.enableDarkMode` 控制，
/// 亮色模式使用 [AppColors.lightScheme] 及配套亮色 token。
library;

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  /// 深色主题。
  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
      primary: AppColors.brandPink,
      onPrimary: Colors.white,
      secondary: AppColors.brandViolet,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textHigh,
      error: AppColors.danger,
      onError: Colors.white,
    );

    return _build(scheme, Brightness.dark);
  }

  /// 亮色主题。
  static ThemeData light() {
    final scheme = AppColors.lightScheme;
    return _build(scheme, Brightness.light);
  }

  static ThemeData _build(ColorScheme scheme, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.background : AppColors.lightBackground;
    final surface = isDark ? AppColors.surface : AppColors.lightSurface;
    final surfaceElevated = isDark
        ? AppColors.surfaceElevated
        : AppColors.lightSurfaceElevated;
    final textHigh = isDark ? AppColors.textHigh : AppColors.lightTextHigh;
    final divider = isDark ? AppColors.divider : AppColors.lightDivider;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      brightness: brightness,
      fontFamily: kFontFamily,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: textHigh,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textHigh,
        ),
        iconTheme: IconThemeData(color: textHigh, size: 22),
      ),
      iconTheme: IconThemeData(color: textHigh, size: 22),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceElevated,
        border: const OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.brandPink,
        linearTrackColor: surfaceElevated,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceElevated,
        contentTextStyle: TextStyle(color: textHigh),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppColors.brandPink,
        selectionColor: Color(0x66FF7BA9),
        selectionHandleColor: AppColors.brandPink,
      ),
    );
  }
}
