import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/theme/widgets/pill_badge.dart';

void main() {
  testWidgets('PillBadge uses a flat semantic container without glow', (
    tester,
  ) async {
    final theme = AppTheme.light();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: PillBadge(label: '热门')),
      ),
    );

    final box = tester.widget<DecoratedBox>(
      find.byKey(const Key('pill-badge-decoration')),
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.gradient, isNull);
    expect(decoration.boxShadow, anyOf(isNull, isEmpty));
    expect(decoration.color, theme.colorScheme.primaryContainer);

    final text = tester.widget<Text>(find.text('热门'));
    expect(text.style?.color, theme.colorScheme.onPrimaryContainer);
  });
}
