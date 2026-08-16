import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/theme/app_spacing.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/views/detail/widgets/detail_metadata.dart';
import 'package:joycomic/views/detail/widgets/hero_header.dart';

void main() {
  testWidgets('hero backdrop stops before the first metadata row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              const HeroHeader(
                title: 'Comic',
                subTitle: 'Author',
                backgroundCover: null,
                frontCover: null,
                rating: 8.8,
                tags: <String>['C108'],
              ),
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: AppSpacing.md),
                    DetailMetadata(
                      authors: const <String>['Author'],
                      categories: const <String>[],
                      labels: const <String>['C108'],
                      viewCount: 13000,
                      likeCount: 1601,
                      commentCount: 18,
                      chapterCount: 1,
                      jmNumber: '1460988',
                      onAuthorTap: (_) {},
                      onCategoryTap: (_) {},
                      onLabelTap: (_) {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final backdrop = tester.getRect(
      find.byKey(const ValueKey('detail-hero-backdrop')),
    );
    final firstMetric = tester.getRect(find.text('1.3万 阅读'));
    expect(backdrop.bottom, lessThanOrEqualTo(firstMetric.top));
    expect(tester.takeException(), isNull);
  });
}
