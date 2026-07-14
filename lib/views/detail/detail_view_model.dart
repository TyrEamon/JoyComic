/// 详情页 ViewModel：编排数据加载与封面取色。
///
/// 职责：
/// - 接收 [ComicSource] key + comicId，调 `loadComicInfo` 拿 [ComicInfoData]
/// - 异步从封面取色 [ComicPalette]（失败回退品牌色）
/// - 暴露加载态 [DetailLoadState]
///
/// 不直接依赖具体源网络层，全部走 ComicSource 声明式契约。
/// 阶段4 接 DB 后在此注入收藏态持久化。
library;

import 'package:flutter/foundation.dart';

import '../../comic_source/comic_source.dart';
import '../../database/favorites_helper.dart';
import '../../foundation/log.dart';
import '../../foundation/palette_extractor.dart';

/// 详情页加载状态。
enum DetailLoadState { idle, loading, success, error }

/// 详情页 UI 数据快照（与 ComicInfoData 解耦的视图模型）。
class DetailUiData {
  const DetailUiData({required this.info, required this.palette});
  final ComicInfoData info;
  final ComicPalette palette;
}

class DetailViewModel extends ChangeNotifier {
  DetailViewModel({
    required this.sourceKey,
    required this.comicId,
    FavoritesHelper? favoritesHelper,
  }) : _favHelper = favoritesHelper ?? FavoritesHelper();

  final String sourceKey;
  final String comicId;

  final FavoritesHelper _favHelper;

  DetailLoadState _state = DetailLoadState.idle;
  DetailLoadState get state => _state;

  DetailUiData? _data;
  DetailUiData? get data => _data;

  String? _error;
  String? get error => _error;

  bool _isFavorite = false;
  bool get isFavorite => _isFavorite;

  /// 评论列表。
  List<Comment> _comments = const [];
  List<Comment> get comments => _comments;

  /// 评论总数（来自 subData）。
  int _commentTotal = 0;
  int get commentTotal => _commentTotal;

  /// 评论是否已加载。
  bool _commentsLoaded = false;
  bool get commentsLoaded => _commentsLoaded;

  /// 封面图鉴权 headers（来源的 getThumbnailLoadingConfig）。
  Map<String, dynamic>? get coverHeaders {
    final cover = _data?.info.cover;
    if (cover == null) return null;
    final source = ComicSource.find(sourceKey);
    if (source?.getThumbnailLoadingConfig == null) return null;
    return source!.getThumbnailLoadingConfig!(cover);
  }

  Future<void> load() async {
    if (_state == DetailLoadState.loading) return;

    _state = DetailLoadState.loading;
    _error = null;
    notifyListeners();

    final source = ComicSource.find(sourceKey);
    if (source == null || source.loadComicInfo == null) {
      _state = DetailLoadState.error;
      _error = '未找到漫画源：$sourceKey';
      notifyListeners();
      return;
    }

    try {
      final res = await source.loadComicInfo!(comicId);
      if (res.error) {
        _state = DetailLoadState.error;
        _error = res.errorMessage ?? '加载失败';
        Log.e('Detail load failed', error: res.errorMessage);
        notifyListeners();
        return;
      }
      final info = res.data;

      _applyFavoriteState(info);
      Log.i('Detail loaded', '$comicId - ${info.title}');

      // 先以兜底色铺好，UI 立即可渲染；取色完成后再平滑替换。
      _data = DetailUiData(info: info, palette: ComicPalette.fallback);
      _state = DetailLoadState.success;
      notifyListeners();

      // 后台取色（不阻塞首屏）。
      final headers = source.getThumbnailLoadingConfig?.call(info.cover);
      final palette = await PaletteExtractor.extract(
        info.cover,
        headers: headers,
      );
      if (_data != null && _data!.info == info) {
        _data = DetailUiData(info: info, palette: palette);
        notifyListeners();
      }

      // 后台加载评论（不阻塞首屏）。
      loadComments();
    } catch (e) {
      _state = DetailLoadState.error;
      _error = e.toString();
      notifyListeners();
    }
  }

  String get author {
    final info = _data?.info;
    if (info == null) return '';
    return _authorOf(info);
  }

  String _authorOf(ComicInfoData info) {
    final values = info.tags['作者'] ?? info.tags['author'] ?? const <String>[];
    return values.join('、');
  }

  void _applyFavoriteState(ComicInfoData info) {
    final notifier = FavoriteNotifier.instance;
    final isLocal = notifier.isFavorited(sourceKey, info.comicId);
    if (info.isFavorite == true && !isLocal) {
      final author = _authorOf(info);
      _favHelper.upsert(
        FavoriteRecord(
          source: sourceKey,
          comic: info.comicId,
          title: info.title,
          cover: info.cover,
          author: author,
          favoritedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      notifier.addLocal(
        sourceKey,
        info.comicId,
        info.title,
        info.cover,
        author,
      );
    }
    _isFavorite = info.isFavorite == true || isLocal;
  }

  /// 切换收藏态（远端成功后才更新本地）。
  Future<void> toggleFavorite() async {
    final info = _data?.info;
    if (info == null) return;

    final newState = await _favHelper.toggleFavorite(
      sourceKey: sourceKey,
      comicId: info.comicId,
      title: info.title,
      coverUrl: info.cover,
      author: _authorOf(info),
    );
    _isFavorite = newState;

    notifyListeners();
  }

  /// 加载评论。
  Future<void> loadComments() async {
    if (_commentsLoaded) return;
    final source = ComicSource.find(sourceKey);
    if (source?.commentsLoader == null) return;
    final res = await source!.commentsLoader!(comicId, null, 1, null);
    if (res.error) return;
    _comments = res.data;
    _commentTotal = res.subData is int ? res.subData as int : _comments.length;
    _commentsLoaded = true;
    notifyListeners();
  }

  Future<void> reload() async {
    _state = DetailLoadState.idle;
    _data = null;
    _error = null;
    notifyListeners();
    await load();
  }
}
