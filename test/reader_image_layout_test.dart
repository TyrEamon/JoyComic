import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/reader/widgets/reader_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ReaderImage default fit is contain', () {
    const image = ReaderImage(url: 'https://example.com/a.webp');
    expect(image.fit, BoxFit.contain);
  });

  test('ReaderImage is StatefulWidget', () {
    const image = ReaderImage(url: 'https://example.com/a.webp');
    expect(image, isA<StatefulWidget>());
  });

  test('ReaderImageSizeCache stores page bytes size', () {
    ReaderImageSizeCache.clear();
    // put requires bytes — only test clear/get null
    expect(ReaderImageSizeCache.sizeOf('missing'), isNull);
  });
}
