import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/theme/app_colors.dart';
import 'package:joycomic/theme/app_gradients.dart';
import 'package:joycomic/theme/app_semantic_colors.dart';
import 'package:joycomic/theme/app_shadows.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/theme/app_theme_context.dart';

void main() {
  test('schemes match approved Warm Paper colors', () {
    expect(AppColors.lightScheme.primary, const Color(0xFFB7463F));
    expect(AppColors.lightScheme.surface, const Color(0xFFFFFFFF));
    expect(AppColors.lightBackground, const Color(0xFFF7F5F2));
    expect(AppColors.darkScheme.primary, const Color(0xFFF08A82));
    expect(AppColors.darkScheme.surface, const Color(0xFF191C1F));
    expect(AppColors.darkBackground, const Color(0xFF111315));
  });

  test('foreground pairs satisfy WCAG contrast', () {
    const pairs = <(Color, Color)>[
      (Color(0xFF1D1E20), Color(0xFFF7F5F2)),
      (Color(0xFF62666B), Color(0xFFF7F5F2)),
      (Color(0xFFFFFFFF), Color(0xFFB7463F)),
      (Color(0xFFF2F3F4), Color(0xFF111315)),
      (Color(0xFFB7BDC3), Color(0xFF111315)),
      (Color(0xFF3B0B08), Color(0xFFF08A82)),
    ];
    for (final (foreground, background) in pairs) {
      expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
    }
  });

  test('semantic status pairs satisfy WCAG contrast', () {
    for (final colors in [AppSemanticColors.light, AppSemanticColors.dark]) {
      expect(
        _contrast(colors.onSuccess, colors.success),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(colors.onWarning, colors.warning),
        greaterThanOrEqualTo(4.5),
      );
      expect(_contrast(colors.onInfo, colors.info), greaterThanOrEqualTo(4.5));
    }
  });

  test('AppTheme installs matching semantic extensions', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();

    expect(light.extension<AppSemanticColors>(), same(AppSemanticColors.light));
    expect(dark.extension<AppSemanticColors>(), same(AppSemanticColors.dark));
    expect(light.scaffoldBackgroundColor, const Color(0xFFF7F5F2));
    expect(dark.scaffoldBackgroundColor, const Color(0xFF111315));
    expect(
      light.colorScheme.surfaceContainerHighest,
      AppSemanticColors.light.surfaceRaised,
    );
    expect(
      dark.colorScheme.surfaceContainerHighest,
      AppSemanticColors.dark.surfaceRaised,
    );
    expect(light.progressIndicatorTheme.color, light.colorScheme.primary);
    expect(dark.progressIndicatorTheme.color, dark.colorScheme.primary);
  });

  testWidgets('BuildContext exposes the installed semantic colors', (
    tester,
  ) async {
    AppSemanticColors? resolved;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            resolved = context.semanticColors;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(resolved, same(AppSemanticColors.light));
  });

  test('application shadows are neutral rather than brand colored', () {
    final shadows = <BoxShadow>[
      ...AppShadows.coverElevation,
      ...AppShadows.card,
      ...AppShadows.actionBar,
    ];
    for (final shadow in shadows) {
      final argb = shadow.color.toARGB32();
      final red = (argb >> 16) & 0xff;
      final green = (argb >> 8) & 0xff;
      final blue = argb & 0xff;
      expect(red, green);
      expect(green, blue);
    }
  });

  test('only approved gradients are exposed', () {
    final light = AppSemanticColors.light;
    expect(AppGradients.imageScrimBottom(light), isA<LinearGradient>());
    expect(AppGradients.readerScrimTop(light), isA<LinearGradient>());
    expect(AppGradients.shimmer(light), isA<LinearGradient>());
  });
}

double _contrast(Color a, Color b) {
  final aLum = a.computeLuminance();
  final bLum = b.computeLuminance();
  final lighter = aLum > bLum ? aLum : bLum;
  final darker = aLum > bLum ? bLum : aLum;
  return (lighter + 0.05) / (darker + 0.05);
}
