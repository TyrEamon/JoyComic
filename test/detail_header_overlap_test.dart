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

  testWidgets('long hero title stays fully inside its visible title band', (
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
            padding: const EdgeInsets.only(top: 24),
          ),
          child: child!,
        ),
        home: const Scaffold(
          body: CustomScrollView(
            slivers: [
              HeroHeader(
                title: '【超长测试漫画标题】汉化组作品天堂1WEEKLY合集',
                subTitle: 'はいら太、なすびニンジャ、その他作者',
                backgroundCover: null,
                frontCover: null,
                rating: 8.8,
                tags: <String>['C108', '汉化'],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final titleBand = tester.getRect(
      find.byKey(const ValueKey('detail-hero-title-band')),
    );
    final titleRect = tester.getRect(
      find.byKey(const ValueKey('detail-hero-title')),
    );
    expect(titleRect.top, greaterThanOrEqualTo(titleBand.top - 0.5));
    expect(titleRect.bottom, lessThanOrEqualTo(titleBand.bottom + 0.5));
    expect(tester.takeException(), isNull);
  });
}
