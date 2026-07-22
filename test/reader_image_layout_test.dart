import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/reader/widgets/reader_image.dart';

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

  test('ReaderImageSizeCache stores and clears sizes', () {
    ReaderImageSizeCache.clear();
    expect(ReaderImageSizeCache.get('k'), isNull);
    ReaderImageSizeCache.put('k', 100, 200);
    expect(ReaderImageSizeCache.get('k'), const Size(100, 200));
    ReaderImageSizeCache.clear();
    expect(ReaderImageSizeCache.get('k'), isNull);
  });
}
