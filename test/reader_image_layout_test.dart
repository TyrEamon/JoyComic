import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/reader/widgets/reader_image.dart';
import 'package:joycomic/views/reader/widgets/vertical_list/vertical_list.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ReaderImage default fit is contain', () {
    const image = ReaderImage(url: 'https://example.com/a.webp');
    expect(image.fit, BoxFit.contain);
  });

  test('ReaderImage is StatefulWidget (Haka-style paint path)', () {
    const image = ReaderImage(url: 'https://example.com/a.webp');
    expect(image, isA<StatefulWidget>());
  });

  test('vertical viewport uses bounded size and requested width ratio', () {
    final size = resolveVerticalReaderViewportSize(
      const BoxConstraints.tightFor(width: 800, height: 600),
      const Size(440, 956),
      0.5,
    );
    expect(size, const Size(400, 600));
  });

  test('vertical viewport falls back to MediaQuery instead of zero size', () {
    final size = resolveVerticalReaderViewportSize(
      const BoxConstraints(),
      const Size(440, 956),
      1,
    );
    expect(size, const Size(440, 956));
  });

  testWidgets('vertical reader viewport escapes a zero-width parent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(440, 956)),
          child: RepaintBoundary(
            key: const ValueKey('reader-viewport-paint'),
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 0,
                    child: VerticalReaderViewport(
                      size: const Size(440, 956),
                      child: ListView(
                        children: const [
                          SizedBox(
                            key: ValueKey('reader-page'),
                            height: 621,
                            child: ColoredBox(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(ListView)), const Size(440, 956));
    expect(
      tester.getSize(find.byKey(const ValueKey('reader-page'))),
      const Size(440, 621),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('reader-page'))),
      Offset.zero,
    );

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('reader-viewport-paint')),
    );
    final pixels = await tester.runAsync(() async {
      final painted = await boundary.toImage(pixelRatio: 1);
      final rgba = await painted.toByteData(format: ui.ImageByteFormat.rawRgba);
      painted.dispose();
      expect(rgba, isNotNull);
      return rgba!.buffer.asUint8List();
    });
    expect(pixels, isNotNull);
    expect(pixels![0], greaterThan(200));
    expect(pixels[1], lessThan(100));
    expect(pixels[2], lessThan(100));
    expect(pixels[3], 255);
  });

  test('ReaderImageSizeCache stores and clears sizes', () {
    ReaderImageSizeCache.clear();
    expect(ReaderImageSizeCache.get('k'), isNull);
    ReaderImageSizeCache.put('k', 100, 200);
    expect(ReaderImageSizeCache.get('k'), const Size(100, 200));
    ReaderImageSizeCache.clear();
    expect(ReaderImageSizeCache.get('k'), isNull);
  });
}
