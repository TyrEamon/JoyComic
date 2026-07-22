import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/reader/widgets/reader_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ReaderImage default fit is fitWidth', () {
    const image = ReaderImage(url: 'https://example.com/a.webp');
    expect(image.fit, BoxFit.fitWidth);
  });

  test('ReaderImage is StatefulWidget with size cache', () {
    const image = ReaderImage(url: 'https://example.com/a.webp');
    expect(image, isA<StatefulWidget>());
  });

  test('ReaderImageSizeCache stores pixel size', () {
    ReaderImageSizeCache.clear();
    ReaderImageSizeCache.put('k', 960, 1378);
    final s = ReaderImageSizeCache.get('k');
    expect(s, isNotNull);
    expect(s!.width, 960);
    expect(s.height, 1378);
  });
}
