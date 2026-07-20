import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/views/detail/widgets/detail_metadata.dart';

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

  test(
    'hero content uses on-image colors and has no fake heat or rating count',
    () {
      final hero = File(
        'lib/views/detail/widgets/hero_header.dart',
      ).readAsStringSync();

      expect(hero, contains('context.onImageColor'));
      expect(hero, isNot(contains('热度')));
      expect(hero, isNot(contains('人评价')));
      expect(hero, isNot(contains('ratingCount')));
    },
  );

  test('detail excludes rating-count and popularity ranking copy', () {
    final files = <File>[
      File('lib/views/detail/detail_page.dart'),
      ...Directory('lib/views/detail/widgets')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];
    final source = files.map((file) => file.readAsStringSync()).join('\n');
    for (final forbidden in const <String>[
      '人已评分',
      '人评价',
      '评分人数',
      '人气榜',
      '热度榜',
      'No.1',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, contains('RatingStars'));
  });

  testWidgets('metadata exposes 44px tappable semantics', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DetailMetadata(
            authors: const <String>['Alice'],
            categories: const <String>['青年'],
            labels: const <String>['冒险'],
            viewCount: 12000,
            likeCount: 900,
            commentCount: 37,
            chapterCount: 4,
            jmNumber: '123',
            onAuthorTap: (value) => tapped.add('author:$value'),
            onCategoryTap: (value) => tapped.add('category:$value'),
            onLabelTap: (value) => tapped.add('label:$value'),
            onJmNumberTap: () => tapped.add('jm:123'),
          ),
        ),
      ),
    );

    for (final key in const <String>[
      'detail-metadata-author-Alice',
      'detail-metadata-category-青年',
      'detail-metadata-label-冒险',
      'detail-metadata-jm-123',
    ]) {
      final finder = find.byKey(ValueKey<String>(key));
      expect(finder, findsOneWidget);
      final size = tester.getSize(finder);
      expect(size.height, greaterThanOrEqualTo(44));
      await tester.tap(finder);
    }

    expect(tapped, <String>[
      'author:Alice',
      'category:青年',
      'label:冒险',
      'jm:123',
    ]);
  });
}
