import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/detail_models.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/views/common/widgets/rating_stars.dart';
import 'package:joycomic/views/detail/widgets/comment_preview.dart';
import 'package:joycomic/views/detail/widgets/detail_actions.dart';
import 'package:joycomic/views/detail/widgets/detail_app_bar.dart';
import 'package:joycomic/views/detail/widgets/detail_loading_skeleton.dart';
import 'package:joycomic/views/detail/widgets/detail_metadata.dart';
import 'package:joycomic/views/detail/widgets/detail_hero_geometry.dart';
import 'package:joycomic/views/detail/widgets/hero_header.dart';
import 'package:joycomic/views/detail/widgets/recent_chapter_strip.dart';
import 'package:joycomic/views/detail/widgets/recommendation_carousel.dart';
import 'package:joycomic/views/detail/widgets/synopsis_block.dart';
import 'package:joycomic/theme/app_spacing.dart';

void main() {
  group('detail hero geometry contract', () {
    test('mobile 3:4 cover places surface at two-thirds cover height', () {
      final geometry = DetailHeroGeometry.calculate(
        layoutWidth: 375,
        appBarReserved: 76,
        coverAspectRatio: 3 / 4,
        sectionSpacing: AppSpacing.md,
      );

      expect(
        geometry.surfaceTop,
        closeTo(geometry.coverTop + geometry.coverHeight * 2 / 3, 1.0),
      );
      expect(geometry.coverBottom, greaterThan(geometry.surfaceTop));
      expect(geometry.coverBottom, lessThanOrEqualTo(geometry.totalHeight));
      expect(
        geometry.metadataTop,
        closeTo(geometry.coverBottom + AppSpacing.md, 1.0),
      );
      expect(
        geometry.metadataTop - geometry.coverBottom,
        closeTo(AppSpacing.md, 1.0),
      );
    });

    test(
      'large text title band bottoms at cover and stays below app bar band',
      () {
        final geometry = DetailHeroGeometry.calculate(
          layoutWidth: 375,
          appBarReserved: 76,
          coverAspectRatio: 3 / 4,
          textScale: 1.3,
          sectionSpacing: AppSpacing.md,
        );

        expect(
          geometry.titleBandBottom,
          lessThanOrEqualTo(geometry.coverBottom),
        );
        expect(geometry.titleBandTop, greaterThanOrEqualTo(76));
        expect(geometry.titleBandBottom, greaterThan(geometry.titleBandTop));
        expect(
          geometry.titleBandTop,
          greaterThanOrEqualTo(geometry.appBarReserved),
        );
      },
    );
  });

  testWidgets('hero floats the cover across backdrop and content surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: CustomScrollView(
            slivers: [
              HeroHeader(
                title: 'Comic',
                subTitle: 'Author',
                backgroundCover: null,
                frontCover: null,
                rating: 8.8,
                tags: <String>['冒险', '奇幻'],
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('detail-hero-backdrop')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-hero-surface')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-floating-cover')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-hero-rating')), findsOneWidget);
    expect(find.text('8.8'), findsOneWidget);
    expect(find.byType(RatingStars), findsOneWidget);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final cover = tester.getRect(
      find.byKey(const ValueKey('detail-floating-cover')),
    );
    final titleBand = tester.getRect(
      find.byKey(const ValueKey('detail-hero-title-band')),
    );
    final rating = tester.getRect(
      find.byKey(const ValueKey('detail-hero-rating')),
    );
    // Right column matches cover height; rating is centered in lower 1/3.
    expect(titleBand.top, closeTo(cover.top, 1.5));
    expect(titleBand.bottom, closeTo(cover.bottom, 1.5));
    final lowerThirdTop = cover.top + cover.height * 2 / 3;
    final lowerThirdCenter = (lowerThirdTop + cover.bottom) / 2;
    expect(rating.center.dy, closeTo(lowerThirdCenter, 6));
    expect(rating.top, greaterThanOrEqualTo(lowerThirdTop - 2));
    expect(rating.bottom, lessThanOrEqualTo(cover.bottom + 2));
  });

  testWidgets(
    'hero surface seam follows two-thirds cover rule across breakpoints',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Future<void> assertSeamAt(Size size) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(padding: const EdgeInsets.only(top: 24)),
              child: child!,
            ),
            home: const Scaffold(
              body: CustomScrollView(
                slivers: [
                  HeroHeader(
                    title: 'Comic',
                    subTitle: 'Author',
                    backgroundCover: null,
                    frontCover: null,
                    rating: 8.2,
                    tags: <String>['冒险'],
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final cover = tester.getRect(
          find.byKey(const ValueKey('detail-floating-cover')),
        );
        final surface = tester.getRect(
          find.byKey(const ValueKey('detail-hero-surface')),
        );
        final titleBand = tester.getRect(
          find.byKey(const ValueKey('detail-hero-title-band')),
        );
        final rating = tester.getRect(
          find.byKey(const ValueKey('detail-hero-rating')),
        );
        final expectedSurfaceTop = cover.top + cover.height * 2 / 3;

        expect(surface.top, closeTo(expectedSurfaceTop, 1.5));
        expect(cover.bottom, greaterThan(surface.top));
        // Right column shares cover vertical bounds; rating centers in lower 1/3.
        expect(titleBand.top, closeTo(cover.top, 1.5));
        expect(titleBand.bottom, closeTo(cover.bottom, 1.5));
        final lowerThirdTop = cover.top + cover.height * 2 / 3;
        final lowerThirdCenter = (lowerThirdTop + cover.bottom) / 2;
        expect(rating.center.dy, closeTo(lowerThirdCenter, 6));
        expect(rating.top, greaterThanOrEqualTo(lowerThirdTop - 2));
        expect(rating.bottom, lessThanOrEqualTo(cover.bottom + 2));
        expect(tester.takeException(), isNull);
      }

      await assertSeamAt(const Size(375, 812));
      await assertSeamAt(const Size(768, 1024));
      await assertSeamAt(const Size(1280, 900));
    },
  );

  testWidgets('synopsis uses full width with trailing expand overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SizedBox(
            width: 280,
            child: SynopsisBlock(
              text:
                  '第一行很长很长很长很长很长很长很长。第二行很长很长很长很长很长很长很长。第三行很长很长很长很长很长很长很长。第四行很长很长很长很长很长很长很长。第五行继续加长确保会超过三行折叠。',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('展开'), findsOneWidget);
    final bodyText = tester.widget<Text>(find.textContaining('第一行'));
    expect(bodyText.maxLines, 3);

    final textRect = tester.getRect(find.textContaining('第一行'));
    final toggleRect = tester.getRect(find.text('展开'));
    // Body spans the content width; expand sits on the trailing edge.
    expect(textRect.width, greaterThanOrEqualTo(200));
    expect(toggleRect.right, closeTo(textRect.right, 8));
    expect(toggleRect.bottom, lessThanOrEqualTo(textRect.bottom + 4));
    // Hit target is at least 44 logical px via the control.
    final toggleControl = tester.getRect(
      find.byKey(const ValueKey('synopsis-toggle')),
    );
    expect(toggleControl.height, greaterThanOrEqualTo(44));
    expect(toggleControl.width, greaterThanOrEqualTo(44));
  });

  testWidgets(
    'recent chapter header aligns 全部章节 with the section title baseline',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: RecentChapterStrip(
              chapters: const <ComicChapter>[
                ComicChapter(id: '1', title: '第1话', order: 1),
              ],
              loadThumbnail: (_) async => null,
              onSelect: (_) {},
              onShowAll: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final titleRect = tester.getRect(find.text('最近章节'));
      final actionRect = tester.getRect(find.text('全部章节'));
      // Optical vertical alignment: centers should be close (no TextButton drop).
      expect((titleRect.center.dy - actionRect.center.dy).abs(), lessThan(6));
    },
  );

  testWidgets('collapsed detail app bar shows title with back and more only', (
    tester,
  ) async {
    var more = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Stack(
            children: [
              DetailAppBar(
                title: 'Comic',
                scrolledUnder: true,
                onMore: () => more++,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Comic'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    expect(more, 1);
  });

  testWidgets('metadata keeps metrics and hides no approved fields', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DetailMetadata(
            authors: const <String>['Alice'],
            categories: const <String>['冒险'],
            labels: const <String>['成长'],
            viewCount: 12000,
            likeCount: 900,
            commentCount: 37,
            chapterCount: 18,
            jmNumber: '123',
            onAuthorTap: (_) {},
            onCategoryTap: (_) {},
            onLabelTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('阅读'), findsOneWidget);
    expect(find.textContaining('喜欢'), findsOneWidget);
    expect(find.textContaining('评论'), findsOneWidget);
    expect(find.textContaining('章节'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('冒险'), findsOneWidget);
  });

  testWidgets('metadata hides null view/like/comment metrics', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DetailMetadata(
            authors: const <String>[],
            categories: const <String>[],
            labels: const <String>[],
            viewCount: null,
            likeCount: null,
            commentCount: null,
            chapterCount: 12,
            jmNumber: null,
            onAuthorTap: (_) {},
            onCategoryTap: (_) {},
            onLabelTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('阅读'), findsNothing);
    expect(find.textContaining('喜欢'), findsNothing);
    expect(find.textContaining('评论'), findsNothing);
    expect(find.textContaining('—'), findsNothing);
    expect(find.textContaining('章节'), findsOneWidget);
    expect(find.textContaining('12'), findsOneWidget);
  });

  testWidgets('synopsis defaults to three lines and exposes expand semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SizedBox(
            width: 160,
            child: SynopsisBlock(
              text:
                  '第一行很长很长很长很长很长很长。第二行很长很长很长很长很长很长。第三行很长很长很长很长很长很长。第四行很长很长很长很长很长很长。第五行继续加长确保会超过三行折叠。',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final text = tester.widget<Text>(find.textContaining('第一行'));
    expect(text.maxLines, 3);
    expect(find.text('展开'), findsOneWidget);
  });

  testWidgets('recent chapter strip shows at most the newest six chapters', (
    tester,
  ) async {
    final chapters = List<ComicChapter>.generate(
      8,
      (index) => ComicChapter(
        id: '${index + 1}',
        title: 'Chapter ${index + 1}',
        order: index + 1,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: RecentChapterStrip(
            chapters: chapters,
            loadThumbnail: (_) async => null,
            onSelect: (_) {},
            onShowAll: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('recent-chapter-strip')), findsOneWidget);
    expect(find.text('Chapter 8'), findsOneWidget);
    expect(find.text('Chapter 2'), findsNothing);
    expect(find.text('全部章节'), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsNothing);

    // Chapter 3 is the oldest of the six-item window and may start off-screen.
    await tester.drag(
      find.byKey(const ValueKey('recent-chapter-strip')),
      const Offset(-900, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chapter 3'), findsOneWidget);
    expect(find.text('Chapter 2'), findsNothing);
  });

  testWidgets(
    'narrow recent chapter strip does not request every thumbnail immediately',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;

      final requested = <String>[];
      final chapters = List<ComicChapter>.generate(
        8,
        (index) => ComicChapter(
          id: '${index + 1}',
          title: 'Chapter ${index + 1}',
          order: index + 1,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: RecentChapterStrip(
              chapters: chapters,
              loadThumbnail: (chapter) async {
                requested.add(chapter.id);
                return null;
              },
              onSelect: (_) {},
              onShowAll: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(requested, isNotEmpty);
      expect(requested.length, lessThan(6));
      expect(requested, isNot(contains('3')));
      expect(requested.first, '8');
    },
  );

  testWidgets(
    'hero title band stays below app bar at 1.3 text scale without overflow',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3),
              padding: const EdgeInsets.only(top: 24),
            ),
            child: child!,
          ),
          home: const Scaffold(
            body: Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    HeroHeader(
                      title: '非常非常长的漫画标题用来验证大字号下不会顶到导航栏也不会撑破头图区域',
                      subTitle: '非常长的作者名以及副标题也需要被限制在安全标题带内',
                      backgroundCover: null,
                      frontCover: null,
                      rating: 8.6,
                      tags: <String>['冒险', '奇幻', '成长', '热血'],
                    ),
                  ],
                ),
                DetailAppBar(title: 'Comic', scrolledUnder: false),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);

      final titleBand = tester.getRect(
        find.byKey(const ValueKey('detail-hero-title-band')),
      );
      final appBarBottom = 24.0 + 52.0;
      expect(titleBand.top, greaterThanOrEqualTo(appBarBottom));
      expect(
        find.byKey(const ValueKey('detail-hero-backdrop')),
        findsOneWidget,
      );
      expect(find.textContaining('非常非常长的漫画标题'), findsOneWidget);
    },
  );

  testWidgets('detail actions expose one favorite and one read button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DetailActions(
            isFavorite: false,
            canRead: true,
            readLabel: '开始阅读',
            onFavorite: () {},
            onRead: () {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('detail-favorite-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('detail-read-button')), findsOneWidget);
  });

  testWidgets('comment preview renders at most two comments', (tester) async {
    final comments = <Comment>[
      const Comment('A', null, 'One', null, 0, '1'),
      const Comment('B', null, 'Two', null, 0, '2'),
      const Comment('C', null, 'Three', null, 0, '3'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CommentPreview(
            comments: comments,
            loading: false,
            canOpenAll: true,
            onOpenAll: () {},
          ),
        ),
      ),
    );
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('Three'), findsNothing);
    expect(find.text('全部评论'), findsOneWidget);
  });

  test('detail page has no tab or fixed action architecture', () {
    final source = File('lib/views/detail/detail_page.dart').readAsStringSync();
    expect(source, isNot(contains('DetailTabBar')));
    expect(source, isNot(contains('StickyActionBar')));
    expect(source, isNot(contains('Positioned(\n          left: 0')));
    expect(source, contains('DetailActions('));
    expect(source, contains('CommentPreview('));
  });

  testWidgets('detail loading skeleton reserves hero and cover geometry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: DetailLoadingSkeleton()),
      ),
    );
    expect(find.byKey(const ValueKey('detail-skeleton-hero')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-skeleton-cover')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('detail-skeleton-chapters')),
      findsOneWidget,
    );
  });

  testWidgets('recommendations render nothing when empty', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: RecommendationCarousel(items: [])),
      ),
    );
    expect(find.text('相关推荐'), findsNothing);
    expect(find.text('暂无推荐'), findsNothing);
  });

  testWidgets(
    'recommendation poster titles allow two lines with a stable card height',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: RecommendationCarousel(
              items: [
                RecommendItem(
                  id: '1',
                  title: '这是一个非常非常长的推荐标题用来验证两行省略不会把卡片撑高',
                  cover: null,
                  author: 'Author',
                ),
                RecommendItem(id: '2', title: '短标题', cover: null),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final longTitle = tester.widget<Text>(
        find.textContaining('这是一个非常非常长的推荐标题'),
      );
      expect(longTitle.maxLines, 2);

      final carousel = tester.getRect(find.byType(RecommendationCarousel));
      // List height is fixed so mixed one/two-line titles stay stable.
      final listSizedBox = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where(
            (box) =>
                box.height == 250 || box.height == 230 || box.height == 210,
          );
      expect(listSizedBox, isNotEmpty);
      expect(carousel.height, greaterThan(180));
    },
  );

  test('detail page appends system bottom inset to the design end spacing', () {
    final source = File('lib/views/detail/detail_page.dart').readAsStringSync();
    expect(source, contains("ValueKey('detail-bottom-safe-padding')"));
    expect(source, contains('bottomContentInset(context)'));
    expect(source, isNot(contains('StickyActionBar')));
  });

  testWidgets('approved composition renders without overflow at breakpoints', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                const HeroHeader(
                  title: 'Comic Title That Can Wrap Across Lines',
                  subTitle: 'Author Name',
                  backgroundCover: null,
                  frontCover: null,
                  rating: 8.2,
                  tags: <String>['冒险', '奇幻', '成长'],
                ),
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      DetailMetadata(
                        authors: const <String>['Alice'],
                        categories: const <String>['冒险'],
                        labels: const <String>['成长'],
                        viewCount: 1200,
                        likeCount: 90,
                        commentCount: 12,
                        chapterCount: 8,
                        jmNumber: null,
                        onAuthorTap: (_) {},
                        onCategoryTap: (_) {},
                        onLabelTap: (_) {},
                      ),
                      const SynopsisBlock(text: '简介内容用于响应式布局检查。'),
                      RecentChapterStrip(
                        chapters: List<ComicChapter>.generate(
                          6,
                          (index) => ComicChapter(
                            id: '${index + 1}',
                            title: 'Chapter ${index + 1}',
                            order: index + 1,
                          ),
                        ),
                        loadThumbnail: (_) async => null,
                        onSelect: (_) {},
                        onShowAll: () {},
                      ),
                      DetailActions(
                        isFavorite: false,
                        canRead: true,
                        readLabel: '开始阅读',
                        onFavorite: () {},
                        onRead: () {},
                      ),
                      CommentPreview(
                        comments: const <Comment>[
                          Comment('A', null, 'Preview', null, 0, '1'),
                        ],
                        loading: false,
                        canOpenAll: true,
                        onOpenAll: () {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    await pumpAt(const Size(375, 812));
    await pumpAt(const Size(768, 1024));
    await pumpAt(const Size(1280, 900));
  });
}
