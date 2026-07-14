import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/database/favorites_helper.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/database/read_record_helper.dart';
import 'package:joycomic/foundation/cache_manager.dart';
import 'package:joycomic/views/mine/mine_page.dart';
import 'package:joycomic/views/settings/settings_page.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database database;

  setUp(() {
    database = sqlite3.openInMemory();
    JoyDatabase.migrateCore(database);
    ComicSource.sources.clear();
  });

  tearDown(() {
    ComicSource.sources.clear();
    database.dispose();
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

    final favorites = FavoritesHelper(database);
    final history = ReadRecordHelper(database);
    favorites.upsert(
      const FavoriteRecord(
        source: 'picacg',
        comic: 'favorite-1',
        title: 'Favorite',
        cover: '',
        author: '',
        favoritedAt: 1,
      ),
    );
    history.upsert(
      const ReadRecord(
        source: 'jm',
        comic: 'history-1',
        chapterId: 'chapter-1',
        pageNo: 2,
        updatedAt: 1,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MinePage(
          statsLoader: () =>
              MineStats(favorites: favorites.count(), history: history.count()),
        ),
      ),
    );
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

    await tester.pumpWidget(const SizedBox.shrink());
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

    await tester.pumpWidget(
      const MaterialApp(home: MinePage(statsLoader: _emptyStats)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('visible-account'), findsOneWidget);
    expect(find.textContaining('javascript:'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
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
    final cacheManager = _ImmediateCacheManager();

    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(cacheManager: cacheManager)),
    );
    await cacheManager.calculated.future.timeout(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('Alice · Lv.7'), findsOneWidget);
    expect(find.text('未登录'), findsOneWidget);
    expect(find.text('已登录 · Lv.12'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

MineStats _emptyStats() => const MineStats();

ComicSource _source(String key, String name) => ComicSource.named(
  name: name,
  key: key,
  filePath: 'test',
  account: const AccountConfig.named(),
);

class _ImmediateCacheManager extends CacheManager {
  _ImmediateCacheManager()
    : super(
        rootDirectory: Directory.systemTemp,
        cacheDirectory: Directory.systemTemp,
        temporaryDirectory: Directory.systemTemp,
        logDirectory: Directory.systemTemp,
        downloadTemporaryDirectory: Directory.systemTemp,
      );

  final Completer<void> calculated = Completer<void>();

  @override
  Future<CacheSize> calculateSize({
    int? imageCacheBytes,
    Iterable<String> extraPaths = const <String>[],
  }) async {
    if (!calculated.isCompleted) calculated.complete();
    return const CacheSize(diskBytes: 0, imageCacheBytes: 0);
  }
}
