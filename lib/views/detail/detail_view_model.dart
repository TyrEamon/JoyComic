/// 详情页 ViewModel：编排漫画详情、收藏与评论加载。
///
/// 职责：
/// - 接收 [ComicSource] key + comicId，调 `loadComicInfo` 拿 [ComicInfoData]
/// - 暴露加载态 [DetailLoadState]
///
/// 不直接依赖具体源网络层，全部走 ComicSource 声明式契约。
/// 阶段4 接 DB 后在此注入收藏态持久化。
library;

import 'package:flutter/foundation.dart';

import '../../comic_source/comic_source.dart';
import '../../database/favorites_helper.dart';
import '../../foundation/log.dart';

/// 详情页加载状态。
enum DetailLoadState { idle, loading, success, error }

/// 详情页 UI 数据快照（与 ComicInfoData 解耦的视图模型）。
class DetailUiData {
  const DetailUiData({required this.info});
  final ComicInfoData info;
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
  bool _disposed = false;
  int _commentGeneration = 0;

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

  /// 评论分页状态。
  bool _commentsLoaded = false;
  bool get commentsLoaded => _commentsLoaded;
  bool _commentsLoading = false;
  bool get commentsLoading => _commentsLoading;
  bool _hasMoreComments = false;
  bool get hasMoreComments => _hasMoreComments;
  int _commentPage = 0;
  bool get canLoadComments =>
      ComicSource.find(sourceKey)?.commentsLoader != null;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _commentGeneration++;
    super.dispose();
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  /// 封面图鉴权 headers（来源的 getThumbnailLoadingConfig）。
  Map<String, dynamic>? get coverHeaders {
    final cover = _data?.info.cover;
    if (cover == null) return null;
    final source = ComicSource.find(sourceKey);
    if (source?.getThumbnailLoadingConfig == null) return null;
    return source!.getThumbnailLoadingConfig!(cover);
  }

  Future<void> load() async {
    if (_disposed || _state == DetailLoadState.loading) return;

    _state = DetailLoadState.loading;
    _error = null;
    _notifyListeners();

    final source = ComicSource.find(sourceKey);
    if (source == null || source.loadComicInfo == null) {
      _state = DetailLoadState.error;
      _error = '未找到漫画源：$sourceKey';
      _notifyListeners();
      return;
    }

    try {
      final res = await source.loadComicInfo!(comicId);
      if (_disposed) return;
      if (res.error) {
        _state = DetailLoadState.error;
        _error = res.errorMessage ?? '加载失败';
        Log.e('Detail load failed', error: res.errorMessage);
        _notifyListeners();
        return;
      }
      final info = res.data;

      _applyFavoriteState(info);
      Log.i('Detail loaded', '$comicId - ${info.title}');

      _data = DetailUiData(info: info);
      _state = DetailLoadState.success;
      _notifyListeners();

      // 后台加载评论（不阻塞首屏）。
      loadComments();
    } catch (e) {
      if (_disposed) return;
      _state = DetailLoadState.error;
      _error = e.toString();
      _notifyListeners();
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
    if (_disposed) return;
    final info = _data?.info;
    if (info == null) return;

    final newState = await _favHelper.toggleFavorite(
      sourceKey: sourceKey,
      comicId: info.comicId,
      title: info.title,
      coverUrl: info.cover,
      author: _authorOf(info),
    );
    if (_disposed) return;
    _isFavorite = newState;

    _notifyListeners();
  }

  /// Loads the first comment page.
  Future<void> loadComments() async {
    if (_disposed || _commentsLoaded || _commentsLoading) return;
    await _loadCommentsPage(1, replace: true);
  }

  /// Loads the next comment page when the remote total has not been reached.
  Future<void> loadMoreComments() async {
    if (_disposed || _commentsLoading || !_hasMoreComments) return;
    await _loadCommentsPage(_commentPage + 1, replace: false);
  }

  Future<void> _loadCommentsPage(int page, {required bool replace}) async {
    if (_disposed) return;
    final generation = _commentGeneration;
    final source = ComicSource.find(sourceKey);
    final loader = source?.commentsLoader;
    if (loader == null) return;
    _commentsLoading = true;
    _notifyListeners();
    try {
      final res = await loader(comicId, null, page, null);
      if (_disposed || generation != _commentGeneration || res.error) return;
      final incoming = res.data;
      if (replace) {
        _comments = List<Comment>.of(incoming);
      } else {
        final knownIds = _comments
            .map((comment) => comment.id)
            .whereType<String>()
            .toSet();
        _comments = <Comment>[
          ..._comments,
          for (final comment in incoming)
            if (comment.id == null || knownIds.add(comment.id!)) comment,
        ];
      }
      final remoteTotal = res.subData is int ? res.subData as int : null;
      if (remoteTotal != null) _commentTotal = remoteTotal;
      if (_commentTotal == 0) _commentTotal = _comments.length;
      _commentPage = page;
      _commentsLoaded = true;
      _hasMoreComments =
          incoming.isNotEmpty &&
          (remoteTotal == null || _comments.length < remoteTotal);
    } finally {
      if (!_disposed && generation == _commentGeneration) {
        _commentsLoading = false;
        _notifyListeners();
      }
    }
  }

  Future<void> reload() async {
    if (_disposed) return;
    _commentGeneration++;
    _state = DetailLoadState.idle;
    _data = null;
    _error = null;
    _comments = const <Comment>[];
    _commentTotal = 0;
    _commentPage = 0;
    _commentsLoaded = false;
    _commentsLoading = false;
    _hasMoreComments = false;
    _notifyListeners();
    await load();
  }
}
