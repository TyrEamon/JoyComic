import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/foundation/webdav_sync.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('WebDAV database archive', () {
    test('round-trips every field in the current core schema', () {
      final source = sqlite3.openInMemory();
      final target = sqlite3.openInMemory();
      addTearDown(source.dispose);
      addTearDown(target.dispose);
      JoyDatabase.migrateCore(source);
      JoyDatabase.migrateCore(target);

      source.execute(
        '''
        INSERT INTO read_records
          (source_key, comic_id, title, cover_url, author, chapter_id,
           chapter_title, page_no, page_count, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          'jm',
          'comic-1',
          '完整标题',
          'https://img.test/read.jpg',
          '阅读作者',
          'chapter-7',
          '第七话',
          6,
          18,
          123456789,
        ],
      );
      source.execute(
        '''
        INSERT INTO favorites
          (source_key, comic_id, title, cover_url, author, authors_json,
           tags_json, metadata_complete, favorited_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          'picacg',
          'favorite-2',
          '收藏标题',
          'https://img.test/favorite.jpg',
          '收藏作者',
          '["收藏作者","第二画师"]',
          '["纯爱","校园"]',
          1,
          987654321,
        ],
      );
      source.execute(
        'INSERT INTO search_history (keyword, created_at) VALUES (?, ?)',
        <Object?>['完整搜索', 24680],
      );

      final archive = exportBackupArchive(source);
      importBackupArchive(target, archive);

      expect(_row(target, 'read_records'), <String, Object?>{
        'source_key': 'jm',
        'comic_id': 'comic-1',
        'title': '完整标题',
        'cover_url': 'https://img.test/read.jpg',
        'author': '阅读作者',
        'chapter_id': 'chapter-7',
        'chapter_title': '第七话',
        'page_no': 6,
        'page_count': 18,
        'updated_at': 123456789,
      });
      expect(_row(target, 'favorites'), <String, Object?>{
        'source_key': 'picacg',
        'comic_id': 'favorite-2',
        'title': '收藏标题',
        'cover_url': 'https://img.test/favorite.jpg',
        'author': '收藏作者',
        'authors_json': '["收藏作者","第二画师"]',
        'tags_json': '["纯爱","校园"]',
        'metadata_complete': 1,
        'favorited_at': 987654321,
      });
      expect(_row(target, 'search_history'), containsPair('keyword', '完整搜索'));
      expect(_row(target, 'search_history'), containsPair('created_at', 24680));
    });

    test('imports legacy backups with current-schema defaults', () {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);

      final archive = Archive()
        ..addFile(
          _jsonFile('read_records.json', <Map<String, Object?>>[
            <String, Object?>{
              'source_key': 'jm',
              'comic_id': 'legacy-read',
              'chapter_id': 'legacy-chapter',
              'page_no': 4,
              'updated_at': 55,
            },
          ]),
        )
        ..addFile(
          _jsonFile('favorites.json', <Map<String, Object?>>[
            <String, Object?>{
              'source_key': 'picacg',
              'comic_id': 'legacy-favorite',
              'title': '旧收藏',
              'cover_url': 'legacy-cover',
              'favorited_at': 66,
            },
          ]),
        );

      importBackupArchive(database, archive);

      expect(_row(database, 'read_records'), <String, Object?>{
        'source_key': 'jm',
        'comic_id': 'legacy-read',
        'title': '',
        'cover_url': '',
        'author': '',
        'chapter_id': 'legacy-chapter',
        'chapter_title': '',
        'page_no': 4,
        'page_count': 0,
        'updated_at': 55,
      });
      expect(_row(database, 'favorites'), <String, Object?>{
        'source_key': 'picacg',
        'comic_id': 'legacy-favorite',
        'title': '旧收藏',
        'cover_url': 'legacy-cover',
        'author': '',
        'authors_json': '[]',
        'tags_json': '[]',
        'metadata_complete': 0,
        'favorited_at': 66,
      });
    });

    test('rolls back every restored file when one archive entry fails', () {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);

      final archive = Archive()
        ..addFile(
          _jsonFile('read_records.json', <Map<String, Object?>>[
            <String, Object?>{'source_key': 'jm', 'comic_id': 'must-rollback'},
          ]),
        )
        ..addFile(
          ArchiveFile(
            'favorites.json',
            utf8.encode('{invalid json').length,
            utf8.encode('{invalid json'),
          ),
        );

      expect(
        () => importBackupArchive(database, archive),
        throwsA(isA<FormatException>()),
      );
      expect(
        database
            .select('SELECT COUNT(*) AS count FROM read_records')
            .single['count'],
        0,
      );
      expect(
        database
            .select('SELECT COUNT(*) AS count FROM favorites')
            .single['count'],
        0,
      );
    });
  });
}

ArchiveFile _jsonFile(String name, Object value) {
  final bytes = utf8.encode(jsonEncode(value));
  return ArchiveFile(name, bytes.length, bytes);
}

Map<String, Object?> _row(Database database, String table) {
  final row = database.select('SELECT * FROM $table').single;
  return <String, Object?>{for (final key in row.keys) key: row[key]};
}
