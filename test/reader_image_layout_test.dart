import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/reader/widgets/reader_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ReaderImage default fit is fitWidth', () {
    final image = ReaderImage(url: 'https://example.com/a.webp');
    expect(image.fit, BoxFit.fitWidth);
  });

  test('ReaderImage is StatefulWidget', () {
    final image = ReaderImage(url: 'https://example.com/a.webp');
    expect(image, isA<StatefulWidget>());
    expect(image.image, isA<ImageProvider>());
  });
}
