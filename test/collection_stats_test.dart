import 'package:flutter/material.dart';
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
    expect(stats.favoriteCoverage(2), closeTo(2 / 3, 0.0001));
  });

  test('artist and tag coverage use total favorites as the denominator', () {
    final stats = CollectionStatsSnapshot.fromRecords(
      favorites: <FavoriteRecord>[
        for (var index = 0; index < 450; index++)
          FavoriteRecord(
            source: 'jm',
            comic: '$index',
            title: 'Comic $index',
            cover: '',
            author: index < 2 ? '藤崎ひかり' : '画师 $index',
            tags: index < 12 ? const <String>['巨乳'] : const <String>[],
            favoritedAt: index,
          ),
      ],
      history: const <ReadRecord>[],
    );

    final artist = stats.artists.firstWhere(
      (value) => value.name == '藤崎ひかり',
    );
    final tag = stats.tags.firstWhere((value) => value.name == '巨乳');
    expect(artist.count, 2);
    expect(stats.favoriteCoverage(artist.count), closeTo(2 / 450, 0.0001));
    expect(tag.count, 12);
    expect(stats.favoriteCoverage(tag.count), closeTo(12 / 450, 0.0001));
  });

  testWidgets('full distribution donut renders every thin category', (
    tester,
  ) async {
    final values = <RankedStat>[
      const RankedStat('藤崎ひかり', 2),
      for (var index = 1; index < 336; index++) RankedStat('画师 $index', 1),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SizedBox.square(
            dimension: 360,
            child: DistributionDonut(
              values: values,
              selectedName: '藤崎ひかり',
              unit: '本',
              percentageTotal: 450,
              percentageLabel: '占全部收藏',
              aspectRatio: 1.32,
              radiusFactor: 0.44,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final donut = tester.widget<DistributionDonut>(
      find.byType(DistributionDonut),
    );
    final donutLayout = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(donut.radiusFactor, 0.44);
    expect(donutLayout.aspectRatio, 1.32);
    expect(1.15 / donut.aspectRatio, inInclusiveRange(0.85, 0.90));
    expect(
      (donut.radiusFactor / donut.aspectRatio) / (0.34 / 1.15),
      inInclusiveRange(1.10, 1.15),
    );
    expect(tester.widget<Text>(find.text('藤崎ひかり')).style?.fontSize, 17);
    expect(tester.widget<Text>(find.text('2 本')).style?.fontSize, 14);
    expect(tester.widget<Text>(find.text('占全部收藏 0.4%')).style?.fontSize, 12);
    expect(tester.widget<Text>(find.text('圆环份额 0.6%')).style?.fontSize, 11);
    expect(find.text('占全部收藏 0.4%'), findsOneWidget);
    expect(find.text('圆环份额 0.6%'), findsOneWidget);
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

}
