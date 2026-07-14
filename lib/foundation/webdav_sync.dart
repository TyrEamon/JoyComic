/// WebDAV 同步服务。
///
/// 使用 `archive` 包将阅读记录 + 收藏 → zip 打包，
/// 上传到 WebDAV 服务器，或从服务器下载回本地恢复。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../database/joy_database.dart';
import '../foundation/log.dart';
import '../foundation/webdav_client.dart';

/// 同步状态回调。
typedef SyncProgressCallback = void Function(String message, double progress);

/// Exports the syncable core tables into an in-memory backup archive.
///
/// The selected fields deliberately mirror the current database schema so a
/// backup never depends on SQLite's physical column order.
Archive exportBackupArchive(Database database) {
  final archive = Archive();
  _addJsonFile(
    archive,
    'read_records.json',
    database
        .select('''
          SELECT source_key, comic_id, title, cover_url, author, chapter_id,
                 chapter_title, page_no, page_count, updated_at
          FROM read_records
        ''')
        .map(
          (row) => <String, Object?>{
            'source_key': row['source_key'],
            'comic_id': row['comic_id'],
            'title': row['title'],
            'cover_url': row['cover_url'],
            'author': row['author'],
            'chapter_id': row['chapter_id'],
            'chapter_title': row['chapter_title'],
            'page_no': row['page_no'],
            'page_count': row['page_count'],
            'updated_at': row['updated_at'],
          },
        )
        .toList(),
  );
  _addJsonFile(
    archive,
    'favorites.json',
    database
        .select('''
          SELECT source_key, comic_id, title, cover_url, author, favorited_at
          FROM favorites
        ''')
        .map(
          (row) => <String, Object?>{
            'source_key': row['source_key'],
            'comic_id': row['comic_id'],
            'title': row['title'],
            'cover_url': row['cover_url'],
            'author': row['author'],
            'favorited_at': row['favorited_at'],
          },
        )
        .toList(),
  );
  _addJsonFile(
    archive,
    'search_history.json',
    database
        .select('SELECT keyword, created_at FROM search_history')
        .map(
          (row) => <String, Object?>{
            'keyword': row['keyword'],
            'created_at': row['created_at'],
          },
        )
        .toList(),
  );
  return archive;
}

/// Imports every supported file in [archive] atomically.
///
/// Missing fields are filled with the same defaults as the current schema so
/// archives created by older JoyComic versions remain restorable.
void importBackupArchive(Database database, Archive archive) {
  database.execute('BEGIN IMMEDIATE');
  try {
    for (final file in archive) {
      if (!file.isFile) continue;
      final content = utf8.decode(file.content);
      _importBackupFile(database, file.name, content);
    }
    database.execute('COMMIT');
  } catch (error, stackTrace) {
    try {
      database.execute('ROLLBACK');
    } catch (_) {
      // Preserve the archive import error.
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
}

void _addJsonFile(Archive archive, String name, Object value) {
  final bytes = utf8.encode(jsonEncode(value));
  archive.addFile(ArchiveFile(name, bytes.length, bytes));
}

void _importBackupFile(Database database, String name, String content) {
  if (name == 'read_records.json') {
    for (final item in _decodeBackupRows(name, content)) {
      database.execute(
        '''
        INSERT OR REPLACE INTO read_records
          (source_key, comic_id, title, cover_url, author, chapter_id,
           chapter_title, page_no, page_count, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          _stringValue(item, 'source_key'),
          _stringValue(item, 'comic_id'),
          _stringValue(item, 'title'),
          _stringValue(item, 'cover_url'),
          _stringValue(item, 'author'),
          _stringValue(item, 'chapter_id'),
          _stringValue(item, 'chapter_title'),
          _intValue(item, 'page_no'),
          _intValue(item, 'page_count'),
          _intValue(item, 'updated_at'),
        ],
      );
    }
    return;
  }
  if (name == 'favorites.json') {
    for (final item in _decodeBackupRows(name, content)) {
      database.execute(
        '''
        INSERT OR REPLACE INTO favorites
          (source_key, comic_id, title, cover_url, author, favorited_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ''',
        <Object?>[
          _stringValue(item, 'source_key'),
          _stringValue(item, 'comic_id'),
          _stringValue(item, 'title'),
          _stringValue(item, 'cover_url'),
          _stringValue(item, 'author'),
          _intValue(item, 'favorited_at'),
        ],
      );
    }
    return;
  }
  if (name == 'search_history.json') {
    for (final item in _decodeBackupRows(name, content)) {
      database.execute(
        '''
        INSERT OR REPLACE INTO search_history (keyword, created_at)
        VALUES (?, ?)
        ''',
        <Object?>[_stringValue(item, 'keyword'), _intValue(item, 'created_at')],
      );
    }
  }
}

List<Map<String, Object?>> _decodeBackupRows(String name, String content) {
  final decoded = jsonDecode(content);
  if (decoded is! List) {
    throw FormatException('$name must contain a JSON array');
  }
  return <Map<String, Object?>>[
    for (final row in decoded)
      if (row is Map)
        <String, Object?>{
          for (final entry in row.entries)
            if (entry.key is String) entry.key as String: entry.value,
        }
      else
        throw FormatException('$name contains a non-object row'),
  ];
}

String _stringValue(Map<String, Object?> row, String key) {
  final value = row[key];
  return value == null ? '' : value.toString();
}

int _intValue(Map<String, Object?> row, String key) {
  final value = row[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// WebDAV 同步服务。
class WebDavSync {
  WebDavSync(this.client);
  final WebDavClient client;

  /// 备份数据到 WebDAV。
  ///
  /// 打包内容：阅读记录 + 收藏数据 → joycomic_backup_日期.zip
  Future<String?> backup({SyncProgressCallback? onProgress}) async {
    try {
      onProgress?.call('正在打包数据...', 0.1);

      // 1. 从 DB 导出数据并创建归档。
      final archive = exportBackupArchive(JoyDatabase.instance.core);
      final encoded = ZipEncoder().encode(archive);

      // 3. 写临时文件
      final tmpDir = Directory.systemTemp;
      final date = DateTime.now().toIso8601String().split('T').first;
      final zipPath = p.join(tmpDir.path, 'joycomic_backup_$date.zip');
      await File(zipPath).writeAsBytes(encoded);

      onProgress?.call('正在上传到 WebDAV...', 0.5);

      // 4. 确保远程目录存在
      await client.createDirectory('joycomic_backups');

      // 5. 上传
      final remotePath = 'joycomic_backups/backup_$date.zip';
      final result = await client.uploadFile(
        localPath: zipPath,
        remotePath: remotePath,
        onProgress: (sent, total) {
          onProgress?.call('上传中...', 0.5 + (sent / total * 0.4));
        },
      );

      // 6. 清理临时文件
      await File(zipPath).delete();

      if (!result.isSuccess) return result.error;
      onProgress?.call('备份完成', 1.0);
      Log.i('WebDAV backup done', remotePath);
      return null; // 成功
    } catch (e) {
      Log.e('WebDAV backup failed', error: e);
      return e.toString();
    }
  }

  /// 从 WebDAV 恢复数据。
  Future<String?> restore({SyncProgressCallback? onProgress}) async {
    try {
      onProgress?.call('正在列出远程备份...', 0.0);

      // 1. 列出远程备份目录
      final listResult = await client.listDirectory('joycomic_backups');
      if (!listResult.isSuccess) return listResult.error;

      // 找最新的 zip
      final zips = (listResult.data ?? [])
          .where((h) => h.endsWith('.zip'))
          .toList();
      if (zips.isEmpty) return '没有找到备份文件';
      final latest = zips.last;

      onProgress?.call('正在下载备份...', 0.2);

      // 2. 下载 zip
      final tmpDir = Directory.systemTemp;
      final zipPath = p.join(tmpDir.path, 'joycomic_restore.zip');
      final dlResult = await client.downloadFile(
        remotePath: latest,
        localPath: zipPath,
        onProgress: (received, total) {
          onProgress?.call('下载中...', 0.2 + (received / total * 0.3));
        },
      );
      if (!dlResult.isSuccess) return dlResult.error;

      onProgress?.call('正在解压恢复...', 0.6);

      // 3. 解压
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 4. 在单一事务内恢复整个归档。
      importBackupArchive(JoyDatabase.instance.core, archive);

      // 5. 清理
      await File(zipPath).delete();

      onProgress?.call('恢复完成', 1.0);
      Log.i('WebDAV restore done', '${archive.files.length} files');
      return null;
    } catch (e) {
      Log.e('WebDAV restore failed', error: e);
      return e.toString();
    }
  }
}
