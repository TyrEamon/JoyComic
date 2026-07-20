import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/reader/utils/reader_image_provider.dart';
import 'package:joycomic/views/reader/utils/source_aware_image.dart';

void main() {
  test('source-aware descriptor builds JM transformer from structured config', () {
    final descriptor = SourceAwareImageDescriptor.resolve(
      imageKey: 'https://cdn.example/media/ep-1/00001.webp?token=secret',
      comicId: 'comic-1',
      episodeId: 'ep-1',
      config: <String, dynamic>{
        'url': 'https://cdn.example/media/ep-1/00001.webp?token=secret',
        'cacheKey': 'jm|comic-1|ep-1|00001',
        'headers': <String, String>{
          'Authorization': 'Bearer secret',
          'Referer': 'https://jm.example/',
        },
        'fallbackUrls': <String>['https://cdn2.example/media/ep-1/00001.webp'],
        'transform': <String, String>{
          'type': 'jm',
          'episodeId': 'ep-1',
          'imageName': '00001.webp',
        },
      },
    );

    expect(descriptor.url, contains('cdn.example'));
    expect(descriptor.cacheKey, 'jm|comic-1|ep-1|00001');
    expect(descriptor.fallbackUrls, hasLength(1));
    expect(descriptor.bytesTransformer, isNotNull);
    expect(descriptor.headers, containsPair('Referer', 'https://jm.example/'));
  });

  test('jmReaderTransformer skips GIF payloads without recombine', () async {
    final transformer = jmReaderTransformer(
      episodeId: 'ep-1',
      imageName: 'anim.gif',
    );
    expect(transformer, isNull);

    final nonGif = jmReaderTransformer(
      episodeId: 'ep-1',
      imageName: '00001.webp',
    );
    expect(nonGif, isNotNull);

    // GIF magic still short-circuits even when the name lost its extension.
    final gifBytes = Uint8List.fromList(<int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
    final out = await nonGif!(gifBytes);
    expect(out, gifBytes);
  });

  test('reader diagnostics never include credential-like header values', () {
    final message = ReaderDiagnostics.formatCandidateFailure(
      host: 'cdn.example',
      status: 403,
      contentType: 'text/html',
      byteCount: 128,
      magic: '3c 21 44 4f',
      headers: const <String, String>{
        'Authorization': 'Bearer secret-token',
        'Cookie': 'session=xyz',
      },
    );
    expect(message, contains('cdn.example'));
    expect(message, contains('403'));
    expect(message, isNot(contains('Bearer secret-token')));
    expect(message, isNot(contains('session=xyz')));
  });

  test(
    'sanitized network errors never persist tokenized URLs headers or body secrets',
    () {
      const secretUrl =
          'https://cdn.example/media/ep-1/00001.webp?token=super-secret-token&sig=abc123';
      final dioLike = Exception(
        'DioException [bad response]: '
        'uri=$secretUrl '
        'statusCode=403 '
        'headers={Authorization: Bearer secret-token, Cookie: session=xyz} '
        'Response Text: {"error":"token=super-secret-token","cookie":"session=xyz"}',
      );

      final sanitized = ReaderDiagnostics.sanitizeCaughtError(
        dioLike,
        candidateUrl: secretUrl,
        headers: const <String, String>{
          'Authorization': 'Bearer secret-token',
          'Cookie': 'session=xyz',
          'Referer': 'https://jm.example/',
        },
        statusCode: 403,
        contentType: 'application/json',
        responseBytes: Uint8List.fromList(
          'token=super-secret-token cookie=session=xyz'.codeUnits,
        ),
      );

      expect(sanitized, contains('cdn.example'));
      expect(sanitized, contains('403'));
      expect(sanitized, isNot(contains('super-secret-token')));
      expect(sanitized, isNot(contains('Bearer secret-token')));
      expect(sanitized, isNot(contains('session=xyz')));
      expect(sanitized, isNot(contains('token=')));
      expect(sanitized, isNot(contains(secretUrl)));
      expect(sanitized.toLowerCase(), isNot(contains('authorization')));
      // Body previews are forbidden entirely.
      expect(sanitized, isNot(contains('Response Text')));
      expect(sanitized, isNot(contains('preview=')));
    },
  );

  test('readerImageProvider carries traceId and imageIndex on network path', () {
    final provider = readerImageProvider(
      url: 'https://cdn.example/a.webp',
      cacheKey: 'k1',
      cacheWidth: 1080,
      traceId: 'traceabc12',
      imageIndex: 7,
    );
    ImageProvider network = provider;
    if (provider is ResizeImage) {
      network = provider.imageProvider;
    }
    expect(network, isA<ReaderNetworkImageProvider>());
    final net = network as ReaderNetworkImageProvider;
    expect(net.traceId, 'traceabc12');
    expect(net.imageIndex, 7);
  });

  test(
    'cacheKeySummary never echoes token/sig/secret substrings for short or long keys',
    () {
      const shortSecret = 'token=secret';
      const longSecret =
          'https://cdn.example/media/ep-1/00001.webp?token=super-secret-token&sig=abc123&cookie=session';

      final shortSummary = ReaderDiagnostics.cacheKeySummary(shortSecret);
      final longSummary = ReaderDiagnostics.cacheKeySummary(longSecret);

      // Deterministic one-way form: length + stable hash only.
      expect(shortSummary, startsWith('len='));
      expect(longSummary, startsWith('len='));
      expect(shortSummary, contains('h='));
      expect(longSummary, contains('h='));

      for (final summary in [shortSummary, longSummary]) {
        expect(summary, isNot(contains('token')));
        expect(summary, isNot(contains('secret')));
        expect(summary, isNot(contains('sig=')));
        expect(summary, isNot(contains('super-secret')));
        expect(summary, isNot(contains('cdn.example')));
        expect(summary, isNot(contains('cookie')));
      }

      // Same input always yields the same summary.
      expect(
        ReaderDiagnostics.cacheKeySummary(longSecret),
        longSummary,
      );
      // Different inputs must not collide trivially via passthrough.
      expect(
        ReaderDiagnostics.cacheKeySummary('safe-key'),
        isNot(equals(shortSummary)),
      );
    },
  );

  test('redactUrl never echoes token-like raw non-URI strings', () {
    expect(
      ReaderDiagnostics.redactUrl('token=super-secret-token'),
      isNot(contains('super-secret-token')),
    );
    expect(
      ReaderDiagnostics.redactUrl('Bearer secret-token'),
      isNot(contains('secret-token')),
    );
    expect(
      ReaderDiagnostics.redactUrl('Cookie: session=xyz'),
      isNot(contains('session=xyz')),
    );
    expect(
      ReaderDiagnostics.redactUrl('path/img.webp?token=secret&sig=abc'),
      isNot(contains('token=secret')),
    );
    expect(
      ReaderDiagnostics.redactUrl('path/img.webp?token=secret&sig=abc'),
      isNot(contains('sig=abc')),
    );
  });
}
