import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/reader_v2/core/reader_v2_scheduler.dart';
import 'package:joycomic/views/reader_v2/core/reader_v2_session.dart';
import 'package:joycomic/views/reader_v2/data/reader_v2_page.dart';
import 'package:joycomic/views/reader_v2/image/reader_v2_image_provider.dart';
import 'package:joycomic/views/reader_v2/widgets/reader_v2_page_image.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  test(
    'page loader tries fallback candidates serially and transforms once',
    () async {
      final attempts = <String>[];
      var transforms = 0;
      final page = ReaderV2Page(
        index: 0,
        url: 'https://bad.example/1.webp',
        cacheKey: 'page-0',
        fallbackUrls: const ['https://good.example/1.webp'],
        bytesTransformer: (bytes) async {
          transforms += 1;
          return _png;
        },
      );
      final loader = ReaderV2PageLoader(
        candidateFetcher: (url, headers, session) async {
          attempts.add(url);
          if (url.contains('bad')) throw StateError('bad host');
          return Uint8List.fromList([0x52, 0x49, 0x46, 0x46]);
        },
      );

      final result = await loader.load(
        page,
        ReaderV2Session(traceId: 'loader'),
      );
      expect(result, _png);
      expect(attempts, [page.url, page.fallbackUrls.single]);
      expect(transforms, 1);
    },
  );

  testWidgets('page image has a non-zero loading slot then paints RawImage', (
    tester,
  ) async {
    final gate = Completer<Uint8List>();
    final session = ReaderV2Session(traceId: 'widget');
    final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 1);
    const page = ReaderV2Page(
      index: 0,
      url: 'https://example.test/1.png',
      cacheKey: 'widget-page',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          child: ReaderV2PageImage(
            page: page,
            session: session,
            scheduler: scheduler,
            priority: ReaderV2Priority.visible,
            bytesLoader: (_, _) => gate.future,
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(ReaderV2PageImage)).height,
      greaterThan(0),
    );
    expect(find.byType(RawImage), findsNothing);

    gate.complete(_png);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 5 && find.byType(RawImage).evaluate().isEmpty; i++) {
      await tester.pump();
    }
    expect(
      find.byType(RawImage),
      findsOneWidget,
      reason: session.events.map((event) => event.stage).join(' | '),
    );
    expect(session.events.any((event) => event.stage == 'frame'), isTrue);
  });
}
