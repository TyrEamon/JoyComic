import '../json_value.dart';
import 'jm_models.dart';

/// Converts one decrypted JM detail payload into a model without performing I/O.
///
/// This internal parser is public only so the network adapter and package tests share
/// one response boundary. It is intentionally not exported by the network facade.
JmComicInfo? parseJmComicInfoResponse(Object? rawData, {required String id}) {
  if (rawData is! Map) return null;
  final data = jsonMap(rawData);

  final author = jsonStringList(data['author']);
  if (author.isEmpty) author.add('未知');

  final series = <int, String>{};
  final epNames = <String>[];
  for (final rawSeries in jsonList(data['series'])) {
    if (rawSeries is! Map) continue;
    final chapter = jsonMap(rawSeries);
    final chapterId = jsonString(chapter['id']);
    if (chapterId.isEmpty) continue;
    final order = series.length + 1;
    series[order] = chapterId;
    final remoteOrder = jsonInt(chapter['sort'], fallback: order);
    final name = jsonString(chapter['name']);
    epNames.add(name.isEmpty ? '第$remoteOrder話' : name);
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
    description: jsonString(data['description']),
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
    favorite: jsonBool(data['is_favorite']),
    comments: jsonInt(
      data['comment_total'] ?? data['comment'] ?? data['comments'],
    ),
    epNames: epNames,
  );
}
