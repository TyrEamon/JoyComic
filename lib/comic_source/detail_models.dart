import '../network/base_comic.dart';
import '../network/res.dart';
import 'history.dart';

class ComicChapter {
  const ComicChapter({
    required this.id,
    required this.title,
    required this.order,
    this.pageCount,
  });

  final String id;
  final String title;
  final int order;
  final int? pageCount;
}

class CommentReplyTarget {
  const CommentReplyTarget({required this.id, required this.userName});

  final String id;
  final String userName;
}

class Comment {
  /// Compatibility constructor for existing const callsites.
  ///
  /// Const callers necessarily provide const collection values. Runtime
  /// production boundaries should use [Comment.snapshot].
  const Comment(
    this.userName,
    this.avatar,
    this.content,
    this.time, [
    int? legacyReplyCount,
    this.id,
    this.likeCount = 0,
    this.isLiked = false,
    this.replies = const <Comment>[],
  ]) : replyCount = legacyReplyCount ?? 0;

  Comment.snapshot(
    this.userName,
    this.avatar,
    this.content,
    this.time, [
    int? legacyReplyCount,
    this.id,
    this.likeCount = 0,
    this.isLiked = false,
    List<Comment> replies = const <Comment>[],
  ]) : replyCount = legacyReplyCount ?? 0,
       replies = List<Comment>.unmodifiable(replies);

  final String userName;
  final String? avatar;
  final String content;
  final String? time;
  final int replyCount;
  final String? id;
  final int likeCount;
  final bool isLiked;
  final List<Comment> replies;
}

class CommentPageData {
  CommentPageData({
    required List<Comment> comments,
    required this.page,
    required this.totalPages,
    required this.totalComments,
  }) : comments = List<Comment>.unmodifiable(comments);

  final List<Comment> comments;
  final int page;
  final int totalPages;
  final int totalComments;

  bool get hasMore => page < totalPages;
}

class ComicInfoData with HistoryMixin {
  /// Compatibility constructor for existing const callsites.
  ///
  /// Const callers necessarily provide const collection values. Runtime
  /// production boundaries should use [ComicInfoData.snapshot].
  const ComicInfoData({
    required this.title,
    required this.subTitle,
    required this.cover,
    required this.description,
    required this.tags,
    required this.chapters,
    required this.thumbnails,
    this.thumbnailLoader,
    this.thumbnailMaxPage = 0,
    this.suggestions,
    required this.sourceKey,
    required this.comicId,
    this.isFavorite,
    this.subId,
    this.authors = const <String>[],
    this.categories = const <String>[],
    this.labels = const <String>[],
    this.viewCount,
    this.likeCount,
    this.commentCount,
    this.sourceRating,
    this.isLiked,
    this.chapterList = const <ComicChapter>[],
    this.singleChapterPages,
  });

  ComicInfoData.snapshot({
    required this.title,
    required this.subTitle,
    required this.cover,
    required this.description,
    required Map<String, List<String>> tags,
    required Map<String, String>? chapters,
    required List<String>? thumbnails,
    this.thumbnailLoader,
    this.thumbnailMaxPage = 0,
    List<BaseComic>? suggestions,
    required this.sourceKey,
    required this.comicId,
    this.isFavorite,
    this.subId,
    List<String> authors = const <String>[],
    List<String> categories = const <String>[],
    List<String> labels = const <String>[],
    this.viewCount,
    this.likeCount,
    this.commentCount,
    this.sourceRating,
    this.isLiked,
    List<ComicChapter> chapterList = const <ComicChapter>[],
    List<String>? singleChapterPages,
  }) : tags = _freezeTags(tags),
       chapters = chapters == null
           ? null
           : Map<String, String>.unmodifiable(Map<String, String>.of(chapters)),
       thumbnails = thumbnails == null
           ? null
           : List<String>.unmodifiable(thumbnails),
       suggestions = suggestions == null
           ? null
           : List<BaseComic>.unmodifiable(suggestions),
       authors = List<String>.unmodifiable(authors),
       categories = List<String>.unmodifiable(categories),
       labels = List<String>.unmodifiable(labels),
       chapterList = List<ComicChapter>.unmodifiable(chapterList),
       singleChapterPages = singleChapterPages == null
           ? null
           : List<String>.unmodifiable(singleChapterPages);

  @override
  final String title;
  @override
  final String? subTitle;
  final String cover;
  @override
  final String? description;

  /// Compatibility metadata retained for existing source adapters.
  final Map<String, List<String>> tags;

  /// Legacy chapter mapping from chapter id to title.
  final Map<String, String>? chapters;
  final List<String>? thumbnails;
  final Future<Res<List<String>>> Function(String id, int page)?
  thumbnailLoader;
  final int thumbnailMaxPage;
  final List<BaseComic>? suggestions;
  final String sourceKey;
  final String comicId;
  final bool? isFavorite;
  final String? subId;

  final List<String> authors;
  final List<String> categories;
  final List<String> labels;
  final int? viewCount;
  final int? likeCount;
  final int? commentCount;
  final double? sourceRating;
  final bool? isLiked;
  final List<ComicChapter> chapterList;
  final List<String>? singleChapterPages;

  @override
  HistoryType get historyType => HistoryType.fromKey(sourceKey);

  @override
  String get target => comicId;
}

Map<String, List<String>> _freezeTags(Map<String, List<String>> tags) {
  return Map<String, List<String>>.unmodifiable({
    for (final entry in tags.entries)
      entry.key: List<String>.unmodifiable(entry.value),
  });
}
