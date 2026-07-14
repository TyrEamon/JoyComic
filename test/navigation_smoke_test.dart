import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

    const routes = <String, _RouteExpectation>{
      '最新': _RouteExpectation('/ranking', '排行榜'),
      '热门排行': _RouteExpectation('/ranking', '排行榜'),
      '影视': _RouteExpectation('/video', '影视'),
      '以图搜图': _RouteExpectation('/image-search', '以图搜图'),
      '收藏库': _RouteExpectation('/favorites', '收藏'),
      '下载': _RouteExpectation('/download', '下载'),
    };
    for (final entry in routes.entries) {
      await _goHome(tester);
      await _tapAndExpectRoute(tester, entry.key, entry.value);
    }

    await _goHome(tester);
    await _pumpUntilHitTestable(tester, find.byIcon(Icons.search).first);
    await tester.tap(find.byIcon(Icons.search).hitTestable().first);
    await _expectCurrentRoute(
      tester,
      const _RouteExpectation('/search', '搜索历史'),
    );
  });

  testWidgets('all visible Mine and Settings menus navigate to real routes', (
    tester,
  ) async {
    await _pumpRouter(tester);

    const mineRoutes = <String, _RouteExpectation>{
      '历史记录': _RouteExpectation('/history', '暂无阅读历史'),
      '下载管理': _RouteExpectation('/download', '下载'),
      '我的收藏': _RouteExpectation('/favorites', '收藏'),
      '源管理 / 登录': _RouteExpectation('/login', '登录'),
      '阅读设置': _RouteExpectation('/settings/reader', '阅读设置'),
      '应用设置': _RouteExpectation('/settings', '设置'),
      '关于': _RouteExpectation('/about', '关于 JoyComic'),
    };
    for (final entry in mineRoutes.entries) {
      await _goHome(tester);
      await _pumpUntilHitTestable(tester, find.text('我的'));
      await tester.tap(find.text('我的').hitTestable());
      await _pumpUntilHitTestable(tester, find.text('源管理 / 登录'));
      await _tapAndExpectRoute(tester, entry.key, entry.value);
    }

    const settingsRoutes = <String, _RouteExpectation>{
      '禁漫': _RouteExpectation('/login', '登录'),
      '测速选源': _RouteExpectation('/settings/source', '禁漫图床测速'),
      '阅读设置': _RouteExpectation('/settings/reader', '阅读设置'),
      'WebDAV 同步': _RouteExpectation('/webdav', 'WebDAV 同步'),
      '开源说明': _RouteExpectation('/about', '关于 JoyComic'),
      '诊断日志': _RouteExpectation('/logs', '诊断日志'),
    };
    for (final entry in settingsRoutes.entries) {
      appRouter.go('/settings');
      await _expectCurrentRoute(
        tester,
        const _RouteExpectation('/settings', '设置'),
      );
      await _tapAndExpectRoute(tester, entry.key, entry.value);
    }
  });

  testWidgets('unknown routes render an explicit 404 with a home action', (
    tester,
  ) async {
    appRouter.go('/missing/task-10?from=test');
    await _pumpRouter(tester);

    expect(_currentPath(), '/missing/task-10');
    expect(find.text('页面不存在'), findsOneWidget);
    expect(find.textContaining('/missing/task-10'), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);

    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();
    expect(_currentPath(), '/');
    expect(find.text('我的'), findsOneWidget);
    _expectNoFunctionalPlaceholder();
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

      final emptyExpressionImplementation = RegExp(
        r'(?:\b(?:void|Future<void>)\s+[A-Za-z_]\w*\s*\([^;{}]*\)'
        r'|on(?:Tap|Pressed|Action):\s*\([^)]*\))'
        r'\s*(?:async\s*)?=>\s*null\s*;',
        multiLine: true,
      );
      for (final forbidden in <Pattern>[
        '_PlaceholderPage',
        '功能待集成',
        '当前全 mock',
        'current mock',
        '/search/all',
        'demoData',
        RegExp(r'\b[A-Za-z_]\w*Stub\w*\b|\bStub\b'),
        RegExp(r'on(?:Tap|Pressed|Action):\s*\(\)\s*\{\s*\}'),
        emptyExpressionImplementation,
      ]) {
        expect(source, isNot(contains(forbidden)), reason: 'found $forbidden');
      }
      expect(
        emptyExpressionImplementation.hasMatch('void save() => null;'),
        isTrue,
      );
      expect(
        emptyExpressionImplementation.hasMatch('onPressed: () => null;'),
        isTrue,
      );
      expect(
        emptyExpressionImplementation.hasMatch('String? optional() => null;'),
        isFalse,
      );
      expect(
        File('lib/views/detail/detail_demo_data.dart').existsSync(),
        isFalse,
      );
    },
  );
}

class _RouteExpectation {
  const _RouteExpectation(this.path, this.targetText);

  final String path;
  final String targetText;
}

String _currentPath() {
  final configuration = appRouter.routerDelegate.currentConfiguration;
  if (configuration.matches.isNotEmpty) {
    final lastMatch = configuration.matches.last;
    if (lastMatch is ImperativeRouteMatch) {
      return lastMatch.matches.uri.path;
    }
  }
  return configuration.uri.path;
}

Future<void> _pumpRouter(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 20));
}

Future<void> _goHome(WidgetTester tester) async {
  appRouter.go('/');
  await _expectCurrentRoute(tester, const _RouteExpectation('/', '我的'));
}

Future<void> _tapAndExpectRoute(
  WidgetTester tester,
  String label,
  _RouteExpectation expectation,
) async {
  final finder = find.text(label).first;
  await tester.ensureVisible(finder);
  await _pumpUntilHitTestable(tester, finder);
  await tester.tap(finder.hitTestable().last);
  await _expectCurrentRoute(tester, expectation);
}

Future<void> _expectCurrentRoute(
  WidgetTester tester,
  _RouteExpectation expectation,
) async {
  final target = find.text(expectation.targetText);
  final visibleTarget = target.hitTestable();
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (_currentPath() == expectation.path &&
        visibleTarget.evaluate().isNotEmpty &&
        find.text('页面不存在').evaluate().isEmpty) {
      expect(visibleTarget, findsWidgets);
      _expectNoFunctionalPlaceholder();
      return;
    }
  }
  expect(_currentPath(), expectation.path);
  expect(visibleTarget, findsWidgets);
  _expectNoFunctionalPlaceholder();
}

Future<void> _pumpUntilHitTestable(WidgetTester tester, Finder finder) async {
  final hitTestable = finder.hitTestable();
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (hitTestable.evaluate().isNotEmpty) return;
  }
  expect(hitTestable, findsWidgets);
}

void _expectNoFunctionalPlaceholder() {
  expect(find.text('功能待集成'), findsNothing);
  expect(find.text('页面不存在'), findsNothing);
}
