/// 下载队列数据库操作。
library download_helper;

import '../foundation/download_task.dart';
import 'joy_database.dart';

class DownloadHelper {
  /// 插入下载任务。
  int insert(DownloadItem item) {
    final now = DateTime.now().millisecondsSinceEpoch;
    JoyDatabase.instance.downloadDb.execute(
      'INSERT INTO downloads (comic_id, source_key, chapter_id, url, file_name, status, progress, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        item.comicId,
        item.sourceKey,
        item.chapterId,
        item.url,
        item.fileName,
        item.status.name,
        item.progress,
        now,
        now,
      ],
    );
    return JoyDatabase.instance.downloadDb.lastInsertRowId;
  }

  /// 更新任务状态。
  void update(DownloadItem item) {
    JoyDatabase.instance.downloadDb.execute(
      'UPDATE downloads SET status = ?, progress = ?, file_path = ?, updated_at = ? WHERE id = ?',
      [item.status.name, item.progress, item.filePath, DateTime.now().millisecondsSinceEpoch, item.id],
    );
  }

  /// 获取所有任务。
  List<DownloadItem> getAll() {
    final result = JoyDatabase.instance.downloadDb.select(
      'SELECT * FROM downloads ORDER BY created_at DESC',
    );
    return result.map((r) => DownloadItem.fromRow({
      'id': r['id'],
      'comic_id': r['comic_id'],
      'source_key': r['source_key'],
      'chapter_id': r['chapter_id'],
      'url': r['url'],
      'file_name': r['file_name'],
      'file_path': r['file_path'],
      'status': r['status'],
      'progress': r['progress'],
      'created_at': r['created_at'],
      'updated_at': r['updated_at'],
    })).toList();
  }

  /// 获取指定状态的任务。
  List<DownloadItem> getByStatus(String status) {
    final result = JoyDatabase.instance.downloadDb.select(
      'SELECT * FROM downloads WHERE status = ? ORDER BY created_at ASC',
      [status],
    );
    return result.map((r) => DownloadItem.fromRow({
      'id': r['id'],
      'comic_id': r['comic_id'],
      'source_key': r['source_key'],
      'chapter_id': r['chapter_id'],
      'url': r['url'],
      'file_name': r['file_name'],
      'file_path': r['file_path'],
      'status': r['status'],
      'progress': r['progress'],
      'created_at': r['created_at'],
      'updated_at': r['updated_at'],
    })).toList();
  }

  /// 删除任务。
  void delete(int id) {
    JoyDatabase.instance.downloadDb.execute(
      'DELETE FROM downloads WHERE id = ?',
      [id],
    );
  }

  /// 清空已完成。
  void clearCompleted() {
    JoyDatabase.instance.downloadDb.execute(
      "DELETE FROM downloads WHERE status = 'completed'",
    );
  }
}
