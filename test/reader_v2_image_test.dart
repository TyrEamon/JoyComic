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

  test('page loader reuses successful transformed bytes', () async {
    var fetches = 0;
    var transforms = 0;
    final loader = ReaderV2PageLoader(
      candidateFetcher: (_, _, _) async {
        fetches += 1;
        if (fetches > 1) {
          throw StateError('network should not run twice');
        }
        return Uint8List.fromList([0x52, 0x49, 0x46, 0x46]);
      },
    );
    final page = ReaderV2Page(
      index: 0,
      url: 'https://example.test/page.webp',
      cacheKey: 'chapter-page-0',
      bytesTransformer: (_) async {
        transforms += 1;
        return _png;
      },
    );
    final session = ReaderV2Session(traceId: 'cache-test');

    expect(await loader.load(page, session), _png);
    expect(await loader.load(page, session), _png);
    expect(fetches, 1);
    expect(transforms, 1);
  });

  test('page loader evicts least recently used transformed bytes', () async {
    final fetches = <String, int>{};
    final loader = ReaderV2PageLoader(
      maxCacheBytes: _png.length * 2,
      candidateFetcher: (url, _, _) async {
        fetches.update(url, (count) => count + 1, ifAbsent: () => 1);
        return _png;
      },
    );
    ReaderV2Page page(int index) => ReaderV2Page(
      index: index,
      url: 'https://example.test/$index.png',
      cacheKey: 'chapter-page-$index',
    );
    final session = ReaderV2Session(traceId: 'cache-lru-test');

    await loader.load(page(0), session);
    await loader.load(page(1), session);
    await loader.load(page(0), session);
    await loader.load(page(2), session);
    await loader.load(page(0), session);
    await loader.load(page(1), session);

    expect(fetches['https://example.test/0.png'], 1);
    expect(fetches['https://example.test/1.png'], 2);
    expect(fetches['https://example.test/2.png'], 1);
  });

  testWidgets('page image keeps one framework Image mounted while loading', (
    tester,
  ) async {
    final gate = Completer<Uint8List>();
    var loads = 0;
    final session = ReaderV2Session(traceId: 'widget');
    final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 1);
    const page = ReaderV2Page(
      index: 0,
      url: 'https://example.test/1.png',
      cacheKey: 'widget-page',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 200,
            child: ReaderV2PageImage(
              page: page,
              session: session,
              scheduler: scheduler,
              priority: ReaderV2Priority.visible,
              bytesLoader: (_, _) {
                loads += 1;
                return gate.future;
              },
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(ReaderV2PageImage)).height,
      greaterThan(0),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ReaderV2PageImage),
        matching: find.byType(Column),
      ),
      findsOneWidget,
    );
    final loadingImageElement = tester.element(find.byType(Image));
    expect(
      find.descendant(
        of: find.byType(ReaderV2PageImage),
        matching: find.byType(Expanded),
      ),
      findsOneWidget,
    );

    gate.complete(_png);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(
      find.byType(Image),
      findsOneWidget,
      reason: session.events.map((event) => event.stage).join(' | '),
    );
    final rawImage = tester.widget<Image>(find.byType(Image));
    expect(rawImage.width, 200);
    expect(rawImage.height, 200);
    expect(tester.element(find.byType(Image)), same(loadingImageElement));
    expect(loads, 1);
    expect(session.events.any((event) => event.stage == 'frame'), isTrue);
    expect(
      session.events.any((event) => event.stage == 'paint-widget'),
      isTrue,
    );
    await tester.pump();
    final layout = session.events.where((event) => event.stage == 'layout');
    expect(layout, hasLength(1));
    expect(layout.single.detail, contains('widget=200.0x200.0'));
    expect(layout.single.detail, contains('image=200.0x200.0'));
    expect(layout.single.detail, contains('attached=true'));
    expect(layout.single.detail, contains('hasSize=true'));
  });

  testWidgets('fixed-height paged image honors centered alignment', (
    tester,
  ) async {
    final session = ReaderV2Session(traceId: 'paged-alignment');
    final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 1);
    addTearDown(scheduler.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 600,
          child: ReaderV2PageImage(
            page: const ReaderV2Page(
              index: 0,
              url: 'https://example.test/paged.png',
              cacheKey: 'paged-alignment-page',
            ),
            session: session,
            scheduler: scheduler,
            priority: ReaderV2Priority.visible,
            bytesLoader: (_, _) async => _png,
            height: 600,
            alignment: Alignment.center,
          ),
        ),
      ),
    );

    expect(
      tester.widget<Image>(find.byType(Image)).alignment,
      Alignment.center,
    );
  });

  testWidgets('flowing page image remains top aligned by default', (
    tester,
  ) async {
    final session = ReaderV2Session(traceId: 'flow-alignment');
    final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 1);
    addTearDown(scheduler.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          child: ReaderV2PageImage(
            page: const ReaderV2Page(
              index: 0,
              url: 'https://example.test/flow.png',
              cacheKey: 'flow-alignment-page',
            ),
            session: session,
            scheduler: scheduler,
            priority: ReaderV2Priority.visible,
            bytesLoader: (_, _) async => _png,
          ),
        ),
      ),
    );

    expect(
      tester.widget<Image>(find.byType(Image)).alignment,
      Alignment.topCenter,
    );
  });

  testWidgets('page image escapes a zero-width positioned-list probe', (
    tester,
  ) async {
    final session = ReaderV2Session(traceId: 'zero-width');
    final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 1);
    addTearDown(scheduler.dispose);
    const page = ReaderV2Page(
      index: 0,
      url: 'https://example.test/zero.png',
      cacheKey: 'zero-width-page',
    );

    Widget buildAtWidth(double width) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(440, 956)),
        child: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: width,
                child: ReaderV2PageImage(
                  key: const ValueKey('retained-page'),
                  page: page,
                  session: session,
                  scheduler: scheduler,
                  priority: ReaderV2Priority.visible,
                  bytesLoader: (_, _) async => _png,
                  placeholderHeight: 440,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(buildAtWidth(440));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 6 && find.byType(Image).evaluate().isEmpty; i++) {
      await tester.pump();
    }
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(buildAtWidth(0));
    await tester.pump();

    final rawImage = tester.widget<Image>(find.byType(Image));
    expect(rawImage.width, 440);
    expect(rawImage.height, 440);
    expect(tester.getSize(find.byType(Image)), const Size(440, 440));
    final pageSize = tester.getSize(find.byType(ReaderV2PageImage));
    expect(pageSize.width, 0);
    expect(pageSize.height, 440);
    expect(pageSize.height.isFinite, isTrue);
  });

  testWidgets('page image retry creates a fresh framework image stream', (
    tester,
  ) async {
    var loads = 0;
    final session = ReaderV2Session(traceId: 'retry');
    final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 1);
    addTearDown(scheduler.dispose);
    const page = ReaderV2Page(
      index: 0,
      url: 'https://example.test/retry.png',
      cacheKey: 'retry-page',
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
            bytesLoader: (_, _) async {
              loads += 1;
              if (loads == 1) throw StateError('first load failed');
              return _png;
            },
            placeholderHeight: 200,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
    expect(loads, 1);

    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(loads, 2);
    expect(find.text('重试'), findsNothing);
    expect(session.events.any((event) => event.stage == 'frame'), isTrue);
  });

  testWidgets('cancelled page image suppresses retry UI and error logs', (
    tester,
  ) async {
    final gate = Completer<Uint8List>();
    final session = ReaderV2Session(traceId: 'cancel-error');
    final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 1);
    addTearDown(scheduler.dispose);
    const page = ReaderV2Page(
      index: 0,
      url: 'https://example.test/cancel.png',
      cacheKey: 'cancel-page',
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
            placeholderHeight: 200,
          ),
        ),
      ),
    );

    session.cancel('test cancellation');
    gate.completeError(StateError('late failure'));
    await tester.pump();
    await tester.pump();

    expect(find.text('重试'), findsNothing);
    expect(
      session.events.where((event) => event.stage == 'image-error'),
      isEmpty,
    );
  });
}
