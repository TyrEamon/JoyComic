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

  test('Codemagic injects idempotent iOS image-picker permissions', () {
    final source = File('codemagic.yaml').readAsStringSync();
    final createIndex = source.indexOf('flutter create . --platforms=ios');
    final photoAdd = source.indexOf(
      'Add :NSPhotoLibraryUsageDescription string 选择漫画图片用于以图搜图',
    );
    final photoSet = source.indexOf(
      'Set :NSPhotoLibraryUsageDescription 选择漫画图片用于以图搜图',
    );
    final cameraAdd = source.indexOf(
      'Add :NSCameraUsageDescription string 拍摄漫画图片用于以图搜图',
    );
    final cameraSet = source.indexOf(
      'Set :NSCameraUsageDescription 拍摄漫画图片用于以图搜图',
    );

    expect(createIndex, greaterThanOrEqualTo(0));
    for (final permissionIndex in <int>[
      photoAdd,
      photoSet,
      cameraAdd,
      cameraSet,
    ]) {
      expect(permissionIndex, greaterThan(createIndex));
    }
  });

  test('SauceNAO source contains no credential-like constants', () {
    const paths = <String>[
      'lib/foundation/sauce_nao_config_store.dart',
      'lib/foundation/sauce_nao_search.dart',
      'lib/views/image_search/image_search_page.dart',
    ];
    final credentialConstant = RegExp(
      r'''(?:api[_-]?key|token|secret)\w*\s*=\s*['"][A-Za-z0-9_-]{20,}['"]''',
      caseSensitive: false,
    );
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('kDefaultApiKey')), reason: path);
      expect(source, isNot(matches(credentialConstant)), reason: path);
    }
  });
}
