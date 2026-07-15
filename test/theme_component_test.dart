import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/theme/widgets/pill_badge.dart';
import 'package:joycomic/views/home/widgets/home_tool_bar.dart';

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
  testWidgets('home tools use one flat semantic icon treatment', (
    tester,
  ) async {
    final theme = AppTheme.light();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: HomeToolBar(
            entries: [
              ToolEntry(
                label: '最新',
                icon: Icons.new_releases_outlined,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );

    final container = tester.widget<Container>(
      find.byKey(const Key('home-tool-icon-最新')),
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.gradient, isNull);
    expect(decoration.boxShadow, anyOf(isNull, isEmpty));
    expect(decoration.color, theme.colorScheme.primaryContainer);

    final icon = tester.widget<Icon>(find.byIcon(Icons.new_releases_outlined));
    expect(icon.color, theme.colorScheme.primary);
  });
}
