/// WebDAV 同步服务。
///
/// 使用 `archive` 包将阅读记录 + 收藏 → zip 打包，
/// 上传到 WebDAV 服务器，或从服务器下载回本地恢复。
library webdav_sync;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../database/joy_database.dart';
import '../foundation/log.dart';
import '../foundation/webdav_client.dart';

/// 同步状态回调。
typedef SyncProgressCallback = void Function(String message, double progress);

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

      // 1. 从 DB 导出数据
      final data = await _collectData();

      // 2. 创建 zip
      final archive = Archive();
      for (final entry in data.entries) {
        archive.addFile(ArchiveFile(
          entry.key,
          entry.value.length,
          entry.value,
        ));
      }

      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) return '压缩失败';

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

      // 4. 恢复数据到 DB
      for (final file in archive) {
        if (file.isFile) {
          final content = utf8.decode(file.content);
          await _restoreFile(file.name, content);
        }
      }

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

  /// 从 DB 收集要备份的数据。
  Future<Map<String, List<int>>> _collectData() async {
    final data = <String, List<int>>{};

    // 阅读记录
    final records = JoyDatabase.instance.core.select('SELECT * FROM read_records');
    final recordsJson = jsonEncode(records.map((r) => {
      'comic_id': r['comic_id'],
      'source_key': r['source_key'],
      'chapter_id': r['chapter_id'],
      'page_no': r['page_no'],
      'updated_at': r['updated_at'],
    }).toList());
    data['read_records.json'] = utf8.encode(recordsJson);

    // 收藏
    final favs = JoyDatabase.instance.core.select('SELECT * FROM favorites');
    final favsJson = jsonEncode(favs.map((r) => {
      'comic_id': r['comic_id'],
      'source_key': r['source_key'],
      'title': r['title'],
      'cover_url': r['cover_url'],
      'favorited_at': r['favorited_at'],
    }).toList());
    data['favorites.json'] = utf8.encode(favsJson);

    // 搜索历史
    final history = JoyDatabase.instance.core.select('SELECT * FROM search_history');
    final historyJson = jsonEncode(history.map((r) => {
      'keyword': r['keyword'],
      'created_at': r['created_at'],
    }).toList());
    data['search_history.json'] = utf8.encode(historyJson);

    return data;
  }

  Future<void> _restoreFile(String name, String content) async {
    if (name == 'read_records.json') {
      final list = jsonDecode(content) as List;
      for (final item in list) {
        JoyDatabase.instance.core.execute(
          'INSERT OR REPLACE INTO read_records VALUES (?, ?, ?, ?, ?)',
          [item['comic_id'], item['source_key'], item['chapter_id'], item['page_no'], item['updated_at']],
        );
      }
    } else if (name == 'favorites.json') {
      final list = jsonDecode(content) as List;
      for (final item in list) {
        JoyDatabase.instance.core.execute(
          'INSERT OR REPLACE INTO favorites VALUES (?, ?, ?, ?, ?, ?)',
          [item['comic_id'], item['source_key'], item['title'], item['cover_url'], item['favorited_at']],
        );
      }
    } else if (name == 'search_history.json') {
      final list = jsonDecode(content) as List;
      for (final item in list) {
        JoyDatabase.instance.core.execute(
          'INSERT OR REPLACE INTO search_history(keyword, created_at) VALUES (?, ?)',
          [item['keyword'], item['created_at']],
        );
      }
    }
  }
}
