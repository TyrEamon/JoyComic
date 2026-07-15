/// JoyComic Warm Paper + Coral color schemes.
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color lightBackground = Color(0xFFF7F5F2);
  static const Color darkBackground = Color(0xFF111315);

  static const ColorScheme lightScheme = ColorScheme.light(
    primary: Color(0xFFB7463F),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFF6DEDA),
    onPrimaryContainer: Color(0xFF5A1713),
    secondary: Color(0xFF6A5E57),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEFE4DC),
    onSecondaryContainer: Color(0xFF2C251F),
    tertiary: Color(0xFFB7463F),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF6DEDA),
    onTertiaryContainer: Color(0xFF5A1713),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceDim: Color(0xFFE3DED8),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F5F2),
    surfaceContainer: Color(0xFFF0EDE8),
    surfaceContainerHigh: Color(0xFFE9E5DF),
    surfaceContainerHighest: Color(0xFFE9E5DF),
    onSurface: Color(0xFF1D1E20),
    onSurfaceVariant: Color(0xFF62666B),
    outline: Color(0xFFC9C3BB),
    outlineVariant: Color(0xFFE1DDD7),
    inverseSurface: Color(0xFF303033),
    onInverseSurface: Color(0xFFF4F0ED),
    inversePrimary: Color(0xFFF08A82),
    surfaceTint: Color(0xFFB7463F),
  );

  static const ColorScheme darkScheme = ColorScheme.dark(
    primary: Color(0xFFF08A82),
    onPrimary: Color(0xFF3B0B08),
    primaryContainer: Color(0xFF32110E),
    onPrimaryContainer: Color(0xFFFFDAD6),
    secondary: Color(0xFFD5C2B7),
    onSecondary: Color(0xFF392E28),
    secondaryContainer: Color(0xFF51453E),
    onSecondaryContainer: Color(0xFFF2DED3),
    tertiary: Color(0xFFF08A82),
    onTertiary: Color(0xFF3B0B08),
    tertiaryContainer: Color(0xFF32110E),
    onTertiaryContainer: Color(0xFFFFDAD6),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    surface: Color(0xFF191C1F),
    surfaceDim: Color(0xFF111315),
    surfaceBright: Color(0xFF30353A),
    surfaceContainerLowest: Color(0xFF0C0E10),
    surfaceContainerLow: Color(0xFF15181A),
    surfaceContainer: Color(0xFF202428),
    surfaceContainerHigh: Color(0xFF272C31),
    surfaceContainerHighest: Color(0xFF272C31),
    onSurface: Color(0xFFF2F3F4),
    onSurfaceVariant: Color(0xFFB7BDC3),
    outline: Color(0xFF60676E),
    outlineVariant: Color(0xFF2E3338),
    inverseSurface: Color(0xFFE3E2E4),
    onInverseSurface: Color(0xFF2E3033),
    inversePrimary: Color(0xFFB7463F),
    surfaceTint: Color(0xFFF08A82),
  );
}
