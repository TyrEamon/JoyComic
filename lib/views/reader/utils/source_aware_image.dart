/// Source-aware image descriptor shared by the reader and detail chapter thumbs.
///
/// Built from [ComicSource.getImageLoadingConfig] so JM detail thumbnails reuse
/// the same URL / cache key / headers / fallbacks / transformer path as the
/// reader without duplicating scramble logic.
library;

import 'reader_image_provider.dart';

/// Immutable image load contract for network (or file) comic images.
class SourceAwareImageDescriptor {
  const SourceAwareImageDescriptor({
    required this.url,
    required this.cacheKey,
    this.headers,
    this.fallbackUrls = const <String>[],
    this.bytesTransformer,
  });

  final String url;
  final String cacheKey;
  final Map<String, String>? headers;
  final List<String> fallbackUrls;
  final ReaderImageBytesTransformer? bytesTransformer;

  bool get hasTransformer => bytesTransformer != null;

  /// Resolve a structured descriptor from source config + raw image key.
  ///
  /// When [config] is null or empty, falls back to headers-only or raw URL.
  static SourceAwareImageDescriptor resolve({
    required String imageKey,
    required String comicId,
    required String episodeId,
    Map<String, dynamic>? config,
    Map<String, dynamic>? thumbnailHeaders,
  }) {
    final key = imageKey.trim();
    if (key.isEmpty) {
      return const SourceAwareImageDescriptor(url: '', cacheKey: '');
    }

    final hasStructuredKeys = config != null &&
        (config.containsKey('url') ||
            config.containsKey('headers') ||
            config.containsKey('cacheKey') ||
            config.containsKey('method') ||
            config.containsKey('fallbackUrls') ||
            config.containsKey('transform'));

    final configuredUrl = config?['url'];
    final url = configuredUrl is String && configuredUrl.trim().isNotEmpty
        ? configuredUrl.trim()
        : key;

    final configuredCacheKey = config?['cacheKey'];
    final cacheKey =
        configuredCacheKey is String && configuredCacheKey.trim().isNotEmpty
        ? configuredCacheKey.trim()
        : 'src|$comicId|$episodeId|$key';

    // Structured configs only use their headers entry; non-structured may fall
    // back to thumbnail headers (headers-only sources).
    final Object? headerSource = hasStructuredKeys
        ? config['headers']
        : (config ?? thumbnailHeaders);
    final headers = _stringHeaders(headerSource);

    final fallbackUrls = <String>[];
    final rawFallbacks = config?['fallbackUrls'];
    if (rawFallbacks is Iterable) {
      for (final fallback in rawFallbacks) {
        if (fallback is String && fallback.trim().isNotEmpty) {
          fallbackUrls.add(fallback.trim());
        }
      }
    }

    ReaderImageBytesTransformer? bytesTransformer;
    final transform = config?['transform'];
    if (transform is Map && transform['type']?.toString() == 'jm') {
      final transformEpisode = transform['episodeId']?.toString() ?? '';
      final transformImageName = transform['imageName']?.toString() ?? '';
      if (transformEpisode.isNotEmpty && transformImageName.isNotEmpty) {
        bytesTransformer = jmReaderTransformer(
          episodeId: transformEpisode,
          imageName: transformImageName,
        );
      }
    }

    return SourceAwareImageDescriptor(
      url: url,
      cacheKey: cacheKey,
      headers: headers,
      fallbackUrls: List<String>.unmodifiable(fallbackUrls),
      bytesTransformer: bytesTransformer,
    );
  }

  static Map<String, String>? _stringHeaders(Object? value) {
    if (value is! Map) return null;
    final headers = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is String && entry.value != null) {
        headers[entry.key as String] = entry.value.toString();
      }
    }
    return headers.isEmpty ? null : Map<String, String>.unmodifiable(headers);
  }
}
