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

  group('ReadRecordHelper', () {
    late ReadRecordHelper helper;

    setUp(() {
      JoyDatabase.migrateCore(db);
      helper = ReadRecordHelper(db);
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
  });
}

Set<String> _columns(Database db, String table) {
  return db
      .select("PRAGMA table_info('$table')")
      .map((row) => row['name'] as String)
      .toSet();
}
