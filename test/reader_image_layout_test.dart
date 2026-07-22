import 'package:flutter/material.dart';
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

  test('ReaderImageSizeCache stores and clears sizes', () {
    ReaderImageSizeCache.clear();
    expect(ReaderImageSizeCache.get('k'), isNull);
    ReaderImageSizeCache.put('k', 100, 200);
    expect(ReaderImageSizeCache.get('k'), const Size(100, 200));
    ReaderImageSizeCache.clear();
    expect(ReaderImageSizeCache.get('k'), isNull);
  });
}
