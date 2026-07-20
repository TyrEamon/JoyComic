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
import 'package:joycomic/views/detail/widgets/hero_header.dart';
import 'package:joycomic/views/detail/widgets/recent_chapter_strip.dart';
import 'package:joycomic/views/detail/widgets/recommendation_carousel.dart';
import 'package:joycomic/views/detail/widgets/synopsis_block.dart';

void main() {
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
    expect(find.text('8.8'), findsOneWidget);
    expect(find.byType(RatingStars), findsOneWidget);
  });

  testWidgets('collapsed detail app bar shows the title and share action', (
    tester,
  ) async {
    var shares = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Stack(
            children: [
              DetailAppBar(
                title: 'Comic',
                scrolledUnder: true,
                onShare: () => shares++,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Comic'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.ios_share_rounded));
    expect(shares, 1);
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
