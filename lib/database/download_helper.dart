/// SQLite persistence for chapter download tasks.
library;

import 'package:sqlite3/sqlite3.dart';

import '../foundation/download_task.dart';
import 'joy_database.dart';

class DownloadHelper {
  DownloadHelper([Database? database]) : _database = database;

  final Database? _database;
  Database get _db => _database ?? JoyDatabase.instance.downloadDb;

  /// Inserts a task once and returns the existing row on identity conflict.
  DownloadTask enqueue(DownloadTask task) {
    final row = task.toRow();
    _db.execute(
      '''
      INSERT OR IGNORE INTO downloads (
        source_key, comic_id, chapter_id, title, cover_url, chapter_title,
        page_urls, completed_count, directory, error_message, status,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        row['source_key'],
        row['comic_id'],
        row['chapter_id'],
        row['title'],
        row['cover_url'],
        row['chapter_title'],
        row['page_urls'],
        row['completed_count'],
        row['directory'],
        row['error_message'],
        row['status'],
        row['created_at'],
        row['updated_at'],
      ],
    );
    return find(task.identity) ??
        (throw StateError('Download task was not persisted: ${task.identity}'));
  }

  /// Compatibility alias for the old helper API.
  int insert(DownloadTask task) => enqueue(task).id!;

  void update(DownloadTask task) {
    final id = task.id;
    if (id == null) throw StateError('Cannot update an unsaved download task');
    task.updatedAt = DateTime.now();
    final row = task.toRow();
    _db.execute(
      '''
      UPDATE downloads SET
        title = ?, cover_url = ?, chapter_title = ?, page_urls = ?,
        completed_count = ?, directory = ?, error_message = ?, status = ?,
        updated_at = ?
      WHERE id = ?
      ''',
      <Object?>[
        row['title'],
        row['cover_url'],
        row['chapter_title'],
        row['page_urls'],
        row['completed_count'],
        row['directory'],
        row['error_message'],
        row['status'],
        row['updated_at'],
        id,
      ],
    );
  }

  DownloadTask? find(DownloadIdentity identity) {
    final rows = _db.select(
      '''
      SELECT * FROM downloads
      WHERE source_key = ? AND comic_id = ? AND chapter_id = ?
      LIMIT 1
      ''',
      <Object?>[identity.sourceKey, identity.comicId, identity.chapterId],
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  DownloadTask? getById(int id) {
    final rows = _db.select(
      'SELECT * FROM downloads WHERE id = ? LIMIT 1',
      <Object?>[id],
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  List<DownloadTask> getAll() {
    return _db
        .select('SELECT * FROM downloads ORDER BY created_at DESC, id DESC')
        .map(_fromRow)
        .toList();
  }

  List<DownloadTask> getByStatus(String status) {
    return _db
        .select(
          'SELECT * FROM downloads WHERE status = ? '
          'ORDER BY created_at ASC, id ASC',
          <Object?>[status],
        )
        .map(_fromRow)
        .toList();
  }

  /// A process killed during a transfer leaves downloading rows behind.
  /// They become pending on startup and retain URL/page progress for resume.
  int recoverInterrupted() {
    _db.execute(
      "UPDATE downloads SET status = 'pending', updated_at = ? "
      "WHERE status = 'downloading'",
      <Object?>[DateTime.now().millisecondsSinceEpoch],
    );
    return _changes();
  }

  int delete(int id) {
    _db.execute('DELETE FROM downloads WHERE id = ?', <Object?>[id]);
    return _changes();
  }

  int clearCompleted() {
    _db.execute("DELETE FROM downloads WHERE status = 'completed'");
    return _changes();
  }

  int count() =>
      _db.select('SELECT COUNT(*) AS count FROM downloads').single['count']
          as int;

  int _changes() =>
      _db.select('SELECT changes() AS count').single['count'] as int;

  DownloadTask _fromRow(Row row) => DownloadTask.fromRow(<String, Object?>{
    'id': row['id'],
    'source_key': row['source_key'],
    'comic_id': row['comic_id'],
    'chapter_id': row['chapter_id'],
    'title': row['title'],
    'cover_url': row['cover_url'],
    'chapter_title': row['chapter_title'],
    'page_urls': row['page_urls'],
    'completed_count': row['completed_count'],
    'directory': row['directory'],
    'error_message': row['error_message'],
    'status': row['status'],
    'created_at': row['created_at'],
    'updated_at': row['updated_at'],
  });
}
