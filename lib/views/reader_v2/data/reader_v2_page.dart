import '../../reader/utils/reader_image_provider.dart';

final class ReaderV2Page {
  const ReaderV2Page({
    required this.index,
    required this.url,
    required this.cacheKey,
    this.headers,
    this.fallbackUrls = const <String>[],
    this.bytesTransformer,
  });

  final int index;
  final String url;
  final String cacheKey;
  final Map<String, String>? headers;
  final List<String> fallbackUrls;
  final ReaderImageBytesTransformer? bytesTransformer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderV2Page && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}
