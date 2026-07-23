import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/video/hls_quality.dart';

void main() {
  test('only m3u8 URLs are probed as HLS manifests', () {
    expect(
      isHlsManifestCandidate(Uri.parse('https://cdn.example/master.M3U8?q=1')),
      isTrue,
    );
    expect(
      isHlsManifestCandidate(Uri.parse('https://cdn.example/movie.mp4')),
      isFalse,
    );
  });

  test('manifest reader rejects responses above its byte limit', () async {
    await expectLater(
      readHlsManifest(
        Stream<List<int>>.value(List<int>.filled(9, 65)),
        maxBytes: 8,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'master playlist exposes sorted resolution variants and resolves URLs',
    () {
      const manifest = '''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5200000,RESOLUTION=1920x1080
../1080/index.m3u8?token=kept
#EXT-X-STREAM-INF:BANDWIDTH=2600000,RESOLUTION=1280x720
https://cdn.example/720/index.m3u8
''';

      final variants = parseHlsVariants(
        manifest,
        Uri.parse('https://media.example/path/master.m3u8?token=secret'),
      );

      expect(variants.map((variant) => variant.label), <String>[
        '1080p',
        '720p',
        '360p',
      ]);
      expect(
        variants.first.uri.toString(),
        'https://media.example/1080/index.m3u8?token=kept',
      );
      expect(variants.first.bandwidth, 5200000);
    },
  );

  test('media playlist has no selectable quality variants', () {
    const manifest = '''#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:6.0,
segment-001.ts
''';

    expect(
      parseHlsVariants(
        manifest,
        Uri.parse('https://media.example/720/index.m3u8'),
      ),
      isEmpty,
    );
  });

  test('non-HLS text cannot expose variants', () {
    expect(
      parseHlsVariants(
        '#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=640x360\nvideo.m3u8',
        Uri.parse('https://media.example/master.m3u8'),
      ),
      isEmpty,
    );
  });
}
