/// 阅读记录数据库操作。
library read_record_helper;

import '../foundation/log.dart';
import 'joy_database.dart';

/// 阅读记录数据模型。
class ReadRecord {
  final String comicId;
  final String sourceKey;
  final String chapterId;
  final int pageNo;
  final int updatedAt;

  const ReadRecord({
    required this.comicId,
    required this.sourceKey,
    required this.chapterId,
    required this.pageNo,
    required this.updatedAt,
  });
}

class ReadRecordHelper {
  /// 保存或更新阅读记录。
  void save({
    required String comicId,
    required String sourceKey,
    required String chapterId,
    required int pageNo,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    JoyDatabase.instance.core.execute(
      'INSERT OR REPLACE INTO read_records '
      '(comic_id, source_key, chapter_id, page_no, updated_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [comicId, sourceKey, chapterId, pageNo, now],
    );
  }

  /// 获取某漫画的最近阅读记录（所有章节）。
  List<ReadRecord> getRecords(String comicId, String sourceKey) {
    final result = JoyDatabase.instance.core.select(
      'SELECT * FROM read_records WHERE comic_id = ? AND source_key = ? '
      'ORDER BY updated_at DESC',
      [comicId, sourceKey],
    );
    return result.map((r) => ReadRecord(
      comicId: r['comic_id'] as String,
      sourceKey: r['source_key'] as String,
      chapterId: r['chapter_id'] as String,
      pageNo: (r['page_no'] as int?) ?? 0,
      updatedAt: (r['updated_at'] as int?) ?? 0,
    )).toList();
  }

  /// 获取某章节的阅读记录（继续阅读用）。
  ReadRecord? getRecord(String comicId, String sourceKey, String chapterId) {
    final result = JoyDatabase.instance.core.select(
      'SELECT * FROM read_records WHERE comic_id = ? AND source_key = ? AND chapter_id = ?',
      [comicId, sourceKey, chapterId],
    );
    if (result.isEmpty) return null;
    final r = result.first;
    return ReadRecord(
      comicId: r['comic_id'] as String,
      sourceKey: r['source_key'] as String,
      chapterId: r['chapter_id'] as String,
      pageNo: (r['page_no'] as int?) ?? 0,
      updatedAt: (r['updated_at'] as int?) ?? 0,
    );
  }

  /// 获取最近阅读的漫画列表（每个漫画一条）。
  List<ReadRecord> getRecentComics({int limit = 20}) {
    final result = JoyDatabase.instance.core.select(
      'SELECT comic_id, source_key, MAX(updated_at) as updated_at '
      'FROM read_records GROUP BY comic_id, source_key '
      'ORDER BY updated_at DESC LIMIT $limit',
    );
    return result.map((r) => ReadRecord(
      comicId: r['comic_id'] as String,
      sourceKey: r['source_key'] as String,
      chapterId: '',
      pageNo: 0,
      updatedAt: (r['updated_at'] as int?) ?? 0,
    )).toList();
  }

  /// 删除某漫画的所有阅读记录。
  void deleteByComic(String comicId, String sourceKey) {
    JoyDatabase.instance.core.execute(
      'DELETE FROM read_records WHERE comic_id = ? AND source_key = ?',
      [comicId, sourceKey],
    );
  }
}
