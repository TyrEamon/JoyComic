import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/database/favorites_helper.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/database/read_record_helper.dart';
import 'package:joycomic/views/stats/collection_stats.dart';
import 'package:joycomic/views/stats/stats_page.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('collection stats deduplicate authors and tags per favorite', () {
    const favorites = <FavoriteRecord>[
      FavoriteRecord(
        source: 'jm',
        comic: '1',
        title: 'One',
        cover: '',
        author: 'Hisasi',
        authors: <String>['Hisasi', 'Hisasi'],
        tags: <String>['纯爱', '校园', '纯爱'],
        metadataComplete: true,
        favoritedAt: 1,
      ),
      FavoriteRecord(
        source: 'jm',
        comic: '2',
        title: 'Two',
        cover: '',
        author: 'Hisasi、Asanagi',
        tags: <String>['纯爱', '巨乳'],
        metadataComplete: true,
        favoritedAt: 2,
      ),
      FavoriteRecord(
        source: 'picacg',
        comic: '3',
        title: 'Three',
        cover: '',
        author: '未知',
        favoritedAt: 3,
      ),
    ];
    const history = <ReadRecord>[
      ReadRecord(
        source: 'jm',
        comic: '2',
        chapterId: 'chapter',
        pageNo: 0,
        updatedAt: 1,
      ),
    ];

    final stats = CollectionStatsSnapshot.fromRecords(
      favorites: favorites,
      history: history,
    );

    expect(stats.totalFavorites, 3);
    expect(stats.read, 1);
    expect(stats.unread, 2);
    expect(stats.metadataComplete, 2);
    expect(stats.artists.map((item) => (item.name, item.count)), <Object?>[
      ('Hisasi', 2),
      ('Asanagi', 1),
    ]);
    expect(stats.tags.first.name, '纯爱');
    expect(stats.tags.first.count, 2);
    expect(stats.tagOccurrences, 4);
  });

  test('favorite metadata survives SQLite round trip', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    JoyDatabase.migrateCore(database);
    final helper = FavoritesHelper(database);
    helper.upsert(
      const FavoriteRecord(
        source: 'jm',
        comic: '9',
        title: 'Title',
        cover: 'cover',
        author: 'A、B',
        authors: <String>['A', 'B'],
        tags: <String>['Tag 1', 'Tag 2'],
        metadataComplete: true,
        favoritedAt: 9,
      ),
    );

    final restored = helper.get('jm', '9')!;
    expect(restored.authors, <String>['A', 'B']);
    expect(restored.tags, <String>['Tag 1', 'Tag 2']);
    expect(restored.metadataComplete, isTrue);
  });

  test('distribution collapses the tail into other', () {
    final values = <RankedStat>[
      for (var index = 0; index < 10; index)
        RankedStat('item-$index', 10 - index),
    ];
    final collapsed = collapseDistribution(values, limit: 3);
    expect(collapsed.map((item) => item.name), <String>[
      'item-0',
      'item-1',
      'item-2',
      '其他',
    ]);
    expect(collapsed.last.count, 28);
  });

  test('routes and both discoverable entries are registered', () {
    final main = File('lib/main.dart').readAsStringSync();
    final mine = File('lib/views/mine/mine_page.dart').readAsStringSync();
    final favorites = File(
      'lib/views/favorites/favorites_page.dart',
    ).readAsStringSync();

    expect(main, contains("path: '/stats'"));
    expect(main, contains("path: 'artists'"));
    expect(main, contains("path: 'tags'"));
    expect(mine, contains("label: '收藏洞察'"));
    expect(favorites, contains("tooltip: '收藏洞察'"));
  });
}
