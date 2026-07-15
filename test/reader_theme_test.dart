import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reader controls centralize contrast colors and gradients', () {
    const paths = <String>[
      'lib/views/reader/reader.dart',
      'lib/views/reader/widgets/app_bar.dart',
      'lib/views/reader/widgets/bottom.dart',
      'lib/views/reader/widgets/menu_lock.dart',
      'lib/views/reader/widgets/page_no_tag.dart',
      'lib/views/reader/widgets/toast.dart',
    ];
    final fixedContrast = RegExp(r'Colors\.(?:black\w*|white\w*)');

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('LinearGradient(')), reason: path);
      expect(source, isNot(matches(fixedContrast)), reason: path);
    }

    expect(
      File('lib/views/reader/widgets/app_bar.dart').readAsStringSync(),
      contains('AppGradients.readerScrimTop'),
    );
    expect(
      File('lib/views/reader/widgets/bottom.dart').readAsStringSync(),
      contains('AppGradients.readerScrimBottom'),
    );
  });
}
