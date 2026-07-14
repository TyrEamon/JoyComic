// 阅读记录数据库操作。
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'joy_database.dart';

/// 每部漫画唯一的当前阅读恢复点。
class ReadRecord {
  final String source;
  final String comic;
  final String title;
  final String cover;
  final String author;
  final String chapterId;
  final String chapterTitle;
  final int pageNo;
  final int pageCount;
  final int updatedAt;

  const ReadRecord({
    String? source,
    String? comic,
    String? sourceKey,
    String? comicId,
    this.title = '',
    this.cover = '',
    this.author = '',
    required this.chapterId,
    this.chapterTitle = '',
    required this.pageNo,
    this.pageCount = 0,
    required this.updatedAt,
  }) : assert(source != null || sourceKey != null),
       assert(comic != null || comicId != null),
       assert(source == null || sourceKey == null || source == sourceKey),
       assert(comic == null || comicId == null || comic == comicId),
       source = source ?? sourceKey ?? '',
       comic = comic ?? comicId ?? '';

  String get sourceKey => source;
  String get comicId => comic;
  String get coverUrl => cover;

  factory ReadRecord.fromRow(Row row) {
    return ReadRecord(
      source: (row['source_key'] as String?) ?? '',
      comic: (row['comic_id'] as String?) ?? '',
      title: (row['title'] as String?) ?? '',
      cover: (row['cover_url'] as String?) ?? '',
      author: (row['author'] as String?) ?? '',
      chapterId: (row['chapter_id'] as String?) ?? '',
      chapterTitle: (row['chapter_title'] as String?) ?? '',
      pageNo: (row['page_no'] as int?) ?? 0,
      pageCount: (row['page_count'] as int?) ?? 0,
      updatedAt: (row['updated_at'] as int?) ?? 0,
    );
  }
}

/// Global reading-history change signal shared by readers and summary pages.
class ReadRecordNotifier extends ChangeNotifier {
  ReadRecordNotifier._();

  static final ReadRecordNotifier instance = ReadRecordNotifier._();

  int _revision = 0;

  /// Monotonically increasing version for successful history mutations.
  int get revision => _revision;

  void _broadcastChange() {
    _revision++;
    notifyListeners();
  }
}

class ReadRecordHelper {
  ReadRecordHelper([Database? database]) : _database = database;

  final Database? _database;
  Database get _db => _database ?? JoyDatabase.instance.core;

  /// 保存完整恢复点；同一来源、同一漫画始终只有一条记录。
  void upsert(ReadRecord record) {
    _db.execute(
      '''
      INSERT INTO read_records
        (source_key, comic_id, title, cover_url, author, chapter_id,
         chapter_title, page_no, page_count, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(source_key, comic_id) DO UPDATE SET
        title = excluded.title,
        cover_url = excluded.cover_url,
        author = excluded.author,
        chapter_id = excluded.chapter_id,
        chapter_title = excluded.chapter_title,
        page_no = excluded.page_no,
        page_count = excluded.page_count,
        updated_at = excluded.updated_at
    ''',
      <Object?>[
        record.source,
        record.comic,
        record.title,
        record.cover,
        record.author,
        record.chapterId,
        record.chapterTitle,
        record.pageNo,
        record.pageCount,
        record.updatedAt,
      ],
    );
    ReadRecordNotifier.instance._broadcastChange();
  }

  /// 兼容阅读器现有调用的快捷保存接口。
  void save({
    required String comicId,
    required String sourceKey,
    required String chapterId,
    required int pageNo,
    String? title,
    String? cover,
    String? author,
    String? chapterTitle,
    int? pageCount,
    int? updatedAt,
  }) {
    final existing = get(sourceKey, comicId);
    final sameChapter = existing?.chapterId == chapterId;
    upsert(
      ReadRecord(
        source: sourceKey,
        comic: comicId,
        title: title ?? existing?.title ?? '',
        cover: cover ?? existing?.cover ?? '',
        author: author ?? existing?.author ?? '',
        chapterId: chapterId,
        chapterTitle:
            chapterTitle ?? (sameChapter ? existing?.chapterTitle ?? '' : ''),
        pageNo: pageNo,
        pageCount: pageCount ?? (sameChapter ? existing?.pageCount ?? 0 : 0),
        updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 按更新时间倒序列出历史。
  List<ReadRecord> list({int? limit}) {
    if (limit != null && limit < 0) {
      throw ArgumentError.value(limit, 'limit', 'must not be negative');
    }
    final sql = StringBuffer(
      'SELECT * FROM read_records '
      'ORDER BY updated_at DESC, source_key ASC, comic_id ASC',
    );
    final parameters = <Object?>[];
    if (limit != null) {
      sql.write(' LIMIT ?');
      parameters.add(limit);
    }
    return _db
        .select(sql.toString(), parameters)
        .map(ReadRecord.fromRow)
        .toList();
  }

  ReadRecord? get(String source, String comic) {
    final rows = _db.select(
      'SELECT * FROM read_records WHERE source_key = ? AND comic_id = ?',
      <Object?>[source, comic],
    );
    return rows.isEmpty ? null : ReadRecord.fromRow(rows.first);
  }

  int delete(String source, String comic) {
    _db.execute(
      'DELETE FROM read_records WHERE source_key = ? AND comic_id = ?',
      <Object?>[source, comic],
    );
    final deleted = _changes();
    if (deleted > 0) ReadRecordNotifier.instance._broadcastChange();
    return deleted;
  }

  int clear() {
    _db.execute('DELETE FROM read_records');
    final deleted = _changes();
    if (deleted > 0) ReadRecordNotifier.instance._broadcastChange();
    return deleted;
  }

  int count() {
    return _db
            .select('SELECT COUNT(*) AS count FROM read_records')
            .single['count']
        as int;
  }

  int _changes() {
    return _db.select('SELECT changes() AS count').single['count'] as int;
  }

  /// 兼容旧接口：漫画级主键下最多返回一条记录。
  List<ReadRecord> getRecords(String comicId, String sourceKey) {
    final record = get(sourceKey, comicId);
    return record == null ? <ReadRecord>[] : <ReadRecord>[record];
  }

  /// 兼容旧接口：仅当当前恢复点仍位于指定章节时返回。
  ReadRecord? getRecord(String comicId, String sourceKey, String chapterId) {
    final record = get(sourceKey, comicId);
    return record?.chapterId == chapterId ? record : null;
  }

  List<ReadRecord> getRecentComics({int limit = 20}) {
    return list(limit: limit);
  }

  void deleteByComic(String comicId, String sourceKey) {
    delete(sourceKey, comicId);
  }
}
