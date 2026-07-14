import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('source contains no empty on* callbacks or stale mock comments', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final source = files.map((file) => file.readAsStringSync()).join('\n');
    final emptyCallback = RegExp(
      r'on[A-Z][A-Za-z0-9_]*\s*:\s*\([^)]*\)\s*(?:async\s*)?\{\s*\}',
      multiLine: true,
    );

    expect(source, isNot(matches(emptyCallback)));
    expect(source, isNot(contains('mock 阶段')));
    expect(source, isNot(contains('当前全 mock')));
    expect(source, isNot(contains('保持 mock')));
  });
}
