import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/database/favorites_helper.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/database/read_record_helper.dart';
import 'package:joycomic/foundation/source_session_notifier.dart';
import 'package:joycomic/network/base_comic.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/views/favorites/favorites_page.dart';
import 'package:joycomic/views/history/history_page.dart';
import 'package:joycomic/views/reader/providers/reader_provider.dart';
import 'package:joycomic/views/reader/state/comic_state.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('favorites library', () {
    test('merges local and remote favorites by source and comic identity', () {
      final merged = mergeFavoriteLibraryItems(
        local: const <FavoriteLibraryItem>[
          FavoriteLibraryItem(
            sourceKey: 'jm',
            comicId: 'same',
            title: 'Local title',
            coverUrl: 'local-cover',
            author: 'Local author',
            favoritedAt: 20,
            isLocal: true,
          ),
          FavoriteLibraryItem(
            sourceKey: 'picacg',
            comicId: 'local-only',
            title: 'Offline favorite',
            coverUrl: '',
            author: '',
            favoritedAt: 10,
            isLocal: true,
          ),
        ],
        remote: const <FavoriteLibraryItem>[
          FavoriteLibraryItem(
            sourceKey: 'jm',
            comicId: 'same',
            title: 'Remote title',
            coverUrl: 'remote-cover',
            author: 'Remote author',
            isRemote: true,
          ),
          FavoriteLibraryItem(
            sourceKey: 'jm',
            comicId: 'remote-only',
            title: 'Cloud favorite',
            coverUrl: '',
            author: '',
            isRemote: true,
          ),
        ],
      );

      expect(merged, hasLength(3));
      final duplicate = merged.singleWhere((item) => item.comicId == 'same');
      expect(duplicate.title, 'Remote title');
      expect(duplicate.coverUrl, 'remote-cover');
      expect(duplicate.isLocal, isTrue);
      expect(duplicate.isRemote, isTrue);
      expect(
        merged.where((item) => item.comicId == 'local-only').single.isRemote,
        isFalse,
      );
    });

    testWidgets('loads every remote favorite page through maxPage', (
      tester,
    ) async {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      final helper = FavoritesHelper(database);
      FavoriteNotifier.instance.loadFromDb(database);
      final calls = <int>[];
      final source = ComicSource.named(
        name: 'Paged',
        key: 'paged',
        filePath: '',
        favoriteData: FavoriteData.named(
          load: (page, [folder]) async {
            calls.add(page);
            return Res<List<BaseComic>>(<BaseComic>[
              _TestComic(id: 'comic-$page', title: 'Page $page'),
            ], subData: 3);
          },
        ),
      )..data['account'] = <String>['user', 'token'];
      final previousSources = List<ComicSource>.of(ComicSource.sources);
      addTearDown(() {
        ComicSource.sources
          ..clear()
          ..addAll(previousSources);
      });
      ComicSource.sources
        ..clear()
        ..add(source);

      await tester.pumpWidget(
        MaterialApp(
          home: FavoritesPage(
            favoritesHelper: helper,
            sourcesProvider: () => <ComicSource>[source],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(calls, <int>[1, 2, 3]);
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('Page 3'), findsOneWidget);
      expect(helper.count(), 3);
    });

    testWidgets('unknown remote page limit stops when a page adds no comics', (
      tester,
    ) async {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      final helper = FavoritesHelper(database);
      FavoriteNotifier.instance.loadFromDb(database);
      final calls = <int>[];
      final source = ComicSource.named(
        name: 'Unknown pages',
        key: 'unknown-pages',
        filePath: '',
        favoriteData: FavoriteData.named(
          load: (page, [folder]) async {
            calls.add(page);
            return const Res<List<BaseComic>>(<BaseComic>[
              _TestComic(id: 'same', title: 'Same comic'),
            ]);
          },
        ),
      )..data['account'] = <String>['user', 'token'];
      final previousSources = List<ComicSource>.of(ComicSource.sources);
      addTearDown(() {
        ComicSource.sources
          ..clear()
          ..addAll(previousSources);
      });
      ComicSource.sources
        ..clear()
        ..add(source);

      await tester.pumpWidget(
        MaterialApp(
          home: FavoritesPage(
            favoritesHelper: helper,
            sourcesProvider: () => <ComicSource>[source],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(calls, <int>[1, 2]);
      expect(find.text('Same comic'), findsOneWidget);
      expect(helper.count(), 1);
    });

    testWidgets('one source page error is isolated and keeps completed pages', (
      tester,
    ) async {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      final helper = FavoritesHelper(database);
      FavoriteNotifier.instance.loadFromDb(database);
      final failedCalls = <int>[];
      final healthyCalls = <int>[];
      final failedSource = ComicSource.named(
        name: 'Partially failed',
        key: 'partially-failed',
        filePath: '',
        favoriteData: FavoriteData.named(
          load: (page, [folder]) async {
            failedCalls.add(page);
            if (page == 2) return const Res.error('page two failed');
            return const Res<List<BaseComic>>(<BaseComic>[
              _TestComic(id: 'kept', title: 'Kept page'),
            ], subData: 2);
          },
        ),
      )..data['account'] = <String>['user', 'token'];
      final healthySource = ComicSource.named(
        name: 'Healthy',
        key: 'healthy',
        filePath: '',
        favoriteData: FavoriteData.named(
          load: (page, [folder]) async {
            healthyCalls.add(page);
            return const Res<List<BaseComic>>(<BaseComic>[
              _TestComic(id: 'healthy', title: 'Healthy page'),
            ], subData: 1);
          },
        ),
      )..data['account'] = <String>['user', 'token'];
      final previousSources = List<ComicSource>.of(ComicSource.sources);
      addTearDown(() {
        ComicSource.sources
          ..clear()
          ..addAll(previousSources);
      });
      ComicSource.sources
        ..clear()
        ..addAll(<ComicSource>[failedSource, healthySource]);

      await tester.pumpWidget(
        MaterialApp(
          home: FavoritesPage(
            favoritesHelper: helper,
            sourcesProvider: () => <ComicSource>[failedSource, healthySource],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(failedCalls, <int>[1, 2]);
      expect(healthyCalls, <int>[1]);
      expect(find.text('Kept page'), findsOneWidget);
      expect(find.text('Healthy page'), findsOneWidget);
      expect(find.textContaining('Partially failed 同步失败'), findsOneWidget);
    });

    test('remote error response leaves local favorite unchanged', () async {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      final helper = FavoritesHelper(database);
      helper.upsert(
        const FavoriteRecord(
          source: 'failing-source',
          comic: 'comic-1',
          title: 'Saved title',
          cover: 'saved-cover',
          author: 'Saved author',
          favoritedAt: 10,
        ),
      );
      FavoriteNotifier.instance.loadFromDb(database);
      final revision = FavoriteNotifier.instance.revision;

      final previousSources = List<ComicSource>.of(ComicSource.sources);
      addTearDown(() {
        ComicSource.sources
          ..clear()
          ..addAll(previousSources);
      });
      ComicSource.sources
        ..clear()
        ..add(
          ComicSource.named(
            name: 'Failing',
            key: 'failing-source',
            filePath: '',
            favoriteData: FavoriteData.named(
              load: (page, [folder]) async => const Res([]),
              addOrDelFavorite: (comicId, folderId, isAdding) async =>
                  const Res.error('remote failed'),
            ),
          )..data['account'] = <String>['user', 'token'],
        );

      await expectLater(
        helper.toggleFavorite(
          sourceKey: 'failing-source',
          comicId: 'comic-1',
          title: 'Saved title',
          coverUrl: 'saved-cover',
        ),
        throwsStateError,
      );

      expect(helper.get('failing-source', 'comic-1')?.title, 'Saved title');
      expect(
        FavoriteNotifier.instance.isFavorited('failing-source', 'comic-1'),
        isTrue,
      );
      expect(FavoriteNotifier.instance.revision, revision);
    });

    testWidgets('local favorites remain visible without a logged-in source', (
      tester,
    ) async {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      final helper = FavoritesHelper(database);
      helper.upsert(
        const FavoriteRecord(
          source: 'jm',
          comic: 'offline-1',
          title: 'Offline favorite',
          cover: '',
          author: 'Author',
          favoritedAt: 10,
        ),
      );
      FavoriteNotifier.instance.loadFromDb(database);

      await tester.pumpWidget(
        MaterialApp(
          home: FavoritesPage(
            favoritesHelper: helper,
            sourcesProvider: () => const <ComicSource>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Offline favorite'), findsOneWidget);
      expect(find.textContaining('本地'), findsWidgets);
    });

    testWidgets('anonymous JM favorite opens detail without a login prompt', (
      tester,
    ) async {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      final helper = FavoritesHelper(database);
      helper.upsert(
        const FavoriteRecord(
          source: 'jm',
          comic: 'anonymous-1',
          title: '匿名可读收藏',
          cover: '',
          author: '',
          favoritedAt: 10,
        ),
      );
      FavoriteNotifier.instance.loadFromDb(database);
      final source = ComicSource.named(
        name: '禁漫',
        key: 'jm',
        filePath: 'test',
        account: const AccountConfig.named(),
      );
      final previousSources = List<ComicSource>.of(ComicSource.sources);
      addTearDown(() {
        ComicSource.sources
          ..clear()
          ..addAll(previousSources);
      });
      ComicSource.sources
        ..clear()
        ..add(source);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => FavoritesPage(
              favoritesHelper: helper,
              sourcesProvider: () => <ComicSource>[source],
            ),
          ),
          GoRoute(
            path: '/detail/:source/:id',
            builder: (context, state) => const Scaffold(body: Text('已进入漫画详情')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('匿名可读收藏'));
      await tester.pumpAndSettle();

      expect(find.text('已进入漫画详情'), findsOneWidget);
      expect(find.text('禁漫 未登录'), findsNothing);
    });

    testWidgets(
      'source login change refreshes remote favorites automatically',
      (tester) async {
        final database = sqlite3.openInMemory();
        addTearDown(database.dispose);
        JoyDatabase.migrateCore(database);
        final helper = FavoritesHelper(database);
        FavoriteNotifier.instance.loadFromDb(database);
        var remoteLoads = 0;
        final source = ComicSource.named(
          name: '禁漫',
          key: 'jm',
          filePath: 'test',
          favoriteData: FavoriteData.named(
            load: (page, [folder]) async {
              remoteLoads++;
              return const Res<List<BaseComic>>(<BaseComic>[
                _TestComic(id: 'remote-after-login', title: '登录后收藏'),
              ], subData: 1);
            },
          ),
        );
        final previousSources = List<ComicSource>.of(ComicSource.sources);
        addTearDown(() {
          ComicSource.sources
            ..clear()
            ..addAll(previousSources);
        });
        ComicSource.sources
          ..clear()
          ..add(source);

        await tester.pumpWidget(
          MaterialApp(
            home: FavoritesPage(
              favoritesHelper: helper,
              sourcesProvider: () => <ComicSource>[source],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(remoteLoads, 0);
        expect(find.textContaining('登录后可同步'), findsOneWidget);

        source.data['authenticated'] = true;
        SourceSessionNotifier.instance.notifyChanged('jm');
        await tester.pumpAndSettle();

        expect(remoteLoads, 1);
        expect(find.text('登录后收藏'), findsOneWidget);
        expect(find.textContaining('登录后可同步'), findsNothing);
      },
    );

    testWidgets('favorite revision refreshes every mounted page', (
      tester,
    ) async {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      final helper = FavoritesHelper(database);
      FavoriteNotifier.instance.loadFromDb(database);
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: <Widget>[
              FavoritesPage(
                favoritesHelper: helper,
                sourcesProvider: () => const <ComicSource>[],
              ),
              FavoritesPage(
                favoritesHelper: helper,
                sourcesProvider: () => const <ComicSource>[],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      helper.upsert(
        const FavoriteRecord(
          source: 'jm',
          comic: 'broadcast-1',
          title: 'Broadcast favorite',
          cover: '',
          author: '',
          favoritedAt: 10,
        ),
      );
      FavoriteNotifier.instance.addLocal(
        'jm',
        'broadcast-1',
        'Broadcast favorite',
        '',
      );
      await tester.pumpAndSettle();

      expect(find.text('Broadcast favorite'), findsNWidgets(2));
    });

    testWidgets(
      'remote load failure still uses remote-first removal and preserves local on failure',
      (tester) async {
        final database = sqlite3.openInMemory();
        addTearDown(database.dispose);
        JoyDatabase.migrateCore(database);
        final helper = FavoritesHelper(database);
        helper.upsert(
          const FavoriteRecord(
            source: 'remote-capable',
            comic: 'comic-1',
            title: 'Cached favorite',
            cover: '',
            author: '',
            favoritedAt: 10,
          ),
        );
        FavoriteNotifier.instance.loadFromDb(database);
        var remoteCalls = 0;
        final source = ComicSource.named(
          name: 'Remote capable',
          key: 'remote-capable',
          filePath: '',
          favoriteData: FavoriteData.named(
            load: (page, [folder]) async =>
                const Res.error('favorite load failed'),
            addOrDelFavorite: (comicId, folderId, isAdding) async {
              remoteCalls++;
              return const Res.error('remove failed');
            },
          ),
        )..data['account'] = <String>['user', 'token'];
        final previousSources = List<ComicSource>.of(ComicSource.sources);
        addTearDown(() {
          ComicSource.sources
            ..clear()
            ..addAll(previousSources);
        });
        ComicSource.sources
          ..clear()
          ..add(source);

        await tester.pumpWidget(
          MaterialApp(
            home: FavoritesPage(
              favoritesHelper: helper,
              sourcesProvider: () => <ComicSource>[source],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('取消收藏'));
        await tester.pumpAndSettle();

        expect(remoteCalls, 1);
        expect(helper.get('remote-capable', 'comic-1'), isNotNull);
        expect(
          FavoriteNotifier.instance.isFavorited('remote-capable', 'comic-1'),
          isTrue,
        );
      },
    );

    testWidgets(
      'favorite removal shows busy state and disables repeated taps',
      (tester) async {
        final database = sqlite3.openInMemory();
        addTearDown(database.dispose);
        JoyDatabase.migrateCore(database);
        final helper = FavoritesHelper(database);
        helper.upsert(
          const FavoriteRecord(
            source: 'busy-source',
            comic: 'comic-1',
            title: 'Busy favorite',
            cover: '',
            author: '',
            favoritedAt: 10,
          ),
        );
        FavoriteNotifier.instance.loadFromDb(database);

        final removeGate = Completer<Res<bool>>();
        final source = ComicSource.named(
          name: 'Busy source',
          key: 'busy-source',
          filePath: '',
          favoriteData: FavoriteData.named(
            load: (page, [folder]) async =>
                const Res.error('favorite load failed'),
            addOrDelFavorite: (comicId, folderId, isAdding) =>
                removeGate.future,
          ),
        )..data['account'] = <String>['user', 'token'];
        final previousSources = List<ComicSource>.of(ComicSource.sources);
        addTearDown(() {
          ComicSource.sources
            ..clear()
            ..addAll(previousSources);
        });
        ComicSource.sources
          ..clear()
          ..add(source);

        await tester.pumpWidget(
          MaterialApp(
            home: FavoritesPage(
              favoritesHelper: helper,
              sourcesProvider: () => <ComicSource>[source],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('取消收藏'));
        await tester.pump();

        expect(
          find.byKey(
            const ValueKey<String>('favorite-busy:busy-source:comic-1'),
          ),
          findsOneWidget,
        );
        final busyButton = tester.widget<IconButton>(
          find.ancestor(
            of: find.byKey(
              const ValueKey<String>('favorite-busy:busy-source:comic-1'),
            ),
            matching: find.byType(IconButton),
          ),
        );
        expect(busyButton.tooltip, '取消收藏中');
        expect(busyButton.onPressed, isNull);

        removeGate.complete(const Res(true));
        await tester.pumpAndSettle();
        expect(helper.get('busy-source', 'comic-1'), isNull);
      },
    );

    testWidgets(
      'remote load failure still uses remote-first removal and deletes local on success',
      (tester) async {
        final database = sqlite3.openInMemory();
        addTearDown(database.dispose);
        JoyDatabase.migrateCore(database);
        final helper = FavoritesHelper(database);
        helper.upsert(
          const FavoriteRecord(
            source: 'remote-capable',
            comic: 'comic-1',
            title: 'Cached favorite',
            cover: '',
            author: '',
            favoritedAt: 10,
          ),
        );
        FavoriteNotifier.instance.loadFromDb(database);
        var remoteCalls = 0;
        final source = ComicSource.named(
          name: 'Remote capable',
          key: 'remote-capable',
          filePath: '',
          favoriteData: FavoriteData.named(
            load: (page, [folder]) async =>
                const Res.error('favorite load failed'),
            addOrDelFavorite: (comicId, folderId, isAdding) async {
              remoteCalls++;
              return const Res(true);
            },
          ),
        )..data['account'] = <String>['user', 'token'];
        final previousSources = List<ComicSource>.of(ComicSource.sources);
        addTearDown(() {
          ComicSource.sources
            ..clear()
            ..addAll(previousSources);
        });
        ComicSource.sources
          ..clear()
          ..add(source);

        await tester.pumpWidget(
          MaterialApp(
            home: FavoritesPage(
              favoritesHelper: helper,
              sourcesProvider: () => <ComicSource>[source],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('取消收藏'));
        await tester.pumpAndSettle();

        expect(remoteCalls, 1);
        expect(helper.get('remote-capable', 'comic-1'), isNull);
        expect(
          FavoriteNotifier.instance.isFavorited('remote-capable', 'comic-1'),
          isFalse,
        );
      },
    );
  });

  group('reading history', () {
    test('history record restores chapter page and complete metadata', () {
      const record = ReadRecord(
        source: 'jm',
        comic: 'comic-9',
        title: 'History title',
        cover: 'cover-url',
        author: 'History author',
        chapterId: 'chapter-3',
        chapterTitle: '第三话',
        pageNo: 7,
        pageCount: 22,
        updatedAt: 100,
      );

      final state = ComicState.fromReadRecord(record);

      expect(state.id, 'comic-9');
      expect(state.sourceKey, 'jm');
      expect(state.title, 'History title');
      expect(state.coverUrl, 'cover-url');
      expect(state.author, 'History author');
      expect(state.chapter.id, 'chapter-3');
      expect(state.chapter.name, '第三话');
      expect(state.chapters, hasLength(1));
      expect(state.pageNo, 7);
    });

    test('history controller deletes one record and clears all records', () {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      final helper = ReadRecordHelper(database);
      for (final record in const <ReadRecord>[
        ReadRecord(
          source: 'jm',
          comic: 'older',
          title: 'Older',
          chapterId: 'c1',
          pageNo: 1,
          updatedAt: 10,
        ),
        ReadRecord(
          source: 'picacg',
          comic: 'newer',
          title: 'Newer',
          chapterId: 'c2',
          pageNo: 2,
          updatedAt: 20,
        ),
      ]) {
        helper.upsert(record);
      }

      final controller = HistoryPageController(helper);
      addTearDown(controller.dispose);
      controller.load();
      expect(controller.records.map((record) => record.comic), <String>[
        'newer',
        'older',
      ]);

      controller.delete(controller.records.first);
      expect(controller.records.single.comic, 'older');
      controller.clear();
      expect(controller.records, isEmpty);
      expect(helper.count(), 0);
    });

    testWidgets('clear history requires confirmation', (tester) async {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      final helper = ReadRecordHelper(database);
      helper.upsert(
        const ReadRecord(
          source: 'jm',
          comic: 'comic-1',
          title: 'History comic',
          chapterId: 'c1',
          chapterTitle: '第一话',
          pageNo: 3,
          pageCount: 10,
          updatedAt: 10,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: HistoryPage(readRecordHelper: helper)),
      );
      await tester.pumpAndSettle();
      expect(find.text('History comic'), findsOneWidget);

      await tester.tap(find.byTooltip('清空历史'));
      await tester.pumpAndSettle();
      expect(find.text('确认清空'), findsOneWidget);
      expect(helper.count(), 1);

      await tester.tap(find.widgetWithText(FilledButton, '清空'));
      await tester.pumpAndSettle();
      expect(helper.count(), 0);
      expect(find.text('History comic'), findsNothing);
    });
  });

  group('reader request and persistence concurrency', () {
    test(
      'stale chapter response cannot replace the latest chapter images',
      () async {
        final database = sqlite3.openInMemory();
        addTearDown(database.dispose);
        JoyDatabase.migrateCore(database);
        final helper = ReadRecordHelper(database);
        const chapterA = ReaderChapter(id: 'a', order: 1, name: 'A');
        const chapterB = ReaderChapter(id: 'b', order: 2, name: 'B');
        final loads = <String, Completer<Res<List<String>>>>{
          'a': Completer<Res<List<String>>>(),
          'b': Completer<Res<List<String>>>(),
        };
        final provider = ReaderProvider(
          state: const ComicState(
            id: 'comic-race',
            title: 'Race',
            chapters: <ReaderChapter>[chapterA, chapterB],
            chapter: chapterA,
            pageNo: 0,
            sourceKey: 'jm',
          ),
          imageLoader: (comicId, episodeKey) => loads[episodeKey]!.future,
          readRecordHelper: helper,
          readRecordDebounce: const Duration(seconds: 10),
        );
        addTearDown(provider.dispose);

        provider.go(chapterB);
        loads['b']!.complete(const Res(<String>['b-1', 'b-2']));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(provider.chapter, same(chapterB));
        expect(provider.images.map((image) => image.url), <String>[
          'b-1',
          'b-2',
        ]);

        loads['a']!.complete(const Res(<String>['a-1']));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(provider.chapter, same(chapterB));
        expect(provider.images.map((image) => image.url), <String>[
          'b-1',
          'b-2',
        ]);
      },
    );

    testWidgets('late chapter response after dispose is ignored', (
      tester,
    ) async {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      final helper = ReadRecordHelper(database);
      final load = Completer<Res<List<String>>>();
      const chapter = ReaderChapter(id: 'late', order: 1, name: 'Late');
      final provider = ReaderProvider(
        state: const ComicState(
          id: 'comic-late',
          title: 'Late',
          chapters: <ReaderChapter>[chapter],
          chapter: chapter,
          pageNo: 2,
          sourceKey: 'jm',
        ),
        imageLoader: (comicId, episodeKey) => load.future,
        readRecordHelper: helper,
        readRecordDebounce: const Duration(milliseconds: 100),
      );

      provider.dispose();
      expect(helper.get('jm', 'comic-late')?.pageCount, 0);
      load.complete(const Res(<String>['late-1', 'late-2']));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final flushed = helper.get('jm', 'comic-late');
      expect(flushed, isNotNull);
      expect(flushed!.pageNo, 2);
      expect(flushed.pageCount, 0);
    });

    testWidgets('real debounce merges rapid page saves into one write', (
      tester,
    ) async {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      database.execute('CREATE TABLE read_record_writes (value INTEGER)');
      database.execute('''
        CREATE TRIGGER count_read_record_insert
        AFTER INSERT ON read_records
        BEGIN
          INSERT INTO read_record_writes VALUES (1);
        END
      ''');
      database.execute('''
        CREATE TRIGGER count_read_record_update
        AFTER UPDATE ON read_records
        BEGIN
          INSERT INTO read_record_writes VALUES (1);
        END
      ''');
      final helper = ReadRecordHelper(database);
      const chapter = ReaderChapter(id: 'debounce', order: 1, name: 'Debounce');
      final provider = ReaderProvider(
        state: const ComicState(
          id: 'comic-debounce',
          title: 'Debounce',
          chapters: <ReaderChapter>[chapter],
          chapter: chapter,
          pageNo: 0,
          sourceKey: 'jm',
        ),
        imageLoader: (comicId, episodeKey) async =>
            const Res(<String>['1', '2', '3', '4', '5']),
        readRecordHelper: helper,
        readRecordDebounce: const Duration(milliseconds: 200),
      );
      addTearDown(provider.dispose);
      await tester.pump();

      provider.onPageNoChanged(1);
      provider.onPageNoChanged(2);
      provider.onPageNoChanged(3);
      await tester.pump(const Duration(milliseconds: 199));
      expect(database.select('SELECT * FROM read_record_writes'), isEmpty);

      await tester.pump(const Duration(milliseconds: 1));
      expect(database.select('SELECT * FROM read_record_writes'), hasLength(1));
      expect(helper.get('jm', 'comic-debounce')?.pageNo, 3);
    });

    test('dispose flushes a pending debounced read record', () {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      final helper = ReadRecordHelper(database);
      const chapter = ReaderChapter(id: 'flush', order: 1, name: 'Flush');
      final provider = ReaderProvider(
        state: const ComicState(
          id: 'comic-flush',
          title: 'Flush',
          chapters: <ReaderChapter>[chapter],
          chapter: chapter,
          pageNo: 0,
          sourceKey: 'jm',
        ),
        readRecordHelper: helper,
        readRecordDebounce: const Duration(seconds: 10),
      );

      provider.onPageNoChanged(4);
      expect(helper.get('jm', 'comic-flush'), isNull);
      provider.dispose();

      final flushed = helper.get('jm', 'comic-flush');
      expect(flushed, isNotNull);
      expect(flushed!.chapterId, 'flush');
      expect(flushed.pageNo, 4);
    });
  });

  test('reader builds and debounces a complete history record', () async {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    JoyDatabase.migrateCore(database);
    final helper = ReadRecordHelper(database);
    const chapter = ReaderChapter(id: 'chapter-2', order: 2, name: '第二话');
    const nextChapter = ReaderChapter(id: 'chapter-3', order: 3, name: '第三话');
    final provider = ReaderProvider(
      state: const ComicState(
        id: 'comic-2',
        title: 'Reader title',
        coverUrl: 'reader-cover',
        author: 'Reader author',
        chapters: <ReaderChapter>[chapter, nextChapter],
        chapter: chapter,
        pageNo: 4,
        sourceKey: 'picacg',
      ),
      imageLoader: (comicId, episodeKey) async =>
          const Res(<String>['1', '2', '3', '4', '5', '6', '7', '8']),
      readRecordHelper: helper,
      readRecordDebounce: Duration.zero,
    );
    addTearDown(provider.dispose);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    provider.onPageNoChanged(6);
    final snapshot = provider.buildReadRecord(updatedAt: 1234);
    expect(snapshot.source, 'picacg');
    expect(snapshot.comic, 'comic-2');
    expect(snapshot.title, 'Reader title');
    expect(snapshot.cover, 'reader-cover');
    expect(snapshot.author, 'Reader author');
    expect(snapshot.chapterId, 'chapter-2');
    expect(snapshot.chapterTitle, '第二话');
    expect(snapshot.pageNo, 6);
    expect(snapshot.pageCount, 8);
    expect(snapshot.updatedAt, 1234);

    await Future<void>.delayed(Duration.zero);
    final saved = helper.get('picacg', 'comic-2');
    expect(saved, isNotNull);
    expect(saved!.pageNo, 6);
    expect(saved.title, 'Reader title');
    expect(saved.cover, 'reader-cover');
    expect(saved.author, 'Reader author');
    expect(saved.chapterTitle, '第二话');
    expect(saved.pageCount, 8);

    provider.go(nextChapter);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final chapterSaved = helper.get('picacg', 'comic-2');
    expect(chapterSaved, isNotNull);
    expect(chapterSaved!.chapterId, 'chapter-3');
    expect(chapterSaved.chapterTitle, '第三话');
    expect(chapterSaved.pageNo, 0);
    expect(chapterSaved.pageCount, 8);
  });
}

class _TestComic extends BaseComic {
  const _TestComic({required this.id, required this.title});

  @override
  final String id;

  @override
  final String title;

  @override
  String get subTitle => '';

  @override
  String get cover => '';

  @override
  List<String> get tags => const <String>[];

  @override
  String get description => '';
}
