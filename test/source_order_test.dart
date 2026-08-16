import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/foundation/app_data.dart';
import 'package:joycomic/views/settings/source_manager_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory dataDirectory;

  ComicSource source(String key, String name) => ComicSource.named(
    name: name,
    key: key,
    filePath: 'test',
  );

  setUp(() {
    dataDirectory = Directory.systemTemp.createTempSync('joycomic-source-order');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          pathProviderChannel,
          (call) async => dataDirectory.path,
        );
    ComicSource.sources.clear();
    ComicSource.builtInMap
      ..clear()
      ..addAll(<String, ComicSource Function()>{
        'picacg': () => source('picacg', '哔咔'),
        'jm': () => source('jm', '禁漫'),
      });
  });

  tearDown(() {
    ComicSource.sources.clear();
    ComicSource.builtInMap.clear();
    ComicSource.dataPathProvider = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    dataDirectory.deleteSync(recursive: true);
  });

  Future<void> initializeAppData(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    await AppData.instance.init();
  }

  test('default source order puts JM before enabled Pica', () async {
    await initializeAppData(<String, Object>{
      'enabledSources': <String>['picacg', 'jm'],
    });

    expect(AppData.instance.sourceOrder, <String>['jm', 'picacg']);
    expect(AppData.instance.orderedEnabledSources, <String>['jm', 'picacg']);
  });

  test('source initialization follows the supplied preference order', () async {
    ComicSource.dataPathProvider = () => dataDirectory.path;

    await ComicSource.init(<String>['jm', 'picacg']);

    expect(ComicSource.sources.map((source) => source.key), <String>[
      'jm',
      'picacg',
    ]);
  });

  testWidgets('source manager persists dragging and reorders runtime sources', (
    tester,
  ) async {
    await initializeAppData(<String, Object>{
      'enabledSources': <String>['picacg', 'jm'],
      'sourceOrder': <String>['jm', 'picacg'],
    });
    ComicSource.sources.addAll(<ComicSource>[
      source('jm', '禁漫'),
      source('picacg', '哔咔'),
    ]);

    await tester.pumpWidget(const MaterialApp(home: SourceManagerPage()));

    expect(
      tester.getTopLeft(find.text('禁漫')).dy,
      lessThan(tester.getTopLeft(find.text('哔咔')).dy),
    );
    expect(find.text('已启用 · 首页优先'), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(2));

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorderItem!(0, 1);
    await tester.pumpAndSettle();

    expect(AppData.instance.prefs.getStringList('sourceOrder'), <String>[
      'picacg',
      'jm',
    ]);
    expect(ComicSource.sources.map((source) => source.key), <String>[
      'picacg',
      'jm',
    ]);
    expect(
      tester.getTopLeft(find.text('哔咔')).dy,
      lessThan(tester.getTopLeft(find.text('禁漫')).dy),
    );
  });
}
