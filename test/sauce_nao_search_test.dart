import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/foundation/sauce_nao_config_store.dart';
import 'package:joycomic/foundation/sauce_nao_search.dart';
import 'package:joycomic/foundation/source_credential_store.dart';

void main() {
  late Directory tempDirectory;
  late File image;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('saucenao-test-');
    image = await File(
      '${tempDirectory.path}/image.jpg',
    ).writeAsBytes(<int>[1]);
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'secure API key takes precedence over compile-time environment',
    () async {
      final backend = _MemorySecretStore();
      final store = SauceNaoConfigStore(
        store: backend,
        environmentApiKey: 'environment-key',
      );
      await store.saveApiKey(' secure-key ');

      expect(await store.readApiKey(), 'secure-key');
      await store.clearApiKey();
      expect(await store.readApiKey(), 'environment-key');
    },
  );

  test('missing API key is a typed error', () async {
    final search = SauceNaoSearch(
      transport: (_, __) async => throw StateError('must not call transport'),
    );

    await expectLater(
      search.search(image, apiKey: '   '),
      throwsA(
        isA<SauceNaoException>().having(
          (error) => error.kind,
          'kind',
          SauceNaoErrorKind.missingKey,
        ),
      ),
    );
  });

  for (final entry in <int, SauceNaoErrorKind>{
    403: SauceNaoErrorKind.invalidKey,
    429: SauceNaoErrorKind.rateLimited,
  }.entries) {
    test('HTTP ${entry.key} maps to ${entry.value.name}', () async {
      final search = SauceNaoSearch(
        transport: (_, __) async => SauceNaoHttpResponse(
          statusCode: entry.key,
          data: const <String, dynamic>{},
        ),
      );

      await expectLater(
        search.search(image, apiKey: 'configured-key'),
        throwsA(
          isA<SauceNaoException>().having(
            (error) => error.kind,
            'kind',
            entry.value,
          ),
        ),
      );
    });
  }

  for (final scenario
      in <({Map<String, Object?> header, SauceNaoErrorKind kind})>[
        (
          header: <String, Object?>{
            'status': -1,
            'message': 'The anonymous account type does not permit API usage.',
          },
          kind: SauceNaoErrorKind.invalidKey,
        ),
        (
          header: <String, Object?>{
            'status': -2,
            'message': 'Daily Search Limit Exceeded.',
            'long_remaining': -1,
          },
          kind: SauceNaoErrorKind.rateLimited,
        ),
      ]) {
    test('HTTP 200 business error maps to ${scenario.kind.name}', () async {
      final search = SauceNaoSearch(
        transport: (_, __) async => SauceNaoHttpResponse(
          statusCode: 200,
          data: <String, Object?>{'header': scenario.header},
        ),
      );

      await expectLater(
        search.search(image, apiKey: 'configured-key'),
        throwsA(
          isA<SauceNaoException>().having(
            (error) => error.kind,
            'kind',
            scenario.kind,
          ),
        ),
      );
    });
  }

  test('transport failure maps to network error', () async {
    final search = SauceNaoSearch(
      transport: (_, __) async => throw const SocketException('offline'),
    );

    await expectLater(
      search.search(image, apiKey: 'configured-key'),
      throwsA(
        isA<SauceNaoException>().having(
          (error) => error.kind,
          'kind',
          SauceNaoErrorKind.network,
        ),
      ),
    );
  });

  test('malformed successful payload is a typed error', () async {
    final search = SauceNaoSearch(
      transport: (_, __) async => const SauceNaoHttpResponse(
        statusCode: 200,
        data: <String, dynamic>{'results': 'not-a-list'},
      ),
    );

    await expectLater(
      search.search(image, apiKey: 'configured-key'),
      throwsA(
        isA<SauceNaoException>().having(
          (error) => error.kind,
          'kind',
          SauceNaoErrorKind.malformed,
        ),
      ),
    );
  });

  test('search parses original results and sends the injected key', () async {
    String? sentKey;
    final search = SauceNaoSearch(
      transport: (_, key) async {
        sentKey = key;
        return const SauceNaoHttpResponse(
          statusCode: 200,
          data: <String, dynamic>{
            'results': <Map<String, dynamic>>[
              <String, dynamic>{
                'header': <String, dynamic>{
                  'similarity': '91.5',
                  'thumbnail': 'https://img.example/thumb.jpg',
                  'index_name': 'Pixiv',
                },
                'data': <String, dynamic>{
                  'title': 'Original title',
                  'author_name': 'Author',
                  'ext_urls': <String>['https://example.com/work'],
                },
              },
            ],
          },
        );
      },
    );

    final results = await search.search(image, apiKey: 'configured-key');

    expect(sentKey, 'configured-key');
    expect(results.single.title, 'Original title');
    expect(results.single.extUrls, <String>['https://example.com/work']);
  });

  test('bestTitle sorts a copy and preserves caller order', () {
    final results = <SauceResult>[
      const SauceResult(
        similarity: 20,
        thumbnail: '',
        source: 'low',
        title: 'Low',
      ),
      const SauceResult(
        similarity: 90,
        thumbnail: '',
        source: 'high',
        title: 'High',
      ),
    ];

    expect(SauceNaoSearch.bestTitle(results), 'High');
    expect(results.map((result) => result.source), <String>['low', 'high']);
  });

  test('service source contains no default API key constant', () {
    final source = File(
      'lib/foundation/sauce_nao_search.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('kDefaultApiKey')));
    expect(source, isNot(matches(RegExp(r'[0-9a-f]{40}'))));
  });
}

class _MemorySecretStore implements SecretKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
