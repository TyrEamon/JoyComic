import '../../reader/utils/source_aware_image.dart';
import 'reader_v2_page.dart';

typedef ReaderV2ImageConfigResolver =
    Map<String, dynamic>? Function(
      String imageKey,
      String comicId,
      String episodeId,
    );

final class ReaderV2DataAdapter {
  const ReaderV2DataAdapter._();

  static List<ReaderV2Page> resolvePages({
    required Iterable<String> imageKeys,
    required String comicId,
    required String episodeId,
    ReaderV2ImageConfigResolver? resolver,
  }) {
    final pages = <ReaderV2Page>[];
    for (final rawKey in imageKeys) {
      final imageKey = rawKey.trim();
      if (imageKey.isEmpty) continue;
      final descriptor = SourceAwareImageDescriptor.resolve(
        imageKey: imageKey,
        comicId: comicId,
        episodeId: episodeId,
        config: resolver?.call(imageKey, comicId, episodeId),
      );
      if (descriptor.url.isEmpty || descriptor.cacheKey.isEmpty) continue;
      pages.add(
        ReaderV2Page(
          index: pages.length,
          url: descriptor.url,
          cacheKey: descriptor.cacheKey,
          headers: descriptor.headers,
          fallbackUrls: descriptor.fallbackUrls,
          bytesTransformer: descriptor.bytesTransformer,
        ),
      );
    }
    return List<ReaderV2Page>.unmodifiable(pages);
  }
}
