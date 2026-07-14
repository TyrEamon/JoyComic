import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/foundation/reader_config.dart';
import 'package:joycomic/main.dart' show appRouter;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory appDirectory;

  setUpAll(() async {
    appDirectory = await Directory.systemTemp.createTemp(
      'joycomic-navigation-test-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (_) async => appDirectory.path,
        );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ReaderConf.instance.inject(await SharedPreferences.getInstance());
    await JoyDatabase.instance.initialize();
  });

  tearDownAll(() async {
    ComicSource.sources.clear();
    await JoyDatabase.instance.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (appDirectory.existsSync()) appDirectory.deleteSync(recursive: true);
  });

  setUp(() {
    ComicSource.sources
      ..clear()
      ..add(
        ComicSource.named(
          name: '禁漫',
          key: 'jm',
          filePath: 'test',
          account: const AccountConfig.named(),
        )..data = <String, dynamic>{},
      );
    appRouter.go('/');
  });

  testWidgets('all visible Home toolbar actions navigate to real routes', (
    tester,
  ) async {
    await _pumpRouter(tester);

    const routes = <String, String>{
      '最新': '/ranking',
      '热门排行': '/ranking',
      '影视': '/video',
      '以图搜图': '/image-search',
      '收藏库': '/favorites',
      '下载': '/download',
    };
    for (final entry in routes.entries) {
      await _goHome(tester);
      await _tapAndExpectRoute(tester, entry.key, entry.value);
    }

    await _goHome(tester);
    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pump();
    expect(appRouter.routeInformationProvider.value.uri.path, '/search');
    _expectNoFunctionalPlaceholder();
  });

  testWidgets('all visible Mine and Settings menus navigate to real routes', (
    tester,
  ) async {
    await _pumpRouter(tester);

    const mineRoutes = <String, String>{
      '历史记录': '/history',
      '下载管理': '/download',
      '我的收藏': '/favorites',
      '源管理 / 登录': '/login',
      '阅读设置': '/settings/reader',
      '应用设置': '/settings',
      '关于': '/about',
    };
    for (final entry in mineRoutes.entries) {
      await _goHome(tester);
      await tester.tap(find.text('我的'));
      await tester.pump();
      await _tapAndExpectRoute(tester, entry.key, entry.value);
    }

    const settingsRoutes = <String, String>{
      '禁漫': '/login',
      '测速选源': '/settings/source',
      '阅读设置': '/settings/reader',
      'WebDAV 同步': '/webdav',
      '开源说明': '/about',
      '诊断日志': '/logs',
    };
    for (final entry in settingsRoutes.entries) {
      appRouter.go('/settings');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await _tapAndExpectRoute(tester, entry.key, entry.value);
    }
  });

  testWidgets('unknown routes render an explicit 404 with a home action', (
    tester,
  ) async {
    appRouter.go('/missing/task-10?from=test');
    await _pumpRouter(tester);

    expect(find.text('页面不存在'), findsOneWidget);
    expect(find.textContaining('/missing/task-10'), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);

    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/');
  });

  test(
    'functional placeholders, empty actions, demo bypass and bad search route are gone',
    () {
      final dartFiles = <File>[
        for (final root in <String>['lib'])
          ...Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart')),
      ];
      final source = dartFiles
          .map((file) => file.readAsStringSync())
          .join('\n');

      for (final forbidden in <Pattern>[
        '_PlaceholderPage',
        '功能待集成',
        '当前全 mock',
        'current mock',
        '/search/all',
        'demoData',
        RegExp(r'on(?:Tap|Pressed|Action):\s*\(\)\s*\{\s*\}'),
      ]) {
        expect(source, isNot(contains(forbidden)), reason: 'found $forbidden');
      }
      expect(
        File('lib/views/detail/detail_demo_data.dart').existsSync(),
        isFalse,
      );
    },
  );
}

Future<void> _pumpRouter(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _goHome(WidgetTester tester) async {
  appRouter.go('/');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _tapAndExpectRoute(
  WidgetTester tester,
  String label,
  String path,
) async {
  final finder = find.text(label).last;
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
  expect(appRouter.routeInformationProvider.value.uri.path, path);
  _expectNoFunctionalPlaceholder();
}

void _expectNoFunctionalPlaceholder() {
  expect(find.text('功能待集成'), findsNothing);
  expect(find.text('页面不存在'), findsNothing);
}
