import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/reader_v2/data/reader_v2_data_adapter.dart';

void main() {
  test('adapter preserves structured source image configuration', () {
    final pages = ReaderV2DataAdapter.resolvePages(
      imageKeys: const ['raw-key'],
      comicId: 'comic',
      episodeId: 'episode',
      resolver: (key, comic, episode) => {
        'url': 'https://cdn.example/page.webp',
        'cacheKey': 'cache-page-1',
        'headers': {'Referer': 'https://example.test'},
        'fallbackUrls': [
          'https://fallback-1.example/page.webp',
          'https://fallback-2.example/page.webp',
        ],
        'transform': {
          'type': 'jm',
          'episodeId': 'episode',
          'imageName': '00001.webp',
        },
      },
    );

    expect(pages, hasLength(1));
    final page = pages.single;
    expect(page.index, 0);
    expect(page.url, 'https://cdn.example/page.webp');
    expect(page.cacheKey, 'cache-page-1');
    expect(page.headers, {'Referer': 'https://example.test'});
    expect(page.fallbackUrls, hasLength(2));
    expect(page.bytesTransformer, isNotNull);
  });

  test('adapter creates stable raw descriptors without a resolver', () {
    final pages = ReaderV2DataAdapter.resolvePages(
      imageKeys: const ['https://cdn.example/1.jpg', 'file:///tmp/2.jpg'],
      comicId: 'comic',
      episodeId: 'episode',
    );

    expect(pages.map((page) => page.index), [0, 1]);
    expect(pages.first.url, 'https://cdn.example/1.jpg');
    expect(pages.first.cacheKey, contains('comic'));
    expect(pages.last.url, 'file:///tmp/2.jpg');
    expect(pages.last.bytesTransformer, isNull);
  });

  test('adapter drops blank image keys', () {
    final pages = ReaderV2DataAdapter.resolvePages(
      imageKeys: const ['', '  ', 'https://cdn.example/1.jpg'],
      comicId: 'comic',
      episodeId: 'episode',
    );

    expect(pages, hasLength(1));
    expect(pages.single.index, 0);
  });
}
