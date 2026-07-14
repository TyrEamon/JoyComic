/// 收藏状态本地追踪 + 跨页面通知。
///
/// 职责：
/// - 本地 sqlite3 记录收藏漫画元数据
/// - 提供增量同步标记，供收藏页判断是否需要刷新
library favorites_helper;

import 'package:flutter/foundation.dart';

import '../foundation/log.dart';
import '../comic_source/comic_source.dart';
import '../network/base_comic.dart';
import 'joy_database.dart';

/// 收藏状态通知器（全局单例，跨页面共享）。
///
/// 详情页收藏后通过此通知器告知收藏页刷新。
class FavoriteNotifier extends ChangeNotifier {
  FavoriteNotifier._();
  static final FavoriteNotifier instance = FavoriteNotifier._();

  /// 收藏源 key + 漫画 id 集合（用于快速判断是否已收藏）。
  final Set<String> _favoritedIds = {};

  /// 标记需要刷新（收藏页切回时检测）。
  bool _dirty = false;
  bool get isDirty => _dirty;

  /// 通知收藏页刷新。
  void markDirty() {
    _dirty = true;
    notifyListeners();
  }

  /// 收藏页已消费刷新标记。
  void consumeDirty() {
    _dirty = false;
  }

  /// 加载本地收藏 id 集合。
  void loadFromDb() {
    _favoritedIds.clear();
    final result = JoyDatabase.instance.core.select(
      'SELECT comic_id, source_key FROM favorites',
    );
    for (final r in result) {
      _favoritedIds.add('${r['source_key']}:${r['comic_id']}');
    }
  }

  /// 检查是否已本地收藏。
  bool isFavorited(String sourceKey, String comicId) {
    return _favoritedIds.contains('$sourceKey:$comicId');
  }

  /// 本地记录收藏。
  void addLocal(String sourceKey, String comicId, String title, String coverUrl) {
    _favoritedIds.add('$sourceKey:$comicId');
    JoyDatabase.instance.core.execute(
      'INSERT OR REPLACE INTO favorites (comic_id, source_key, title, cover_url, favorited_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [comicId, sourceKey, title, coverUrl, DateTime.now().millisecondsSinceEpoch],
    );
  }

  /// 本地移除收藏。
  void removeLocal(String sourceKey, String comicId) {
    _favoritedIds.remove('$sourceKey:$comicId');
    JoyDatabase.instance.core.execute(
      'DELETE FROM favorites WHERE comic_id = ? AND source_key = ?',
      [comicId, sourceKey],
    );
  }
}

/// 收藏助手：管理收藏 API 调用 + 本地同步。
class FavoritesHelper {
  /// 切换收藏状态（API + 本地同步）。
  ///
  /// 返回新的收藏状态（true=已收藏, false=未收藏）。
  Future<bool> toggleFavorite({
    required String sourceKey,
    required String comicId,
    required String title,
    required String coverUrl,
  }) async {
    // 先看本地状态
    final wasFavorited = FavoriteNotifier.instance.isFavorited(sourceKey, comicId);

    if (wasFavorited) {
      // 已收藏 → 取消：走 API，成功后删本地
      await _removeFromSource(sourceKey, comicId);
      FavoriteNotifier.instance.removeLocal(sourceKey, comicId);
      Log.i('Favorite removed', '$sourceKey/$comicId');
      return false;
    } else {
      // 未收藏 → 添加：走 API，成功后写本地
      await _addToSource(sourceKey, comicId);
      FavoriteNotifier.instance.addLocal(sourceKey, comicId, title, coverUrl);
      Log.i('Favorite added', '$sourceKey/$comicId');
      return true;
    }
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
