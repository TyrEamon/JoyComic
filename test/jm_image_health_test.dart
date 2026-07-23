import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/jm/jm_image.dart';
import 'package:joycomic/network/jm/jm_image_health.dart';

void main() {
  test('successful image host is preferred and failed host is cooled', () {
    var now = DateTime.fromMillisecondsSinceEpoch(1000);
    final health = JmImageHealth(clock: () => now);

    health.recordSuccess('cdn-good.example');
    health.recordFailure('cdn-bad.example', ImageFailure.timeout);

    expect(
      health.order(const ['cdn-bad.example', 'cdn-good.example']).first,
      'cdn-good.example',
    );
    expect(health.isCoolingDown('cdn-bad.example'), isTrue);

    now = now.add(const Duration(seconds: 10));
    expect(health.isCoolingDown('cdn-bad.example'), isFalse);
  });

  test('same image key shares the download future', () async {
    final health = JmImageHealth();
    var calls = 0;

    Future<int> download() async {
      calls += 1;
      await Future<void>.delayed(Duration.zero);
      return 3;
    }

    final result = await Future.wait([
      health.singleFlight('album/1.jpg', download),
      health.singleFlight('album/1.jpg', download),
    ]);

    expect(result, [3, 3]);
    expect(calls, 1);
  });

  test('JM candidate URLs preserve path query and remove duplicate hosts', () {
    final candidates = jmImageUrlCandidates(
      'https://cdn-msp3.jmapiproxy1.cc/media/photos/123/00001.webp?x=1',
      additionalBases: const <String>[
        'https://cdn-msp.jmapiproxy3.cc',
        'https://cdn-msp3.jmapiproxy1.cc',
      ],
    );

    expect(candidates, hasLength(5));
    expect(candidates.first, contains('cdn-msp3.jmapiproxy1.cc'));
    expect(
      candidates.any((url) => url.contains('cdn-msp.jmapiproxy3.cc')),
      isTrue,
    );
    expect(candidates.every((url) => url.endsWith('00001.webp?x=1')), isTrue);
  });

  test('non-JM image URL does not gain JM fallback hosts', () {
    expect(
      jmImageUrlCandidates('https://example.com/image.jpg'),
      const <String>['https://example.com/image.jpg'],
    );
  });
}
