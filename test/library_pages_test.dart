import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/database/favorites_helper.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/database/read_record_helper.dart';
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
      FavoriteNotifier.instance.consumeDirty();

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
      expect(FavoriteNotifier.instance.isDirty, isFalse);
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
        FavoriteNotifier.instance.consumeDirty();

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
        FavoriteNotifier.instance.consumeDirty();

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
