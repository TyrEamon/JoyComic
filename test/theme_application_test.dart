import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/foundation/reader_config.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/views/auth/login_page.dart';
import 'package:joycomic/views/home/home_page.dart';
import 'package:joycomic/views/image_search/image_search_page.dart';
import 'package:joycomic/views/ranking/ranking_page.dart';
import 'package:joycomic/views/search/search_page.dart';
import 'package:joycomic/views/search/temp_search_page.dart';
import 'package:joycomic/views/video/video_page.dart';
import 'package:joycomic/views/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'joycomic-theme-test-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (_) async => databaseDirectory.path,
        );
    await JoyDatabase.instance.initialize();
  });

  tearDownAll(() async {
    await JoyDatabase.instance.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (databaseDirectory.existsSync()) {
      databaseDirectory.deleteSync(recursive: true);
    }
  });

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

  final remainingPages = <_PageCase>[
    const _PageCase('login', LoginPage(), '注册账号'),
    const _PageCase('image search', ImageSearchPage(), '以图搜图'),
    const _PageCase('ranking', RankingPage(), '排行榜'),
    const _PageCase('search', SearchPage(), '搜索历史'),
    const _PageCase(
      'temporary search',
      TempSearchPage(sourceKey: 'jm'),
      '输入关键词后搜索',
    ),
    const _PageCase('video', VideoPage(), '影视'),
  ];

  for (final pageCase in remainingPages) {
    testWidgets('${pageCase.name} follows readable light/dark themes', (
      tester,
    ) async {
      final lightTheme = AppTheme.light();
      final darkTheme = AppTheme.dark();
      final light = await _renderPage(
        tester,
        theme: lightTheme,
        page: pageCase.page,
        text: pageCase.text,
      );
      final dark = await _renderPage(
        tester,
        theme: darkTheme,
        page: pageCase.page,
        text: pageCase.text,
      );

      expect(light.background, lightTheme.scaffoldBackgroundColor);
      expect(dark.background, darkTheme.scaffoldBackgroundColor);
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

  test('discovery pages contain no decorative gradients', () {
    const paths = <String>[
      'lib/views/search/search_page.dart',
      'lib/views/search/temp_search_page.dart',
      'lib/views/ranking/ranking_page.dart',
      'lib/views/category/category_page.dart',
      'lib/views/common/source_content_page.dart',
      'lib/views/image_search/image_search_page.dart',
      'lib/views/video/video_page.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('LinearGradient(')), reason: path);
    }
  });

  test('remaining feature pages contain no fixed dark semantic colors', () {
    const paths = <String>[
      'lib/views/auth/login_page.dart',
      'lib/views/image_search/image_search_page.dart',
      'lib/views/ranking/ranking_page.dart',
      'lib/views/search/search_page.dart',
      'lib/views/search/temp_search_page.dart',
      'lib/views/video/video_page.dart',
    ];
    final fixedDark = RegExp(
      r'AppColors\.(background|surface|surfaceElevated|textHigh|textMedium|textLow|textDisabled|border|divider)|Color\(0xFF(?:0E0B14|1B1622|2F2740|8A8298)\)',
    );

    for (final path in paths) {
      expect(
        File(path).readAsStringSync(),
        isNot(matches(fixedDark)),
        reason: '$path must use Theme.of(context)',
      );
    }
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

class _PageCase {
  const _PageCase(this.name, this.page, this.text);

  final String name;
  final Widget page;
  final String text;
}
