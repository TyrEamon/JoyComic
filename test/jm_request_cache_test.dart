import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/jm/jm_request_cache.dart';
import 'package:joycomic/network/res.dart';

void main() {
  test('request cache expires entries and keeps keys isolated', () async {
    var now = DateTime.fromMillisecondsSinceEpoch(1000);
    final cache = JmRequestCache(clock: () => now);
    cache.put(
      'jm:album:1',
      const Res<dynamic>({'id': '1'}),
      const Duration(seconds: 5),
    );
    expect(cache.get('jm:album:1'), isNotNull);
    expect(cache.get('jm:album:2'), isNull);
    now = now.add(const Duration(seconds: 6));
    expect(cache.get('jm:album:1'), isNull);
  });

  test('request cache never stores error responses', () {
    final cache = JmRequestCache();
    cache.put(
      'jm:album:err',
      const Res<dynamic>(null, errorMessage: 'boom'),
      const Duration(minutes: 1),
    );
    expect(cache.get('jm:album:err'), isNull);
  });

  test('request cache is bounded to 64 entries with LRU eviction', () {
    final cache = JmRequestCache();
    for (var i = 0; i < 64; i++) {
      cache.put('k$i', Res<dynamic>({'i': i}), const Duration(minutes: 1));
    }
    expect(cache.get('k0'), isNotNull);
    // Touch k0 so it becomes most-recently used.
    cache.get('k0');
    cache.put('k64', const Res<dynamic>({'i': 64}), const Duration(minutes: 1));
    expect(cache.get('k0'), isNotNull);
    expect(cache.get('k1'), isNull);
    expect(cache.get('k64'), isNotNull);
  });

  test('remove and clear drop entries', () {
    final cache = JmRequestCache();
    cache.put('a', const Res<dynamic>(1), const Duration(minutes: 1));
    cache.put('b', const Res<dynamic>(2), const Duration(minutes: 1));
    cache.remove('a');
    expect(cache.get('a'), isNull);
    expect(cache.get('b'), isNotNull);
    cache.clear();
    expect(cache.get('b'), isNull);
  });

  test(
    'cached JSON data is detached from caller-owned mutable collections',
    () {
      final cache = JmRequestCache();
      final images = <dynamic>['first.webp'];
      final payload = <String, dynamic>{'images': images};
      cache.put('album', Res<dynamic>(payload), const Duration(minutes: 1));

      images[0] = 'mutated.webp';
      payload['extra'] = true;

      final cached = cache.get('album')!.data as Map;
      expect(cached['images'], const <dynamic>['first.webp']);
      expect(cached.containsKey('extra'), isFalse);
      expect(() => cached['new'] = true, throwsUnsupportedError);
    },
  );
}
