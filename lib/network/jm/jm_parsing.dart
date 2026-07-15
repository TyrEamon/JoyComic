import '../../foundation/detail_text.dart';
import '../json_value.dart';
import 'jm_models.dart';

/// Converts one decrypted JM detail payload into a model without performing I/O.
///
/// This internal parser is public only so the network adapter and package tests
/// share one response boundary. It is intentionally not exported by the network
/// facade.
JmComicInfo? parseJmComicInfoResponse(Object? rawData, {required String id}) {
  if (rawData is! Map) return null;
  final data = jsonMap(rawData);

  final author = jsonStringList(data['author']);
  if (author.isEmpty) author.add('未知');

  final rawChapters = <_RawJmChapter>[];
  final rawSeries = jsonList(data['series']);
  for (var index = 0; index < rawSeries.length; index++) {
    final rawChapter = rawSeries[index];
    if (rawChapter is! Map) continue;
    final chapter = jsonMap(rawChapter);
    final chapterId = jsonString(chapter['id']).trim();
    if (chapterId.isEmpty) continue;
    rawChapters.add(
      _RawJmChapter(
        originalIndex: index,
        chapterId: chapterId,
        name: jsonString(chapter['name']).trim(),
        remoteOrder: _positiveJsonInt(chapter['sort']),
        pageCount: _parseJmChapterPageCount(chapter),
      ),
    );
  }

  final usedOrders = <int>{};
  for (final chapter in rawChapters) {
    final remoteOrder = chapter.remoteOrder;
    if (remoteOrder != null && usedOrders.add(remoteOrder)) {
      chapter.assignedOrder = remoteOrder;
    }
  }
  var nextUnusedOrder = 1;
  final unassigned =
      rawChapters.where((chapter) => chapter.assignedOrder == null).toList()
        ..sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
  for (final chapter in unassigned) {
    while (usedOrders.contains(nextUnusedOrder)) {
      nextUnusedOrder++;
    }
    chapter.assignedOrder = nextUnusedOrder;
    usedOrders.add(nextUnusedOrder);
    nextUnusedOrder++;
  }

  final parsedChapters = <JmChapter>[
    for (final chapter in rawChapters)
      JmChapter(
        order: chapter.assignedOrder!,
        chapterId: chapter.chapterId,
        title: chapter.name.isEmpty
            ? '第${chapter.assignedOrder!}話'
            : chapter.name,
        pageCount: chapter.pageCount,
      ),
  ]..sort((a, b) => a.order.compareTo(b.order));
  final series = <int, String>{
    for (final chapter in parsedChapters) chapter.order: chapter.chapterId,
  };
  final epNames = <String>[for (final chapter in parsedChapters) chapter.title];

  final images = <String>[];
  for (final rawImage in _jmImageValues(data['images'])) {
    final image = switch (rawImage) {
      String value => value.trim(),
      Map value => jsonString(jsonMap(value)['image']).trim(),
      _ => '',
    };
    if (image.isNotEmpty) images.add(image);
  }

  final categories = <String>[];
  for (final key in const <String>['category', 'category_sub']) {
    _collectJmCategoryNames(data[key], categories);
  }

  final related = <JmComicBrief>[];
  for (final rawRelated in jsonList(data['related_list'])) {
    if (rawRelated is! Map) continue;
    final comic = JmComicBrief.fromJson(jsonMap(rawRelated));
    if (comic.id.isEmpty) continue;
    related.add(comic);
  }

  return JmComicInfo(
    name: jsonString(data['name'], fallback: 'Unknown'),
    id: id,
    author: author,
    description: normalizeDetailText(jsonString(data['description'])),
    likes: jsonInt(data['likes']),
    views: jsonInt(data['total_views'] ?? data['totalViews'] ?? data['views']),
    series: series,
    tags: jsonStringList(data['tags']),
    works: jsonStringList(data['works']),
    actors: jsonStringList(data['actors']),
    relatedComics: related,
    liked: jsonBool(
      data['liked'] ?? (data['likes'] is bool ? data['likes'] : null),
    ),
    favorite: jsonBool(data['is_favorite'] ?? data['favorite']),
    comments: jsonInt(
      data['comment_total'] ?? data['comment'] ?? data['comments'],
    ),
    epNames: epNames,
    seriesId: _nullableJsonInt(data['series_id']),
    images: images,
    categories: categories,
    chapters: parsedChapters,
  );
}

Iterable<Object?> _jmImageValues(Object? value) {
  if (value == null) return const <Object?>[];
  return value is List ? value : <Object?>[value];
}

int? _nullableJsonInt(Object? value) {
  if (value is int) return value;
  if (value is num) {
    if (!value.isFinite || value != value.truncateToDouble()) return null;
    return value.toInt();
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

int? _positiveJsonInt(Object? value) {
  final parsed = _nullableJsonInt(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

int? _parseJmChapterPageCount(Map<String, dynamic> chapter) {
  for (final value in <Object?>[
    chapter['page_count'],
    chapter['pageCount'],
    chapter['photo_count'],
    chapter['photoCount'],
    chapter['photos'],
  ]) {
    if (value is List) {
      if (value.isNotEmpty) return value.length;
      continue;
    }
    final count = _positiveJsonInt(value);
    if (count != null) return count;
  }
  return null;
}

void _collectJmCategoryNames(Object? rawValue, List<String> output) {
  final values = rawValue is List ? rawValue : <Object?>[rawValue];
  for (final value in values) {
    final name = value is Map
        ? jsonString(jsonMap(value)['title'] ?? jsonMap(value)['name']).trim()
        : jsonString(value).trim();
    if (name.isNotEmpty && !output.contains(name)) output.add(name);
  }
}

class _RawJmChapter {
  _RawJmChapter({
    required this.originalIndex,
    required this.chapterId,
    required this.name,
    required this.remoteOrder,
    required this.pageCount,
  });

  final int originalIndex;
  final String chapterId;
  final String name;
  final int? remoteOrder;
  final int? pageCount;
  int? assignedOrder;
}
