import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/database/favorites_helper.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/database/read_record_helper.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
  });

  tearDown(() {
    db.dispose();
  });

  group('JoyDatabase initialization lifecycle', () {
    test(
      'shares one initialization future across concurrent callers',
      () async {
        final directory = Completer<String>();
        final opened = <Database>[];
        final manager = JoyDatabase.forTesting(
          databaseDirectory: () => directory.future,
          openDatabase: (_) {
            final database = sqlite3.openInMemory();
            opened.add(database);
            return database;
          },
          coreMigrator: JoyDatabase.migrateCore,
          downloadMigrator: (_) {},
        );

        final first = manager.initialize();
        final second = manager.initialize();

        expect(identical(first, second), isTrue);
        expect(opened, isEmpty);
        directory.complete('memory');
        await Future.wait(<Future<void>>[first, second]);

        expect(opened, hasLength(2));
        expect(manager.core, same(opened.first));
        expect(manager.downloadDb, same(opened.last));
        await manager.close();
      },
    );

    test(
      'disposes partial connections and allows retry after failure',
      () async {
        final opened = <Database>[];
        var migrations = 0;
        final manager = JoyDatabase.forTesting(
          databaseDirectory: () async => 'memory',
          openDatabase: (_) {
            final database = sqlite3.openInMemory();
            opened.add(database);
            return database;
          },
          coreMigrator: (database) {
            migrations++;
            if (migrations == 1) throw StateError('migration failed');
            JoyDatabase.migrateCore(database);
          },
          downloadMigrator: (_) {},
        );

        await expectLater(manager.initialize(), throwsStateError);
        expect(() => manager.core, throwsStateError);
        expect(() => manager.downloadDb, throwsStateError);
        expect(opened, hasLength(2));
        expect(() => opened[0].select('SELECT 1'), throwsA(anything));
        expect(() => opened[1].select('SELECT 1'), throwsA(anything));

        await manager.initialize();
        expect(opened, hasLength(4));
        expect(manager.core, same(opened[2]));
        expect(manager.downloadDb, same(opened[3]));
        await manager.close();
      },
    );
  });

  group('JoyDatabase core migration', () {
    test('creates the current schema from an empty database', () {
      JoyDatabase.migrateCore(db);

      expect(
        _columns(db, 'favorites'),
        containsAll(<String>{
          'source_key',
          'comic_id',
          'title',
          'cover_url',
          'author',
          'authors_json',
          'tags_json',
          'metadata_complete',
          'favorited_at',
        }),
      );
      expect(
        _columns(db, 'read_records'),
        containsAll(<String>{
          'source_key',
          'comic_id',
          'title',
          'cover_url',
          'author',
          'chapter_id',
          'chapter_title',
          'page_no',
          'page_count',
          'updated_at',
        }),
      );
      expect(
        db
            .select('SELECT version FROM schema_meta WHERE id = 1')
            .single['version'],
        JoyDatabase.coreSchemaVersion,
      );
    });

    test('can run repeatedly without changing data', () {
      JoyDatabase.migrateCore(db);
      db.execute(
        'INSERT INTO favorites '
        '(source_key, comic_id, title, cover_url, author, favorited_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        <Object?>['jm', 'comic-1', 'Title', 'cover', 'Author', 10],
      );

      JoyDatabase.migrateCore(db);
      JoyDatabase.migrateCore(db);

      expect(
        db.select('SELECT COUNT(*) AS count FROM favorites').single['count'],
        1,
      );
      expect(db.select('SELECT title FROM favorites').single['title'], 'Title');
    });

    test('adds favorite metadata columns and keeps legacy rows', () {
      db.execute('''
        CREATE TABLE favorites (
          comic_id TEXT NOT NULL,
          source_key TEXT NOT NULL,
          title TEXT,
          cover_url TEXT,
          favorited_at INTEGER NOT NULL,
          PRIMARY KEY (comic_id, source_key)
        )
      ''');
      db.execute(
        'INSERT INTO favorites '
        '(comic_id, source_key, title, cover_url, favorited_at) '
        'VALUES (?, ?, ?, ?, ?)',
        <Object?>['legacy-comic', 'legacy-source', 'Legacy', 'old-cover', 42],
      );

      JoyDatabase.migrateCore(db);

      final row = db.select('SELECT * FROM favorites').single;
      expect(row['comic_id'], 'legacy-comic');
      expect(row['source_key'], 'legacy-source');
      expect(row['title'], 'Legacy');
      expect(row['cover_url'], 'old-cover');
      expect(row['author'], '');
      expect(row['authors_json'], '[]');
      expect(row['tags_json'], '[]');
      expect(row['metadata_complete'], 0);
      expect(row['favorited_at'], 42);
    });

    test('keeps the latest legacy chapter as the comic resume point', () {
      db.execute('''
        CREATE TABLE read_records (
          comic_id TEXT NOT NULL,
          source_key TEXT NOT NULL,
          chapter_id TEXT NOT NULL,
          page_no INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (comic_id, source_key, chapter_id)
        )
      ''');
      db.execute('INSERT INTO read_records VALUES (?, ?, ?, ?, ?)', <Object?>[
        'comic-1',
        'jm',
        'chapter-old',
        8,
        100,
      ]);
      db.execute('INSERT INTO read_records VALUES (?, ?, ?, ?, ?)', <Object?>[
        'comic-1',
        'jm',
        'chapter-new',
        3,
        200,
      ]);
      db.execute('INSERT INTO read_records VALUES (?, ?, ?, ?, ?)', <Object?>[
        'comic-2',
        'jm',
        'chapter-only',
        5,
        150,
      ]);

      JoyDatabase.migrateCore(db);

      final rows = db.select('SELECT * FROM read_records ORDER BY comic_id');
      expect(rows, hasLength(2));
      expect(rows.first['chapter_id'], 'chapter-new');
      expect(rows.first['page_no'], 3);
      expect(rows.first['title'], '');
      expect(rows.first['page_count'], 0);
      expect(rows.last['comic_id'], 'comic-2');

      final pk =
          db
              .select("PRAGMA table_info('read_records')")
              .where((row) => (row['pk'] as int) > 0)
              .toList()
            ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
      expect(pk.map((row) => row['name']), <Object?>['source_key', 'comic_id']);
    });
  });

  test('core migration rolls back every schema change on failure', () {
    db.execute('''
      CREATE TABLE favorites (
        comic_id TEXT NOT NULL,
        source_key TEXT NOT NULL,
        title TEXT,
        cover_url TEXT,
        favorited_at INTEGER NOT NULL,
        PRIMARY KEY (comic_id, source_key)
      )
    ''');
    db.execute(
      'INSERT INTO favorites '
      '(comic_id, source_key, title, cover_url, favorited_at) '
      'VALUES (?, ?, ?, ?, ?)',
      <Object?>['comic-1', 'jm', 'Legacy', 'cover', 10],
    );

    expect(
      () => JoyDatabase.migrateCore(
        db,
        beforeCommit: () => throw StateError('injected failure'),
      ),
      throwsStateError,
    );

    expect(_columns(db, 'favorites'), isNot(contains('author')));
    expect(
      db.select("SELECT name FROM sqlite_master WHERE name = 'schema_meta'"),
      isEmpty,
    );
    expect(db.select('SELECT title FROM favorites').single['title'], 'Legacy');

    JoyDatabase.migrateCore(db);
    expect(_columns(db, 'favorites'), contains('author'));
  });

  group('FavoritesHelper', () {
    late FavoritesHelper helper;

    setUp(() {
      JoyDatabase.migrateCore(db);
      helper = FavoritesHelper(db);
    });

    test('upserts and gets complete typed metadata', () {
      helper.upsert(
        const FavoriteRecord(
          source: 'jm',
          comic: 'comic-1',
          title: 'Old title',
          cover: 'old-cover',
          author: 'Old author',
          favoritedAt: 10,
        ),
      );
      helper.upsert(
        const FavoriteRecord(
          source: 'jm',
          comic: 'comic-1',
          title: 'New title',
          cover: 'new-cover',
          author: 'New author',
          favoritedAt: 20,
        ),
      );

      expect(helper.count(), 1);
      final favorite = helper.get('jm', 'comic-1');
      expect(favorite, isNotNull);
      expect(favorite!.source, 'jm');
      expect(favorite.comic, 'comic-1');
      expect(favorite.title, 'New title');
      expect(favorite.cover, 'new-cover');
      expect(favorite.author, 'New author');
      expect(favorite.favoritedAt, 20);
    });

    test('lists newest favorites first and deletes by comic identity', () {
      helper.upsert(
        const FavoriteRecord(
          source: 'jm',
          comic: 'older',
          title: 'Older',
          cover: '',
          author: '',
          favoritedAt: 10,
        ),
      );
      helper.upsert(
        const FavoriteRecord(
          source: 'picacg',
          comic: 'newer',
          title: 'Newer',
          cover: '',
          author: '',
          favoritedAt: 30,
        ),
      );

      expect(helper.list().map((record) => record.comic), <String>[
        'newer',
        'older',
      ]);
      expect(helper.delete('jm', 'older'), 1);
      expect(helper.get('jm', 'older'), isNull);
      expect(helper.count(), 1);
    });
  });

  group('FavoritesHelper toggle injection', () {
    setUp(() {
      JoyDatabase.migrateCore(db);
      FavoriteNotifier.instance.loadFromDb(db);
    });

    test(
      'successful toggle persists only through the injected database',
      () async {
        final calls = <bool>[];
        final helper = FavoritesHelper(db, (source, comic, favorite) async {
          calls.add(favorite);
        });

        expect(
          await helper.toggleFavorite(
            sourceKey: 'injected',
            comicId: 'comic-1',
            title: 'Title',
            coverUrl: 'cover',
          ),
          isTrue,
        );
        expect(helper.get('injected', 'comic-1')?.title, 'Title');
        expect(
          FavoriteNotifier.instance.isFavorited('injected', 'comic-1'),
          isTrue,
        );

        expect(
          await helper.toggleFavorite(
            sourceKey: 'injected',
            comicId: 'comic-1',
            title: 'Title',
            coverUrl: 'cover',
          ),
          isFalse,
        );
        expect(helper.get('injected', 'comic-1'), isNull);
        expect(
          FavoriteNotifier.instance.isFavorited('injected', 'comic-1'),
          isFalse,
        );
        expect(calls, <bool>[true, false]);
      },
    );

    test(
      'concurrent toggles share one remote operation per favorite',
      () async {
        final addGate = Completer<void>();
        var addCalls = 0;
        final addHelper = FavoritesHelper(db, (source, comic, favorite) async {
          addCalls++;
          await addGate.future;
        });

        final firstAdd = addHelper.toggleFavorite(
          sourceKey: 'injected',
          comicId: 'comic-1',
          title: 'Title',
          coverUrl: 'cover',
        );
        final secondAdd = addHelper.toggleFavorite(
          sourceKey: 'injected',
          comicId: 'comic-1',
          title: 'Title',
          coverUrl: 'cover',
        );
        await Future<void>.delayed(Duration.zero);

        expect(addCalls, 1);
        addGate.complete();
        expect(await Future.wait(<Future<bool>>[firstAdd, secondAdd]), <bool>[
          true,
          true,
        ]);
        expect(addHelper.count(), 1);

        final removeGate = Completer<void>();
        var removeCalls = 0;
        final removeHelper = FavoritesHelper(db, (
          source,
          comic,
          favorite,
        ) async {
          removeCalls++;
          await removeGate.future;
        });
        final firstRemove = removeHelper.toggleFavorite(
          sourceKey: 'injected',
          comicId: 'comic-1',
          title: 'Title',
          coverUrl: 'cover',
        );
        final secondRemove = removeHelper.toggleFavorite(
          sourceKey: 'injected',
          comicId: 'comic-1',
          title: 'Title',
          coverUrl: 'cover',
        );
        await Future<void>.delayed(Duration.zero);

        expect(removeCalls, 1);
        removeGate.complete();
        expect(
          await Future.wait(<Future<bool>>[firstRemove, secondRemove]),
          <bool>[false, false],
        );
        expect(removeHelper.count(), 0);
      },
    );

    test(
      'failed remote add leaves injected database and memory unchanged',
      () async {
        final helper = FavoritesHelper(db, (source, comic, favorite) async {
          throw StateError('remote failed');
        });
        await expectLater(
          helper.toggleFavorite(
            sourceKey: 'injected',
            comicId: 'comic-1',
            title: 'Title',
            coverUrl: 'cover',
          ),
          throwsStateError,
        );
        expect(helper.count(), 0);
        expect(
          FavoriteNotifier.instance.isFavorited('injected', 'comic-1'),
          isFalse,
        );
      },
    );

    test(
      'failed remote removal preserves injected database and memory',
      () async {
        final seed = FavoritesHelper(db);
        seed.upsert(
          const FavoriteRecord(
            source: 'injected',
            comic: 'comic-1',
            title: 'Title',
            cover: 'cover',
            author: '',
            favoritedAt: 10,
          ),
        );
        FavoriteNotifier.instance.loadFromDb(db);
        final helper = FavoritesHelper(db, (source, comic, favorite) async {
          throw StateError('remote failed');
        });
        await expectLater(
          helper.toggleFavorite(
            sourceKey: 'injected',
            comicId: 'comic-1',
            title: 'Title',
            coverUrl: 'cover',
          ),
          throwsStateError,
        );
        expect(helper.count(), 1);
        expect(
          FavoriteNotifier.instance.isFavorited('injected', 'comic-1'),
          isTrue,
        );
      },
    );
  });

  group('FavoritesHelper clear', () {
    late FavoritesHelper helper;

    setUp(() {
      JoyDatabase.migrateCore(db);
      helper = FavoritesHelper(db);
      for (final record in const <FavoriteRecord>[
        FavoriteRecord(
          source: 'jm',
          comic: 'jm-1',
          title: 'JM 1',
          cover: '',
          author: '',
          favoritedAt: 10,
        ),
        FavoriteRecord(
          source: 'jm',
          comic: 'jm-2',
          title: 'JM 2',
          cover: '',
          author: '',
          favoritedAt: 20,
        ),
        FavoriteRecord(
          source: 'picacg',
          comic: 'pica-1',
          title: 'Pica 1',
          cover: '',
          author: '',
          favoritedAt: 30,
        ),
      ]) {
        helper.upsert(record);
      }
    });

    test('clears every local favorite when sourceKey is omitted', () {
      FavoriteNotifier.instance.loadFromDb(db);
      final revision = FavoriteNotifier.instance.revision;

      expect(helper.clear(), 3);
      expect(helper.count(), 0);
      expect(helper.list(), isEmpty);
      expect(FavoriteNotifier.instance.isFavorited('jm', 'jm-1'), isFalse);
      expect(
        FavoriteNotifier.instance.isFavorited('picacg', 'pica-1'),
        isFalse,
      );
      expect(FavoriteNotifier.instance.revision, revision + 1);
    });

    test('clears only the requested source', () {
      FavoriteNotifier.instance.loadFromDb(db);
      final revision = FavoriteNotifier.instance.revision;

      expect(helper.clear(sourceKey: 'jm'), 2);
      expect(helper.count(), 1);
      expect(helper.get('jm', 'jm-1'), isNull);
      expect(helper.get('jm', 'jm-2'), isNull);
      expect(helper.get('picacg', 'pica-1'), isNotNull);
      expect(FavoriteNotifier.instance.isFavorited('jm', 'jm-1'), isFalse);
      expect(FavoriteNotifier.instance.isFavorited('picacg', 'pica-1'), isTrue);
      expect(FavoriteNotifier.instance.revision, revision + 1);

      expect(helper.clear(sourceKey: 'missing'), 0);
      expect(helper.count(), 1);
      expect(FavoriteNotifier.instance.revision, revision + 1);
    });
  });
  test('favorite identity and source filtering do not collide on colons', () {
    JoyDatabase.migrateCore(db);
    final helper = FavoritesHelper(db);
    helper.upsert(
      const FavoriteRecord(
        source: 'a',
        comic: 'b:c',
        title: 'First',
        cover: '',
        author: '',
        favoritedAt: 10,
      ),
    );
    helper.upsert(
      const FavoriteRecord(
        source: 'a:b',
        comic: 'c',
        title: 'Second',
        cover: '',
        author: '',
        favoritedAt: 20,
      ),
    );
    FavoriteNotifier.instance.loadFromDb(db);

    expect(FavoriteNotifier.instance.isFavorited('a', 'b:c'), isTrue);
    expect(FavoriteNotifier.instance.isFavorited('a:b', 'c'), isTrue);
    expect(helper.clear(sourceKey: 'a'), 1);
    expect(FavoriteNotifier.instance.isFavorited('a', 'b:c'), isFalse);
    expect(FavoriteNotifier.instance.isFavorited('a:b', 'c'), isTrue);
  });

  group('ReadRecordHelper', () {
    late ReadRecordHelper helper;

    setUp(() {
      JoyDatabase.migrateCore(db);
      helper = ReadRecordHelper(db);
    });

    test('supports legacy and complete constructor names', () {
      const legacy = ReadRecord(
        sourceKey: 'legacy-source',
        comicId: 'legacy-comic',
        chapterId: 'chapter-1',
        pageNo: 3,
        updatedAt: 40,
      );
      const complete = ReadRecord(
        source: 'new-source',
        comic: 'new-comic',
        title: 'Title',
        cover: 'Cover',
        author: 'Author',
        chapterId: 'chapter-2',
        chapterTitle: 'Chapter 2',
        pageNo: 4,
        pageCount: 30,
        updatedAt: 50,
      );

      expect(legacy.source, 'legacy-source');
      expect(legacy.comic, 'legacy-comic');
      expect(legacy.title, '');
      expect(legacy.cover, '');
      expect(legacy.author, '');
      expect(legacy.chapterTitle, '');
      expect(legacy.pageCount, 0);
      helper.upsert(legacy);
      expect(
        helper.get('legacy-source', 'legacy-comic')?.chapterId,
        'chapter-1',
      );
      expect(complete.sourceKey, 'new-source');
      expect(complete.comicId, 'new-comic');
      expect(complete.title, 'Title');
    });

    test('upserts one complete resume point per comic', () {
      helper.upsert(
        const ReadRecord(
          source: 'jm',
          comic: 'comic-1',
          title: 'Comic',
          cover: 'cover',
          author: 'Author',
          chapterId: 'chapter-1',
          chapterTitle: 'Chapter 1',
          pageNo: 5,
          pageCount: 20,
          updatedAt: 100,
        ),
      );
      helper.upsert(
        const ReadRecord(
          source: 'jm',
          comic: 'comic-1',
          title: 'Comic updated',
          cover: 'new-cover',
          author: 'Author updated',
          chapterId: 'chapter-2',
          chapterTitle: 'Chapter 2',
          pageNo: 2,
          pageCount: 30,
          updatedAt: 200,
        ),
      );

      expect(helper.count(), 1);
      final record = helper.get('jm', 'comic-1');
      expect(record, isNotNull);
      expect(record!.source, 'jm');
      expect(record.comic, 'comic-1');
      expect(record.title, 'Comic updated');
      expect(record.cover, 'new-cover');
      expect(record.author, 'Author updated');
      expect(record.chapterId, 'chapter-2');
      expect(record.chapterTitle, 'Chapter 2');
      expect(record.pageNo, 2);
      expect(record.pageCount, 30);
      expect(record.updatedAt, 200);
    });

    test('legacy save updates position without erasing stored metadata', () {
      helper.upsert(
        const ReadRecord(
          source: 'jm',
          comic: 'comic-1',
          title: 'Comic',
          cover: 'cover',
          author: 'Author',
          chapterId: 'chapter-1',
          chapterTitle: 'Chapter 1',
          pageNo: 5,
          pageCount: 20,
          updatedAt: 100,
        ),
      );

      helper.save(
        sourceKey: 'jm',
        comicId: 'comic-1',
        chapterId: 'chapter-2',
        pageNo: 3,
        updatedAt: 200,
      );

      final record = helper.get('jm', 'comic-1')!;
      expect(record.title, 'Comic');
      expect(record.cover, 'cover');
      expect(record.author, 'Author');
      expect(record.chapterId, 'chapter-2');
      expect(record.chapterTitle, '');
      expect(record.pageNo, 3);
      expect(record.pageCount, 0);
      expect(record.updatedAt, 200);
    });
    test('lists newest history first and supports delete clear and count', () {
      helper.upsert(
        const ReadRecord(
          source: 'jm',
          comic: 'older',
          title: 'Older',
          cover: '',
          author: '',
          chapterId: 'c1',
          chapterTitle: '',
          pageNo: 1,
          pageCount: 10,
          updatedAt: 10,
        ),
      );
      helper.upsert(
        const ReadRecord(
          source: 'picacg',
          comic: 'newer',
          title: 'Newer',
          cover: '',
          author: '',
          chapterId: 'c2',
          chapterTitle: '',
          pageNo: 2,
          pageCount: 20,
          updatedAt: 30,
        ),
      );

      expect(helper.list().map((record) => record.comic), <String>[
        'newer',
        'older',
      ]);
      expect(helper.delete('jm', 'older'), 1);
      expect(helper.count(), 1);
      expect(helper.clear(), 1);
      expect(helper.count(), 0);
      expect(helper.list(), isEmpty);
    });

    test('notifier revision advances once for every history mutation', () {
      final notifier = ReadRecordNotifier.instance;
      final initialRevision = notifier.revision;
      var notifications = 0;
      void listener() => notifications++;
      notifier.addListener(listener);
      addTearDown(() => notifier.removeListener(listener));

      helper.upsert(
        const ReadRecord(
          source: 'jm',
          comic: 'tracked',
          chapterId: 'chapter-1',
          pageNo: 1,
          updatedAt: 1,
        ),
      );
      expect(notifier.revision, initialRevision + 1);

      helper.save(
        sourceKey: 'jm',
        comicId: 'tracked',
        chapterId: 'chapter-1',
        pageNo: 2,
        updatedAt: 2,
      );
      expect(notifier.revision, initialRevision + 2);

      expect(helper.delete('jm', 'tracked'), 1);
      expect(notifier.revision, initialRevision + 3);

      helper.upsert(
        const ReadRecord(
          source: 'jm',
          comic: 'clear-me',
          chapterId: 'chapter-1',
          pageNo: 1,
          updatedAt: 3,
        ),
      );
      expect(helper.clear(), 1);
      expect(notifier.revision, initialRevision + 5);
      expect(notifications, 5);
    });
  });
}

Set<String> _columns(Database db, String table) {
  return db
      .select("PRAGMA table_info('$table')")
      .map((row) => row['name'] as String)
      .toSet();
}
