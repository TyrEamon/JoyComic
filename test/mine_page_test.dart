import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/database/favorites_helper.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/database/read_record_helper.dart';
import 'package:joycomic/foundation/cache_manager.dart';
import 'package:joycomic/views/mine/mine_page.dart';
import 'package:joycomic/views/settings/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'joycomic-mine-test-',
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

  setUp(() {
    JoyDatabase.instance.core.execute('DELETE FROM favorites');
    JoyDatabase.instance.core.execute('DELETE FROM read_records');
    ComicSource.sources.clear();
  });

  testWidgets('Mine shows real enabled-source accounts and persisted counts', (
    tester,
  ) async {
    final picacg = _source('picacg', '哔咔')
      ..data = <String, dynamic>{
        'account': <String>['alice@example.com', 'secret'],
        'user': <String, dynamic>{'name': 'Alice', 'level': 7, 'avatarUrl': ''},
      };
    final jm = _source('jm', '禁漫')..data = <String, dynamic>{};
    ComicSource.sources.addAll(<ComicSource>[picacg, jm]);

    FavoritesHelper().upsert(
      const FavoriteRecord(
        source: 'picacg',
        comic: 'favorite-1',
        title: 'Favorite',
        cover: '',
        author: '',
        favoritedAt: 1,
      ),
    );
    ReadRecordHelper().upsert(
      const ReadRecord(
        source: 'jm',
        comic: 'history-1',
        chapterId: 'chapter-1',
        pageNo: 2,
        updatedAt: 1,
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: MinePage()));
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.textContaining('Lv.7'), findsOneWidget);
    expect(find.text('禁漫 · 未登录'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('mine-stat-favorites'))).data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('mine-stat-history'))).data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('mine-stat-downloads'))).data,
      '0',
    );
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('Mine handles malformed account data without exposing it', (
    tester,
  ) async {
    final source = _source('broken', '测试源')
      ..data = <String, dynamic>{
        'account': <Object?>['visible-account', Object()],
        'user': <String, Object?>{
          'name': <String, String>{'unexpected': 'value'},
          'level': <String, String>{'unexpected': 'value'},
          'avatarUrl': 'javascript:alert(1)',
        },
      };
    ComicSource.sources.add(source);

    await tester.pumpWidget(const MaterialApp(home: MinePage()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('visible-account'), findsOneWidget);
    expect(find.textContaining('javascript:'), findsNothing);
  });

  testWidgets('Settings derives account status from enabled sources', (
    tester,
  ) async {
    final picacg = _source('picacg', '哔咔')
      ..data = <String, dynamic>{
        'account': <String>['alice@example.com', 'secret'],
        'user': <String, dynamic>{'name': 'Alice', 'level': 7},
      };
    final jm = _source('jm', '禁漫')..data = <String, dynamic>{};
    ComicSource.sources.addAll(<ComicSource>[picacg, jm]);

    final root = await Directory.systemTemp.createTemp(
      'joycomic-settings-cache-test-',
    );
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final cacheManager = CacheManager(
      rootDirectory: root,
      cacheDirectory: Directory('${root.path}/cache'),
      temporaryDirectory: Directory('${root.path}/temp'),
      logDirectory: Directory('${root.path}/logs'),
      downloadTemporaryDirectory: Directory('${root.path}/downloads/.temp'),
    );

    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(cacheManager: cacheManager)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alice · Lv.7'), findsOneWidget);
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('已登录 · Lv.12'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
  });
}

ComicSource _source(String key, String name) => ComicSource.named(
  name: name,
  key: key,
  filePath: 'test',
  account: const AccountConfig.named(),
);
