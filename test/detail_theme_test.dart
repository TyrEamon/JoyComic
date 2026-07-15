import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detail implementation has no dynamic palette dependency', () {
    final files = <File>[
      File('lib/views/detail/detail_view_model.dart'),
      File('lib/views/detail/detail_page.dart'),
      ...Directory('lib/views/detail/widgets')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('ComicPalette')), reason: file.path);
      expect(source, isNot(contains('PaletteExtractor')), reason: file.path);
      expect(source, isNot(contains('palette.gradient')), reason: file.path);
      expect(source, isNot(contains('palette.accent')), reason: file.path);
    }
  });
}
