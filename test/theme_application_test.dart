import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/foundation/reader_config.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/views/home/home_page.dart';
import 'package:joycomic/views/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ReaderConf.instance.inject(await SharedPreferences.getInstance());
    ComicSource.sources.clear();
  });

  testWidgets(
    'settings background and text follow readable light/dark themes',
    (tester) async {
      final light = await _renderPage(
        tester,
        theme: AppTheme.light(),
        page: const SettingsPage(),
        text: '源管理',
      );
      final dark = await _renderPage(
        tester,
        theme: AppTheme.dark(),
        page: const SettingsPage(),
        text: '源管理',
      );

      expect(light.background, isNot(dark.background));
      expect(light.foreground, isNot(dark.foreground));
      expect(
        _contrast(light.foreground, light.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(dark.foreground, dark.background),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  testWidgets('home background and empty-state text follow light/dark themes', (
    tester,
  ) async {
    final light = await _renderPage(
      tester,
      theme: AppTheme.light(),
      page: const HomePage(),
      text: '暂无首页内容',
      settle: true,
    );
    final dark = await _renderPage(
      tester,
      theme: AppTheme.dark(),
      page: const HomePage(),
      text: '暂无首页内容',
      settle: true,
    );

    expect(light.background, isNot(dark.background));
    expect(light.foreground, isNot(dark.foreground));
    expect(
      _contrast(light.foreground, light.background),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(dark.foreground, dark.background),
      greaterThanOrEqualTo(4.5),
    );
  });
}

Future<({Color background, Color foreground})> _renderPage(
  WidgetTester tester, {
  required ThemeData theme,
  required Widget page,
  required String text,
  bool settle = false,
}) async {
  await tester.pumpWidget(MaterialApp(theme: theme, home: page));
  await tester.pumpAndSettle();
  final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text).first);
  return (
    background: scaffold.backgroundColor ?? theme.scaffoldBackgroundColor,
    foreground: paragraph.text.style?.color ?? theme.colorScheme.onSurface,
  );
}

double _contrast(Color a, Color b) {
  final aLum = a.computeLuminance();
  final bLum = b.computeLuminance();
  final lighter = aLum > bLum ? aLum : bLum;
  final darker = aLum > bLum ? bLum : aLum;
  return (lighter + 0.05) / (darker + 0.05);
}
