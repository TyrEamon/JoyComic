import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
  final viewFiles = files
      .where((file) => file.path.contains('lib${Platform.pathSeparator}views'))
      .toList();

  test('deleted brand and palette APIs cannot return', () {
    final banned = RegExp(
      r'brandPink|brandViolet|brandGradient|gradientStart|gradientEnd|'
      r'ComicPalette|PaletteExtractor|palette_extractor',
    );
    for (final file in files) {
      expect(
        file.readAsStringSync(),
        isNot(matches(banned)),
        reason: file.path,
      );
    }
  });

  test('views contain no hexadecimal design colors', () {
    final hex = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)');
    for (final file in viewFiles) {
      expect(file.readAsStringSync(), isNot(matches(hex)), reason: file.path);
    }
  });

  test('gradients are centralized', () {
    for (final file in files) {
      if (file.path.endsWith('app_gradients.dart')) continue;
      expect(
        file.readAsStringSync(),
        isNot(contains('LinearGradient(')),
        reason: file.path,
      );
    }
  });

  test('views use semantic contrast and status colors', () {
    final fixed = RegExp(
      r'Colors\.(?:redAccent|orangeAccent|pink\w*|purple\w*|black\w*|white\w*)',
    );
    for (final file in viewFiles) {
      expect(file.readAsStringSync(), isNot(matches(fixed)), reason: file.path);
    }
  });
}
