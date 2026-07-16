/// Immutable JM video API models.
library;

import '../json_value.dart';

class JmVideoItem {
  JmVideoItem({
    required this.id,
    required this.title,
    required this.photo,
    required List<String> tags,
    required this.backlink,
  }) : tags = List<String>.unmodifiable(tags);

  final String id;
  final String title;
  final String photo;
  final List<String> tags;
  final String backlink;

  factory JmVideoItem.fromJson(
    Map<String, dynamic> json, {
    required String imageBaseUrl,
  }) => JmVideoItem(
    id: jsonString(json['id'] ?? json['vid'] ?? json['_id']),
    title: jsonString(json['title']),
    photo: normalizeJmVideoUrl(jsonString(json['photo']), imageBaseUrl),
    tags: jsonStringList(json['tags']),
    backlink: jsonString(json['backlink'] ?? json['full_url']),
  );
}

class JmVideoDetail {
  JmVideoDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.photo,
    required this.videoSrc,
    required this.fullUrl,
    required List<String> tags,
    required this.backlink,
    required List<JmVideoItem> relatedVideos,
  }) : tags = List<String>.unmodifiable(tags),
       relatedVideos = List<JmVideoItem>.unmodifiable(relatedVideos);

  final String id;
  final String title;
  final String description;
  final String photo;
  final String videoSrc;
  final String fullUrl;
  final List<String> tags;
  final String backlink;
  final List<JmVideoItem> relatedVideos;

  factory JmVideoDetail.fromJson(
    Map<String, dynamic> json, {
    required String imageBaseUrl,
  }) {
    final video = jsonMap(json['video']).isNotEmpty
        ? jsonMap(json['video'])
        : json;
    final relatedRaw = json['related_videos'];
    if (relatedRaw != null && relatedRaw is! List) {
      throw const FormatException('related_videos must be a list');
    }
    final relatedVideos = <JmVideoItem>[];
    for (final raw in jsonList(relatedRaw)) {
      if (raw is! Map) {
        throw const FormatException('related_videos item must be an object');
      }
      final item = JmVideoItem.fromJson(
        jsonMap(raw),
        imageBaseUrl: imageBaseUrl,
      );
      if (item.id.isEmpty && item.title.isEmpty) {
        throw const FormatException('related_videos item is empty');
      }
      relatedVideos.add(item);
    }
    return JmVideoDetail(
      id: jsonString(video['vid'] ?? video['id'] ?? video['_id']),
      title: jsonString(video['title']),
      description: jsonString(video['description']),
      photo: normalizeJmVideoUrl(jsonString(video['photo']), imageBaseUrl),
      videoSrc: jsonString(video['video_src']),
      fullUrl: jsonString(video['full_url'] ?? video['backlink']),
      tags: jsonStringList(video['tags']),
      backlink: jsonString(video['backlink']),
      relatedVideos: relatedVideos,
    );
  }
}

String normalizeJmVideoUrl(String value, String imageBaseUrl) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('//')) return 'https:$trimmed';
  final uri = Uri.tryParse(trimmed);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return trimmed;
  }
  if (uri != null && uri.hasScheme) return '';
  final base = Uri.tryParse(imageBaseUrl.trim());
  if (base == null || !base.hasScheme) return trimmed;
  return base.resolve(trimmed).toString();
}
