/// 详情页 ViewModel：编排漫画详情、收藏、评论与章节资源加载。
///
/// 不直接依赖具体源网络层，全部走 ComicSource 声明式契约。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pool/pool.dart';

import '../../comic_source/comic_source.dart';
import '../../database/favorites_helper.dart';
import '../../database/read_record_helper.dart';
import '../../foundation/detail_rating.dart';
import '../../foundation/log.dart';
import '../../network/res.dart';
import '../reader/utils/source_aware_image.dart';

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
    ReadRecordHelper? readRecordHelper,
  }) : _favHelper = favoritesHelper ?? FavoritesHelper(),
       _readRecordHelper = readRecordHelper ?? ReadRecordHelper() {
    ReadRecordNotifier.instance.addListener(_handleReadRecordChanged);
  }

  final String sourceKey;
  final String comicId;

  final FavoritesHelper _favHelper;
  final ReadRecordHelper _readRecordHelper;
  final Pool _thumbnailPool = Pool(3);
  final Map<String, Future<Res<List<String>>>> _chapterPageRequests =
      <String, Future<Res<List<String>>>>{};
  final Map<String, Future<SourceAwareImageDescriptor?>>
  _chapterThumbnailRequests = <String, Future<SourceAwareImageDescriptor?>>{};

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

  List<ComicChapter> get chapters =>
      _data?.info.chapterList ?? const <ComicChapter>[];

  double? get rating {
    final info = _data?.info;
    if (info == null) return null;
    return calculateDetailRating(
      views: info.viewCount,
      likes: info.likeCount,
      sourceRating: info.sourceRating,
    );
  }

  /// 评论列表。
  List<Comment> _comments = const <Comment>[];
  List<Comment> get comments => _comments;

  /// 评论总数优先来自详情接口，评论页激活后由分页元数据更新。
  int _commentTotal = 0;
  int get commentTotal => _commentTotal;

  bool _commentsActivated = false;
  bool _commentsLoaded = false;
  bool get commentsLoaded => _commentsLoaded;
  bool _commentsLoading = false;
  bool get commentsLoading => _commentsLoading;
  bool _hasMoreComments = false;
  bool get hasMoreComments => _hasMoreComments;
  int _commentPage = 0;
  bool get canLoadComments =>
      ComicSource.find(sourceKey)?.commentsLoader != null;

  CommentReplyTarget? _replyTarget;
  CommentReplyTarget? get replyTarget => _replyTarget;

  bool _commentSending = false;
  bool get commentSending => _commentSending;

  String? _commentSendError;
  String? get commentSendError => _commentSendError;

  ReadRecord? get readRecord => _readRecordHelper.get(sourceKey, comicId);
  bool get hasReadProgress => readRecord != null;
  String get readActionLabel => hasReadProgress ? '继续阅读' : '开始阅读';

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ReadRecordNotifier.instance.removeListener(_handleReadRecordChanged);
    _commentGeneration++;
    unawaited(_thumbnailPool.close());
    super.dispose();
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  void _handleReadRecordChanged() => _notifyListeners();

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
      _data = DetailUiData(info: info);
      _commentTotal = info.commentCount ?? 0;
      _state = DetailLoadState.success;
      Log.i('Detail loaded', '$comicId - ${info.title}');
      _notifyListeners();
    } catch (error) {
      if (_disposed) return;
      _state = DetailLoadState.error;
      _error = error.toString();
      _notifyListeners();
    }
  }

  String get author {
    final info = _data?.info;
    if (info == null) return '';
    return _authorOf(info);
  }

  String _authorOf(ComicInfoData info) {
    if (info.authors.isNotEmpty) return info.authors.join('、');
    return info.subTitle?.trim() ?? '';
  }

  void _applyFavoriteState(ComicInfoData info) {
    final notifier = FavoriteNotifier.instance;
    final isLocal = notifier.isFavorited(sourceKey, info.comicId);
    if (info.isFavorite == true || isLocal) {
      final author = _authorOf(info);
      final existing = _favHelper.get(sourceKey, info.comicId);
      _favHelper.upsert(
        FavoriteRecord(
          source: sourceKey,
          comic: info.comicId,
          title: info.title,
          cover: info.cover,
          author: author,
          authors: info.authors,
          tags: info.labels,
          metadataComplete: true,
          favoritedAt:
              existing?.favoritedAt ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!isLocal) {
        notifier.addLocal(
          sourceKey,
          info.comicId,
          info.title,
          info.cover,
          author,
        );
      }
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
      authors: info.authors,
      tags: info.labels,
      metadataComplete: true,
    );
    if (_disposed) return;
    _isFavorite = newState;
    _notifyListeners();
  }

  /// 评论 Tab 首次激活时才加载第一页。
  Future<void> activateComments() async {
    if (_disposed) return;
    _commentsActivated = true;
    if (_commentsLoaded || _commentsLoading) return;
    await _loadCommentsPage(1, replace: true);
  }

  /// 兼容旧调用点；语义等同于激活评论区。
  Future<void> loadComments() => activateComments();

  /// Loads the next comment page when the typed page reports more data.
  Future<void> loadMoreComments() async {
    if (_disposed || _commentsLoading || !_hasMoreComments) return;
    await _loadCommentsPage(_commentPage + 1, replace: false);
  }

  void beginReply(Comment comment) {
    final id = comment.id?.trim();
    if (_disposed || id == null || id.isEmpty) return;
    _replyTarget = CommentReplyTarget(id: id, userName: comment.userName);
    _commentSendError = null;
    _notifyListeners();
  }

  void cancelReply() {
    if (_disposed || _replyTarget == null) return;
    _replyTarget = null;
    _commentSendError = null;
    _notifyListeners();
  }

  Future<bool> sendComment(String content) async {
    if (_disposed || _commentSending) return false;
    final normalized = content.trim();
    if (normalized.isEmpty) {
      _commentSendError = '评论内容不能为空';
      _notifyListeners();
      return false;
    }
    final source = ComicSource.find(sourceKey);
    final sender = source?.sendCommentFunc;
    if (sender == null) {
      _commentSendError = '当前漫画源不支持评论';
      _notifyListeners();
      return false;
    }

    _commentSending = true;
    _commentSendError = null;
    _notifyListeners();
    try {
      final res = await sender(
        comicId,
        _data?.info.subId,
        normalized,
        _replyTarget,
      );
      if (_disposed) return false;
      if (res.error || res.dataOrNull != true) {
        _commentSendError = res.errorMessage ?? '评论发送失败';
        return false;
      }

      _replyTarget = null;
      _commentSendError = null;
      if (_commentsActivated && canLoadComments) {
        await _reloadCommentPageOne();
      }
      return true;
    } catch (error) {
      if (!_disposed) _commentSendError = error.toString();
      return false;
    } finally {
      if (!_disposed) {
        _commentSending = false;
        _notifyListeners();
      }
    }
  }

  Future<void> _reloadCommentPageOne() async {
    _commentGeneration++;
    _comments = const <Comment>[];
    _commentPage = 0;
    _commentsLoaded = false;
    _commentsLoading = false;
    _hasMoreComments = false;
    await _loadCommentsPage(1, replace: true);
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
      final res = await loader(comicId, _data?.info.subId, page, null);
      if (_disposed || generation != _commentGeneration || res.error) return;
      final pageData = res.data;
      final incoming = pageData.comments;
      if (replace) {
        _comments = List<Comment>.unmodifiable(incoming);
      } else {
        final knownIds = _comments
            .map((comment) => comment.id)
            .whereType<String>()
            .toSet();
        _comments = List<Comment>.unmodifiable(<Comment>[
          ..._comments,
          for (final comment in incoming)
            if (comment.id == null || knownIds.add(comment.id!)) comment,
        ]);
      }
      _commentTotal = pageData.totalComments;
      _commentPage = pageData.page;
      _commentsLoaded = true;
      _hasMoreComments = pageData.hasMore;
    } finally {
      if (!_disposed && generation == _commentGeneration) {
        _commentsLoading = false;
        _notifyListeners();
      }
    }
  }

  Future<Res<List<String>>> loadChapterPages(ComicChapter chapter) {
    return _chapterPageRequests.putIfAbsent(chapter.id, () {
      final inlinePages = _data?.info.singleChapterPages;
      // Absolute inline URLs can skip the source. Relative JM names (00001.webp)
      // must go through loadComicPages so hosts + unpaid chapter/CDN apply.
      if (inlinePages != null &&
          inlinePages.isNotEmpty &&
          _allAbsoluteHttpUrls(inlinePages)) {
        return Future<Res<List<String>>>.value(
          Res<List<String>>(List<String>.unmodifiable(inlinePages)),
        );
      }
      final loader = ComicSource.find(sourceKey)?.loadComicPages;
      if (loader == null) {
        if (inlinePages != null && inlinePages.isNotEmpty) {
          return Future<Res<List<String>>>.value(
            Res<List<String>>(List<String>.unmodifiable(inlinePages)),
          );
        }
        return Future<Res<List<String>>>.value(
          const Res<List<String>>(null, errorMessage: '当前漫画源不支持章节阅读'),
        );
      }
      return _loadRemoteChapterPages(loader, chapter);
    });
  }

  bool _allAbsoluteHttpUrls(List<String> pages) {
    for (final page in pages) {
      final uri = Uri.tryParse(page.trim());
      if (uri == null ||
          !(uri.scheme == 'http' || uri.scheme == 'https') ||
          uri.host.isEmpty) {
        return false;
      }
    }
    return true;
  }

  Future<Res<List<String>>> _loadRemoteChapterPages(
    LoadComicPagesFunc loader,
    ComicChapter chapter,
  ) async {
    try {
      final res = await loader(comicId, chapter.id);
      if (res.error) {
        _chapterPageRequests.remove(chapter.id);
        return Res<List<String>>(null, errorMessage: res.errorMessage);
      }
      return Res<List<String>>(List<String>.unmodifiable(res.data));
    } catch (error) {
      _chapterPageRequests.remove(chapter.id);
      return Res<List<String>>(null, errorMessage: error.toString());
    }
  }

  /// Source-aware first-page thumbnail for chapter cards.
  ///
  /// Routes through [ComicSource.getImageLoadingConfig] so JM thumbs use the
  /// same scramble transformer / cache key / fallbacks as the reader.
  Future<SourceAwareImageDescriptor?> loadChapterThumbnailDescriptor(
    ComicChapter chapter,
  ) {
    return _chapterThumbnailRequests.putIfAbsent(
      chapter.id,
      () => _thumbnailPool.withResource(
        () => _loadChapterThumbnailDescriptor(chapter),
      ),
    );
  }

  /// Back-compat alias used only by tests that still call the old name.
  Future<String?> loadChapterThumbnail(ComicChapter chapter) async {
    final descriptor = await loadChapterThumbnailDescriptor(chapter);
    return descriptor?.url;
  }

  Future<SourceAwareImageDescriptor?> _loadChapterThumbnailDescriptor(
    ComicChapter chapter,
  ) async {
    final imageKey = await _chapterThumbnailImageKey(chapter);
    if (imageKey == null || imageKey.isEmpty) return null;

    final source = ComicSource.find(sourceKey);
    Map<String, dynamic>? config;
    final resolver = source?.getImageLoadingConfig;
    if (resolver != null) {
      config = resolver(imageKey, comicId, chapter.id);
    }
    // Headers-only fallback when the source has no structured page config.
    final thumbnailHeaders = source?.getThumbnailLoadingConfig?.call(imageKey);

    return SourceAwareImageDescriptor.resolve(
      imageKey: imageKey,
      comicId: comicId,
      episodeId: chapter.id,
      config: config,
      thumbnailHeaders: thumbnailHeaders,
    );
  }

  Future<String?> _chapterThumbnailImageKey(ComicChapter chapter) async {
    final direct = _directChapterThumbnail(chapter);
    if (direct != null) return direct;
    final pages = await loadChapterPages(chapter);
    if (pages.error || pages.data.isEmpty) return null;
    final first = pages.data.first.trim();
    return first.isEmpty ? null : first;
  }

  String? _directChapterThumbnail(ComicChapter chapter) {
    final info = _data?.info;
    final thumbnails = info?.thumbnails;
    if (info == null || thumbnails == null) return null;
    final index = info.chapterList.indexWhere((item) => item.id == chapter.id);
    if (index < 0 || index >= thumbnails.length) return null;
    final thumbnail = thumbnails[index].trim();
    return thumbnail.isEmpty ? null : thumbnail;
  }

  Future<void> reload() async {
    if (_disposed) return;
    final reactivateComments = _commentsActivated;
    _commentGeneration++;
    _state = DetailLoadState.idle;
    _data = null;
    _error = null;
    _comments = const <Comment>[];
    _commentTotal = 0;
    _commentPage = 0;
    _commentsActivated = false;
    _commentsLoaded = false;
    _commentsLoading = false;
    _hasMoreComments = false;
    _replyTarget = null;
    _commentSendError = null;
    _chapterPageRequests.clear();
    _chapterThumbnailRequests.clear();
    _notifyListeners();
    await load();
    if (reactivateComments && _state == DetailLoadState.success) {
      unawaited(activateComments());
    }
  }
}
