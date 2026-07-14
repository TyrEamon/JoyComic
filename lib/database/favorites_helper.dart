// 收藏状态本地追踪 + 跨页面通知。
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../comic_source/comic_source.dart';
import '../foundation/log.dart';
import 'joy_database.dart';

/// 完整的本地收藏记录。
class FavoriteRecord {
  final String source;
  final String comic;
  final String title;
  final String cover;
  final String author;
  final int favoritedAt;

  const FavoriteRecord({
    required this.source,
    required this.comic,
    required this.title,
    required this.cover,
    required this.author,
    required this.favoritedAt,
  });

  String get sourceKey => source;
  String get comicId => comic;
  String get coverUrl => cover;

  factory FavoriteRecord.fromRow(Row row) {
    return FavoriteRecord(
      source: (row['source_key'] as String?) ?? '',
      comic: (row['comic_id'] as String?) ?? '',
      title: (row['title'] as String?) ?? '',
      cover: (row['cover_url'] as String?) ?? '',
      author: (row['author'] as String?) ?? '',
      favoritedAt: (row['favorited_at'] as int?) ?? 0,
    );
  }
}

/// 收藏状态通知器（全局单例，跨页面共享）。
class FavoriteNotifier extends ChangeNotifier {
  FavoriteNotifier._();
  static final FavoriteNotifier instance = FavoriteNotifier._();

  final Set<String> _favoritedIds = <String>{};
  bool _dirty = false;
  bool get isDirty => _dirty;

  void markDirty() {
    _dirty = true;
    notifyListeners();
  }

  void consumeDirty() {
    _dirty = false;
  }

  void loadFromDb([Database? database]) {
    _favoritedIds.clear();
    for (final favorite in FavoritesHelper(database).list()) {
      _favoritedIds.add('${favorite.source}:${favorite.comic}');
    }
  }

  bool isFavorited(String sourceKey, String comicId) {
    return _favoritedIds.contains('$sourceKey:$comicId');
  }

  void addLocal(
    String sourceKey,
    String comicId,
    String title,
    String coverUrl, [
    String author = '',
  ]) {
    _favoritedIds.add('$sourceKey:$comicId');
    FavoritesHelper().upsert(
      FavoriteRecord(
        source: sourceKey,
        comic: comicId,
        title: title,
        cover: coverUrl,
        author: author,
        favoritedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void removeLocal(String sourceKey, String comicId) {
    _favoritedIds.remove('$sourceKey:$comicId');
    FavoritesHelper().delete(sourceKey, comicId);
  }

  void _favoritesCleared(String? sourceKey) {
    if (sourceKey == null) {
      _favoritedIds.clear();
    } else {
      _favoritedIds.removeWhere((id) => id.startsWith('$sourceKey:'));
    }
    markDirty();
  }
}

/// 收藏助手：管理本地记录，并协调远端收藏 API。
class FavoritesHelper {
  FavoritesHelper([Database? database]) : _database = database;

  final Database? _database;
  Database get _db => _database ?? JoyDatabase.instance.core;

  /// 插入收藏；同一来源、同一漫画已存在时完整更新元数据。
  void upsert(FavoriteRecord record) {
    _db.execute(
      '''
      INSERT INTO favorites
        (source_key, comic_id, title, cover_url, author, favorited_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(source_key, comic_id) DO UPDATE SET
        title = excluded.title,
        cover_url = excluded.cover_url,
        author = excluded.author,
        favorited_at = excluded.favorited_at
    ''',
      <Object?>[
        record.source,
        record.comic,
        record.title,
        record.cover,
        record.author,
        record.favoritedAt,
      ],
    );
  }

  /// 按收藏时间倒序列出记录。
  List<FavoriteRecord> list() {
    return _db
        .select(
          'SELECT * FROM favorites '
          'ORDER BY favorited_at DESC, source_key ASC, comic_id ASC',
        )
        .map(FavoriteRecord.fromRow)
        .toList();
  }

  FavoriteRecord? get(String source, String comic) {
    final rows = _db.select(
      'SELECT * FROM favorites WHERE source_key = ? AND comic_id = ?',
      <Object?>[source, comic],
    );
    return rows.isEmpty ? null : FavoriteRecord.fromRow(rows.first);
  }

  int delete(String source, String comic) {
    _db.execute(
      'DELETE FROM favorites WHERE source_key = ? AND comic_id = ?',
      <Object?>[source, comic],
    );
    return _changes();
  }

  /// 清空本地收藏。传入 [sourceKey] 时仅清理该来源。
  int clear({String? sourceKey}) {
    if (sourceKey == null) {
      _db.execute('DELETE FROM favorites');
    } else {
      _db.execute('DELETE FROM favorites WHERE source_key = ?', <Object?>[
        sourceKey,
      ]);
    }
    final deleted = _changes();
    if (deleted > 0) {
      FavoriteNotifier.instance._favoritesCleared(sourceKey);
    }
    return deleted;
  }

  int count() {
    return _db.select('SELECT COUNT(*) AS count FROM favorites').single['count']
        as int;
  }

  int _changes() {
    return _db.select('SELECT changes() AS count').single['count'] as int;
  }

  /// 切换收藏状态（API + 本地同步）。
  Future<bool> toggleFavorite({
    required String sourceKey,
    required String comicId,
    required String title,
    required String coverUrl,
  }) async {
    final wasFavorited = FavoriteNotifier.instance.isFavorited(
      sourceKey,
      comicId,
    );

    if (wasFavorited) {
      await _removeFromSource(sourceKey, comicId);
      FavoriteNotifier.instance.removeLocal(sourceKey, comicId);
      Log.i('Favorite removed', '$sourceKey/$comicId');
      return false;
    }

    await _addToSource(sourceKey, comicId);
    FavoriteNotifier.instance.addLocal(sourceKey, comicId, title, coverUrl);
    Log.i('Favorite added', '$sourceKey/$comicId');
    return true;
  }

  Future<void> _addToSource(String sourceKey, String comicId) async {
    final source = ComicSource.find(sourceKey);
    if (source?.favoriteData?.addOrDelFavorite == null) return;
    await source!.favoriteData!.addOrDelFavorite!(comicId, '', true);
  }

  Future<void> _removeFromSource(String sourceKey, String comicId) async {
    final source = ComicSource.find(sourceKey);
    if (source?.favoriteData?.addOrDelFavorite == null) return;
    await source!.favoriteData!.addOrDelFavorite!(comicId, '', false);
  }
}
