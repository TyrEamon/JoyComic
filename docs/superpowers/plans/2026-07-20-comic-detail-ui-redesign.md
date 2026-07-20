# Comic Detail UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild JoyComic's comic detail experience around an immersive cover hero with a cross-surface floating cover, a six-item recent chapter strip, one inline favorite/read action row, comment previews, recommendations, and separate full chapter/comment pages.

**Architecture:** Keep `DetailViewModel` and all `ComicSource` contracts intact. Recompose the current detail screen into focused widgets, add nested GoRouter routes for full chapters and comments, and extract the existing chapter download behavior into the full chapters page. Use `LayoutBuilder`, theme tokens, and existing typed models so mobile, tablet, desktop, light theme, and dark theme share one information architecture.

**Tech Stack:** Flutter, Material 3, Provider, GoRouter, cached_network_image_ce, existing JoyComic theme helpers, flutter_test.

---

## Scope and file map

### Create

- `lib/views/detail/detail_chapters_page.dart` — complete chapter browser and the only mobile download surface.
- `lib/views/detail/detail_comments_page.dart` — complete comments, pagination, reply, and composer surface.
- `lib/views/detail/widgets/recent_chapter_strip.dart` — at most six recent chapters for the detail page.
- `lib/views/detail/widgets/detail_actions.dart` — the single inline favorite/read action row.
- `lib/views/detail/widgets/comment_preview.dart` — at most two comments and the all-comments entry.
- `lib/views/detail/widgets/chapter_download_sheet.dart` — extracted download queue/status sheet used by the all-chapters page.
- `lib/views/detail/widgets/detail_loading_skeleton.dart` — stable loading geometry matching the final hero/content layout.
- `test/detail_redesign_test.dart` — approved hierarchy, excluded copy, responsive layout, and unique-action tests.
- `test/detail_subpages_test.dart` — full chapter/comment page and download-location tests.

### Modify

- `lib/main.dart` — nested chapter/comment routes.
- `lib/views/detail/detail_navigation.dart` — typed route builders and navigation helpers.
- `lib/views/detail/detail_page.dart` — remove tab/sticky architecture and compose the approved flow.
- `lib/views/detail/detail_view_model.dart` — expose comment capability/preview state without changing source contracts.
- `lib/views/detail/widgets/detail_app_bar.dart` — collapsed title, share, and more actions.
- `lib/views/detail/widgets/hero_header.dart` — immersive background, content surface seam, floating cover, title, tags, score, and stars.
- `lib/views/detail/widgets/detail_metadata.dart` — metrics, author/category/label groups, and JM copy entry without rating-count or popularity copy.
- `lib/views/detail/widgets/synopsis_block.dart` — three-line default and stable expand/collapse semantics.
- `lib/views/detail/widgets/chapter_grid.dart` — full-page chapter grid/list behavior; downloads remain here only for the chapter page.
- `lib/views/detail/widgets/comment_section.dart` — export a reusable comment tile for preview/full-page consistency.
- `lib/views/detail/widgets/recommendation_carousel.dart` — hide when empty and retain horizontal refresh behavior.
- `test/detail_tabs_test.dart` — remove obsolete tab/sticky assertions and retain app-bar/composer/thumbnail coverage.
- `test/detail_actions_test.dart` — update comment preview loading and recommendation batching expectations.
- `test/detail_theme_test.dart` — assert score/stars remain and forbidden popularity/rating-count copy is absent.
- `test/routes_test.dart` — cover the two new nested routes.

### Delete after replacement tests pass

- `lib/views/detail/widgets/detail_tab_bar.dart`
- `lib/views/detail/widgets/sticky_action_bar.dart`
- `lib/views/detail/widgets/info_overlay.dart`

### Prohibited scope

- Do not change `ComicSource` network contracts or source adapters.
- Do not touch reader image pipeline files, home/search/ranking UI, `tools/**`, `clone/**`, or unrelated untracked files.
- Do not add rating-count, popularity, ranking, No.1, or fabricated metrics.
- Do not push. Local task commits are allowed; Codex performs final review and decides whether to push.

---

### Task 1: Lock navigation and exclusion rules with failing tests

**Files:**
- Modify: `lib/views/detail/detail_navigation.dart`
- Modify: `lib/main.dart`
- Modify: `test/routes_test.dart`
- Modify: `test/detail_theme_test.dart`

- [ ] **Step 1: Add failing route-builder tests**

Append to `test/routes_test.dart`:

```dart
test('detail subpage routes encode source and comic ids', () {
  expect(
    detailChaptersRoute(sourceKey: 'pica source', comicId: 'comic/id'),
    '/detail/pica%20source/comic%2Fid/chapters',
  );
  expect(
    detailCommentsRoute(sourceKey: 'pica source', comicId: 'comic/id'),
    '/detail/pica%20source/comic%2Fid/comments',
  );
});
```

Add this import:

```dart
import 'package:joycomic/views/detail/detail_navigation.dart';
```

- [ ] **Step 2: Run the route test and verify it fails**

Run:

```powershell
flutter test --no-pub test/routes_test.dart
```

Expected: FAIL because `detailChaptersRoute` and `detailCommentsRoute` do not exist.

- [ ] **Step 3: Add typed nested-route helpers**

Add to `lib/views/detail/detail_navigation.dart`:

```dart
String detailChaptersRoute({
  required String sourceKey,
  required String comicId,
}) =>
    '/detail/${Uri.encodeComponent(sourceKey)}/${Uri.encodeComponent(comicId)}/chapters';

String detailCommentsRoute({
  required String sourceKey,
  required String comicId,
}) =>
    '/detail/${Uri.encodeComponent(sourceKey)}/${Uri.encodeComponent(comicId)}/comments';

void openDetailChapters(
  BuildContext context, {
  required String sourceKey,
  required String comicId,
}) {
  context.push(detailChaptersRoute(sourceKey: sourceKey, comicId: comicId));
}

void openDetailComments(
  BuildContext context, {
  required String sourceKey,
  required String comicId,
}) {
  context.push(detailCommentsRoute(sourceKey: sourceKey, comicId: comicId));
}
```

- [ ] **Step 4: Register nested routes with temporary page imports**

Create minimal page shells so routing compiles; these shells are replaced in Tasks 6 and 7.

Create `lib/views/detail/detail_chapters_page.dart`:

```dart
import 'package:flutter/material.dart';

class DetailChaptersPage extends StatelessWidget {
  const DetailChaptersPage({
    super.key,
    required this.sourceKey,
    required this.comicId,
  });

  final String sourceKey;
  final String comicId;

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('全部章节')));
}
```

Create `lib/views/detail/detail_comments_page.dart`:

```dart
import 'package:flutter/material.dart';

class DetailCommentsPage extends StatelessWidget {
  const DetailCommentsPage({
    super.key,
    required this.sourceKey,
    required this.comicId,
  });

  final String sourceKey;
  final String comicId;

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('全部评论')));
}
```

Import both pages in `lib/main.dart`, then replace the existing detail route with:

```dart
GoRoute(
  path: '/detail/:sourceKey/:comicId',
  builder: (context, state) => DetailPage(
    sourceKey: state.pathParameters['sourceKey']!,
    comicId: state.pathParameters['comicId']!,
  ),
  routes: [
    GoRoute(
      path: 'chapters',
      builder: (context, state) => DetailChaptersPage(
        sourceKey: state.pathParameters['sourceKey']!,
        comicId: state.pathParameters['comicId']!,
      ),
    ),
    GoRoute(
      path: 'comments',
      builder: (context, state) => DetailCommentsPage(
        sourceKey: state.pathParameters['sourceKey']!,
        comicId: state.pathParameters['comicId']!,
      ),
    ),
  ],
),
```

- [ ] **Step 5: Strengthen forbidden-copy tests**

Extend `test/detail_theme_test.dart`:

```dart
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
```

- [ ] **Step 6: Run tests and commit**

Run:

```powershell
flutter test --no-pub test/routes_test.dart test/detail_theme_test.dart
```

Expected: PASS.

Commit:

```powershell
git add lib/main.dart lib/views/detail/detail_navigation.dart lib/views/detail/detail_chapters_page.dart lib/views/detail/detail_comments_page.dart test/routes_test.dart test/detail_theme_test.dart
git commit -m "test: define detail subpage routes and copy rules"
```

---

### Task 2: Rebuild the hero seam, floating cover, and collapsing app bar

**Files:**
- Modify: `lib/views/detail/widgets/hero_header.dart`
- Modify: `lib/views/detail/widgets/detail_app_bar.dart`
- Delete: `lib/views/detail/widgets/info_overlay.dart`
- Create: `test/detail_redesign_test.dart`

- [ ] **Step 1: Write failing hero hierarchy tests**

Create `test/detail_redesign_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/views/detail/widgets/detail_app_bar.dart';
import 'package:joycomic/views/detail/widgets/hero_header.dart';

void main() {
  testWidgets('hero floats the cover across backdrop and content surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              HeroHeader(
                title: 'Comic',
                subTitle: 'Author',
                backgroundCover: null,
                frontCover: null,
                rating: 8.8,
                tags: const <String>['冒险', '奇幻'],
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
}
```

Add the missing import:

```dart
import 'package:joycomic/views/common/widgets/rating_stars.dart';
```

- [ ] **Step 2: Run the test and verify it fails**

Run:

```powershell
flutter test --no-pub test/detail_redesign_test.dart
```

Expected: FAIL because the hero has no `tags` argument or seam keys and the app bar has no title/share button.

- [ ] **Step 3: Implement the adaptive hero stack**

Replace `HeroHeader`'s public interface with:

```dart
class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.title,
    required this.subTitle,
    required this.backgroundCover,
    required this.frontCover,
    required this.rating,
    required this.tags,
    this.coverHeaders,
  });

  final String title;
  final String? subTitle;
  final String? backgroundCover;
  final String? frontCover;
  final double? rating;
  final List<String> tags;
  final Map<String, dynamic>? coverHeaders;
}
```

Return a `SliverLayoutBuilder` containing a `SliverToBoxAdapter`, then use `LayoutBuilder` inside the box. The implementation must compute mobile/tablet/desktop cover widths without fixed device assumptions:

```dart
final width = constraints.maxWidth;
final coverWidth = width >= 900
    ? 188.0
    : width >= 600
    ? 164.0
    : (width * 0.34).clamp(116.0, 144.0);
final backdropHeight = width >= 600 ? 340.0 : 300.0;
final seamTop = backdropHeight - 34;
final totalHeight = backdropHeight + (width >= 600 ? 190.0 : 170.0);
```

Build a single `Stack` with these keyed layers:

```dart
Stack(
  clipBehavior: Clip.none,
  children: [
    Positioned(
      key: const ValueKey('detail-hero-backdrop'),
      left: 0,
      right: 0,
      top: 0,
      height: backdropHeight,
      child: _HeroBackdrop(
        imageUrl: backgroundCover ?? frontCover,
        headers: coverHeaders,
      ),
    ),
    Positioned(
      key: const ValueKey('detail-hero-surface'),
      left: 0,
      right: 0,
      top: seamTop,
      bottom: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.pageBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    ),
    Positioned(
      key: const ValueKey('detail-floating-cover'),
      left: AppSpacing.md,
      top: seamTop - coverWidth * 0.56,
      width: coverWidth,
      child: ComicCover(
        url: frontCover,
        width: coverWidth,
        headers: coverHeaders,
      ),
    ),
    Positioned(
      left: AppSpacing.md + coverWidth + AppSpacing.md,
      right: AppSpacing.md,
      bottom: totalHeight - seamTop + AppSpacing.lg,
      child: _HeroTitle(
        title: title,
        subTitle: subTitle,
        tags: tags,
      ),
    ),
    if (rating != null)
      Positioned(
        left: AppSpacing.md + coverWidth + AppSpacing.md,
        right: AppSpacing.md,
        top: seamTop + AppSpacing.lg,
        child: _HeroRating(rating: rating!),
      ),
  ],
)
```

Implement `_HeroBackdrop` as the existing `CachedNetworkImage` plus current top/bottom `AppGradients` scrims, `_HeroTitle` as title/subtitle plus `tags.take(4)` using on-image colors, and `_HeroRating` as:

```dart
class _HeroRating extends StatelessWidget {
  const _HeroRating({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          rating.toStringAsFixed(1),
          style: AppTypography.ratingNumber(context),
        ),
        const SizedBox(width: AppSpacing.xs),
        RatingStars(rating: rating / 2, size: 16),
      ],
    );
  }
}
```

Use `context.onImageColor` for backdrop text, `context.pageBackground` for the lower surface, existing `AppGradients` scrims, and existing theme shadows/radii. If `rating == null`, do not build either the number or `RatingStars`.

Pass `constraints.scrollOffset` from `SliverLayoutBuilder` to `_HeroBackdrop`. Apply only a restrained background-image translation:

```dart
final disableMotion = MediaQuery.disableAnimationsOf(context);
final parallaxY = disableMotion ? 0.0 : scrollOffset * 0.12;
Transform.translate(
  offset: Offset(0, parallaxY),
  child: CachedNetworkImage(
    imageUrl: imageUrl ?? '',
    httpHeaders: headers?.cast<String, String>(),
    fit: BoxFit.cover,
    placeholder: (_, __) => ColoredBox(
      color: context.elevatedSurfaceColor,
      child: const SizedBox.expand(),
    ),
    errorBuilder: (_, __, ___) => ColoredBox(
      color: context.elevatedSurfaceColor,
      child: const Center(child: Icon(Icons.menu_book_rounded)),
    ),
  ),
)
```

Do not translate the content surface or floating cover; the seam must remain stable.

- [ ] **Step 4: Implement the collapsing app bar**

Update `DetailAppBar` to accept `String? title`. Its bar must render:

```dart
Row(
  children: [
    _IconBtn(
      icon: Icons.arrow_back_ios_new_rounded,
      tooltip: '返回',
      onTap: onBack,
    ),
    if (scrolledUnder)
      Expanded(
        child: Text(
          title ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      )
    else
      const Spacer(),
    _IconBtn(
      icon: Icons.ios_share_rounded,
      tooltip: '分享',
      onTap: onShare,
    ),
    _IconBtn(
      icon: Icons.more_horiz_rounded,
      tooltip: '更多',
      onTap: onMore,
    ),
  ],
)
```

Use the existing 200ms `AnimatedContainer`; when collapsed, use `context.pageBackground`, a bottom border, and theme foreground colors. When expanded, use the image scrim and `context.onImageColor`.

- [ ] **Step 5: Delete the obsolete overlay and run tests**

Delete `lib/views/detail/widgets/info_overlay.dart` after removing its import from `hero_header.dart`.

Run:

```powershell
dart format lib/views/detail/widgets/hero_header.dart lib/views/detail/widgets/detail_app_bar.dart test/detail_redesign_test.dart
flutter test --no-pub test/detail_redesign_test.dart test/detail_theme_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```powershell
git add lib/views/detail/widgets/hero_header.dart lib/views/detail/widgets/detail_app_bar.dart lib/views/detail/widgets/info_overlay.dart test/detail_redesign_test.dart test/detail_theme_test.dart
git commit -m "feat: rebuild immersive detail hero"
```

---

### Task 3: Simplify metadata and synopsis while preserving score and metrics

**Files:**
- Modify: `lib/views/detail/widgets/detail_metadata.dart`
- Modify: `lib/views/detail/widgets/synopsis_block.dart`
- Modify: `test/detail_redesign_test.dart`
- Modify: `test/detail_theme_test.dart`

- [ ] **Step 1: Add failing metadata/synopsis tests**

Add to `test/detail_redesign_test.dart`:

```dart
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

testWidgets('synopsis defaults to three lines and exposes expand semantics', (
  tester,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: SizedBox(
          width: 220,
          child: SynopsisBlock(
            text: '第一行很长很长。第二行很长很长。第三行很长很长。第四行很长很长。',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final text = tester.widget<Text>(find.textContaining('第一行'));
  expect(text.maxLines, 3);
  expect(find.text('展开'), findsOneWidget);
});
```

- [ ] **Step 2: Verify the tests fail**

Run:

```powershell
flutter test --no-pub test/detail_redesign_test.dart
```

Expected: FAIL because `DetailMetadata` still requires `rating` and `SynopsisBlock` defaults to four lines.

- [ ] **Step 3: Remove rating from metadata and flatten its surface**

Remove `rating` from the `DetailMetadata` constructor and fields. Keep the four metrics, JM copy chip, authors, categories, and labels. Replace the boxed `_MetricsPanel` with a responsive plain layout:

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final columns = constraints.maxWidth >= 720 ? 4 : 2;
    final width =
        (constraints.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _Metric(width: width, icon: Icons.visibility_outlined, label: '阅读', value: _formatCount(viewCount)),
        _Metric(width: width, icon: Icons.favorite_border_rounded, label: '喜欢', value: _formatCount(likeCount)),
        _Metric(width: width, icon: Icons.chat_bubble_outline_rounded, label: '评论', value: _formatCount(commentCount)),
        _Metric(width: width, icon: Icons.menu_book_outlined, label: '章节', value: chapterCount.toString()),
      ],
    );
  },
)
```

Do not add score, stars, rating count, heat, or popularity here; score/stars belong only in `HeroHeader`.

- [ ] **Step 4: Set synopsis to three lines and add semantics**

Change the default to:

```dart
this.maxLinesWhenCollapsed = 3,
```

Wrap `_ToggleLink` with:

```dart
Semantics(
  button: true,
  label: expanded ? '收起简介' : '展开简介',
  child: Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          expanded ? '收起' : '展开',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: accent,
          ),
        ),
      ),
    ),
  ),
)
```

Keep the existing 220ms `AnimatedSize` and `暂无简介` state.

- [ ] **Step 5: Run tests and commit**

```powershell
dart format lib/views/detail/widgets/detail_metadata.dart lib/views/detail/widgets/synopsis_block.dart test/detail_redesign_test.dart
flutter test --no-pub test/detail_redesign_test.dart test/detail_theme_test.dart
git add lib/views/detail/widgets/detail_metadata.dart lib/views/detail/widgets/synopsis_block.dart test/detail_redesign_test.dart test/detail_theme_test.dart
git commit -m "feat: refine detail metadata and synopsis"
```

Expected: both test files PASS.

---

### Task 4: Add the recent chapter strip and single inline action row

**Files:**
- Create: `lib/views/detail/widgets/recent_chapter_strip.dart`
- Create: `lib/views/detail/widgets/detail_actions.dart`
- Modify: `test/detail_redesign_test.dart`
- Modify: `test/detail_tabs_test.dart`

- [ ] **Step 1: Add failing recent-chapter and action tests**

Add to `test/detail_redesign_test.dart`:

```dart
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
  expect(find.text('Chapter 3'), findsOneWidget);
  expect(find.text('Chapter 2'), findsNothing);
  expect(find.text('全部章节'), findsOneWidget);
  expect(find.byIcon(Icons.download_rounded), findsNothing);
});

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
  expect(find.byKey(const ValueKey('detail-favorite-button')), findsOneWidget);
  expect(find.byKey(const ValueKey('detail-read-button')), findsOneWidget);
});
```

- [ ] **Step 2: Verify tests fail**

Run:

```powershell
flutter test --no-pub test/detail_redesign_test.dart
```

Expected: FAIL because both widgets are missing.

- [ ] **Step 3: Implement `RecentChapterStrip`**

The widget interface must be:

```dart
class RecentChapterStrip extends StatelessWidget {
  const RecentChapterStrip({
    super.key,
    required this.chapters,
    required this.loadThumbnail,
    required this.onSelect,
    required this.onShowAll,
    this.coverHeaders,
  });

  final List<ComicChapter> chapters;
  final Future<String?> Function(ComicChapter chapter) loadThumbnail;
  final ValueChanged<ComicChapter> onSelect;
  final VoidCallback onShowAll;
  final Map<String, dynamic>? coverHeaders;
}
```

Select chapters with:

```dart
final recent = chapters.reversed.take(6).toList(growable: false);
```

Render a section heading, latest label, `全部章节`, and a horizontal `ListView.separated` keyed `recent-chapter-strip`. Each item uses `ChapterThumbnail`, a stable 16:11 image area, title, 44px minimum tap target, and no download icon. Empty chapters render `暂无可阅读章节`.

- [ ] **Step 4: Implement `DetailActions`**

Use this interface:

```dart
class DetailActions extends StatelessWidget {
  const DetailActions({
    super.key,
    required this.isFavorite,
    required this.canRead,
    required this.readLabel,
    required this.onFavorite,
    required this.onRead,
  });

  final bool isFavorite;
  final bool canRead;
  final String readLabel;
  final VoidCallback onFavorite;
  final VoidCallback onRead;
}
```

Render one `OutlinedButton.icon` keyed `detail-favorite-button` and one `FilledButton.icon` keyed `detail-read-button`. The favorite icon/text changes together. Disable only the read button when `canRead == false`. Do not use `SafeArea`, `Positioned`, fixed-bottom layout, or download actions.

- [ ] **Step 5: Remove obsolete tab/sticky widget tests**

In `test/detail_tabs_test.dart`, delete:

- `chapter tab is selected by default and comments show the true total`
- `favorite and read actions are both exactly 52px high`

Remove imports for `detail_tab_bar.dart` and `sticky_action_bar.dart`. Retain composer, thumbnail, and app-bar tests; update the app-bar test to pass `title: 'Comic'` and expect both share/more callbacks.

- [ ] **Step 6: Run tests and commit**

```powershell
dart format lib/views/detail/widgets/recent_chapter_strip.dart lib/views/detail/widgets/detail_actions.dart test/detail_redesign_test.dart test/detail_tabs_test.dart
flutter test --no-pub test/detail_redesign_test.dart test/detail_tabs_test.dart
git add lib/views/detail/widgets/recent_chapter_strip.dart lib/views/detail/widgets/detail_actions.dart test/detail_redesign_test.dart test/detail_tabs_test.dart
git commit -m "feat: add recent chapters and inline detail actions"
```

Expected: PASS.

---

### Task 5: Recompose the main detail page and load comment previews

**Files:**
- Modify: `lib/views/detail/detail_page.dart`
- Modify: `lib/views/detail/detail_view_model.dart`
- Create: `lib/views/detail/widgets/comment_preview.dart`
- Modify: `lib/views/detail/widgets/comment_section.dart`
- Delete: `lib/views/detail/widgets/detail_tab_bar.dart`
- Delete: `lib/views/detail/widgets/sticky_action_bar.dart`
- Modify: `test/detail_actions_test.dart`
- Modify: `test/detail_redesign_test.dart`

- [ ] **Step 1: Add failing comment-preview tests**

Add to `test/detail_redesign_test.dart`:

```dart
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
```

Add a source assertion test:

```dart
test('detail page has no tab or fixed action architecture', () {
  final source = File('lib/views/detail/detail_page.dart').readAsStringSync();
  expect(source, isNot(contains('DetailTabBar')));
  expect(source, isNot(contains('StickyActionBar')));
  expect(source, isNot(contains('Positioned(\n          left: 0')));
  expect(source, contains('DetailActions('));
  expect(source, contains('CommentPreview('));
});
```

- [ ] **Step 2: Verify failure**

```powershell
flutter test --no-pub test/detail_redesign_test.dart
```

Expected: FAIL because `CommentPreview` is missing and the detail page still uses tabs/sticky actions.

- [ ] **Step 3: Export a reusable comment tile**

Rename `_CommentCard` in `comment_section.dart` to public `CommentTile`:

```dart
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    this.onReply,
    this.compact = false,
  });

  final Comment comment;
  final VoidCallback? onReply;
  final bool compact;
}
```

When `compact == true`, limit the main content to two lines and omit reply previews; only show the reply button when `onReply != null`. Update `CommentSection` to use `CommentTile(comment: comment, onReply: ...)`.

- [ ] **Step 4: Implement `CommentPreview`**

Use:

```dart
class CommentPreview extends StatelessWidget {
  const CommentPreview({
    super.key,
    required this.comments,
    required this.loading,
    required this.canOpenAll,
    required this.onOpenAll,
  });

  final List<Comment> comments;
  final bool loading;
  final bool canOpenAll;
  final VoidCallback onOpenAll;
}
```

Rules:

```dart
final preview = comments.take(2).toList(growable: false);
```

- Loading and empty comments: show a compact progress/empty state.
- Build `全部评论` only when `canOpenAll && comments.isNotEmpty`.
- Render `CommentTile(comment: comment, compact: true)` for each preview comment.

- [ ] **Step 5: Expose comment capability clearly**

Add to `DetailViewModel`:

```dart
bool get canLoadComments => ComicSource.find(sourceKey)?.commentsLoader != null;
```

If this getter already exists under another exact name, reuse it and do not duplicate it. Keep `activateComments()` idempotent.

Also inject and expose reading progress using the existing database helper:

```dart
DetailViewModel({
  required this.sourceKey,
  required this.comicId,
  FavoritesHelper? favoritesHelper,
  ReadRecordHelper? readRecordHelper,
}) : _favHelper = favoritesHelper ?? FavoritesHelper(),
     _readRecordHelper = readRecordHelper ?? ReadRecordHelper() {
  ReadRecordNotifier.instance.addListener(_handleReadRecordChanged);
}

final ReadRecordHelper _readRecordHelper;

ReadRecord? get readRecord => _readRecordHelper.get(sourceKey, comicId);
bool get hasReadProgress => readRecord != null;
String get readActionLabel => hasReadProgress ? '继续阅读' : '开始阅读';

void _handleReadRecordChanged() => _notifyListeners();
```

In `dispose()`, remove the listener before disposing the thumbnail pool:

```dart
ReadRecordNotifier.instance.removeListener(_handleReadRecordChanged);
```

Add tests to `test/detail_view_model_test.dart` using an in-memory `ReadRecordHelper` to verify the label changes from `开始阅读` to `继续阅读` after inserting a record.

Update `test/detail_actions_test.dart` so the lazy-load test still asserts `load()` alone does not fetch comments, then explicitly verifies `activateComments()` fetches page one. The detail page, not `DetailViewModel.load()`, owns preview activation.

- [ ] **Step 6: Recompose `DetailPage`**

Convert `_DetailScaffold` to `StatefulWidget` with `_scrolledUnder`. Wrap the body in `NotificationListener<ScrollNotification>` and update the state only when crossing the collapse threshold:

```dart
final next = notification.metrics.pixels > 260;
if (next != _scrolledUnder) setState(() => _scrolledUnder = next);
return false;
```

Pass `title`, `scrolledUnder`, share, and more to `DetailAppBar`.

In `_ContentState.didChangeDependencies`, activate preview comments once:

```dart
if (!_requestedCommentPreview) {
  _requestedCommentPreview = true;
  unawaited(context.read<DetailViewModel>().activateComments());
}
```

Replace the current stack/tabs/sticky layout with one `CustomScrollView` keyed for restoration:

```dart
CustomScrollView(
  key: PageStorageKey<String>('detail-${vm.sourceKey}-${info.comicId}'),
  slivers: <Widget>[
    // approved content order below
  ],
)
```

Its content order must be exactly:

```dart
HeroHeader(...),
DetailMetadata(...),
SynopsisBlock(text: info.description),
RecentChapterStrip(
  chapters: vm.chapters,
  loadThumbnail: vm.loadChapterThumbnail,
  onSelect: (chapter) => _openReader(context, vm, chapter, readerChapters),
  onShowAll: () => openDetailChapters(
    context,
    sourceKey: vm.sourceKey,
    comicId: info.comicId,
  ),
),
DetailActions(
  isFavorite: vm.isFavorite,
  canRead: vm.chapters.isNotEmpty,
  readLabel: vm.readActionLabel,
  onFavorite: vm.toggleFavorite,
  onRead: () => _openReader(context, vm, null, readerChapters),
),
CommentPreview(
  comments: vm.comments,
  loading: vm.commentsLoading,
  canOpenAll: vm.canLoadComments,
  onOpenAll: () => openDetailComments(
    context,
    sourceKey: vm.sourceKey,
    comicId: info.comicId,
  ),
),
if (visibleRecommends.isNotEmpty)
  RecommendationCarousel(...),
```

Pass `tags: <String>[...info.categories, ...info.labels].take(4).toList()` to `HeroHeader`. Remove all download methods from `detail_page.dart`; Task 6 relocates them. Remove imports for download manager/task, comment composer/section, detail tab bar, chapter grid, and sticky action bar.

Use page padding at the end, not bottom safe-area compensation for a fixed bar.

- [ ] **Step 7: Delete obsolete widgets and run tests**

Delete:

- `lib/views/detail/widgets/detail_tab_bar.dart`
- `lib/views/detail/widgets/sticky_action_bar.dart`

Run:

```powershell
dart format lib/views/detail/detail_page.dart lib/views/detail/detail_view_model.dart lib/views/detail/widgets/comment_preview.dart lib/views/detail/widgets/comment_section.dart test/detail_actions_test.dart test/detail_redesign_test.dart
flutter test --no-pub test/detail_redesign_test.dart test/detail_actions_test.dart test/detail_tabs_test.dart test/detail_view_model_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```powershell
git add lib/views/detail/detail_page.dart lib/views/detail/detail_view_model.dart lib/views/detail/widgets/comment_preview.dart lib/views/detail/widgets/comment_section.dart lib/views/detail/widgets/detail_tab_bar.dart lib/views/detail/widgets/sticky_action_bar.dart test/detail_actions_test.dart test/detail_redesign_test.dart test/detail_tabs_test.dart test/detail_view_model_test.dart
git commit -m "feat: compose the new detail content flow"
```

---

### Task 6: Build the full chapters page and move all download actions there

**Files:**
- Modify: `lib/views/detail/detail_chapters_page.dart`
- Create: `lib/views/detail/widgets/chapter_download_sheet.dart`
- Modify: `lib/views/detail/widgets/chapter_grid.dart`
- Create: `test/detail_subpages_test.dart`

- [ ] **Step 1: Add failing chapter-page tests**

Create `test/detail_subpages_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile download actions live on the full chapters page only', () {
    final detail = File('lib/views/detail/detail_page.dart').readAsStringSync();
    final chapters = File(
      'lib/views/detail/detail_chapters_page.dart',
    ).readAsStringSync();
    expect(detail, isNot(contains('download_rounded')));
    expect(detail, isNot(contains('DownloadManager')));
    expect(chapters, contains('ChapterGrid('));
    expect(chapters, contains('showChapterDownloadSheet('));
  });
}
```

Add widget coverage after the functional page is available:

```dart
testWidgets('full chapters page exposes download and empty states', (
  tester,
) async {
  final source = ComicSource.named(
    name: 'Chapter page test',
    key: 'chapter-page-test',
    filePath: 'test',
    loadComicInfo: (_) async => Res<ComicInfoData>(
      const ComicInfoData(
        title: 'Comic',
        subTitle: 'Author',
        cover: '',
        description: 'Synopsis',
        tags: <String, List<String>>{},
        chapters: null,
        chapterList: <ComicChapter>[
          ComicChapter(id: '1', title: 'Chapter 1', order: 1),
          ComicChapter(id: '2', title: 'Chapter 2', order: 2),
        ],
        thumbnails: null,
        sourceKey: 'chapter-page-test',
        comicId: 'comic',
      ),
    ),
    loadComicPages: (_, __) async => const Res<List<String>>(<String>[]),
  );
  ComicSource.sources.add(source);
  addTearDown(() => ComicSource.sources.remove(source));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const DetailChaptersPage(
        sourceKey: 'chapter-page-test',
        comicId: 'comic',
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('全部章节'), findsOneWidget);
  expect(find.byIcon(Icons.download_rounded), findsWidgets);
});
```

Use the existing `ComicSource.named`, in-memory SQLite, and source cleanup patterns from `detail_view_model_test.dart`; provide two chapters and a successful `loadComicPages` callback.

- [ ] **Step 2: Run and verify failure**

```powershell
flutter test --no-pub test/detail_subpages_test.dart
```

Expected: FAIL because the temporary route shell does not build `ChapterGrid` or the download sheet.

- [ ] **Step 3: Extract the chapter download sheet**

Create `chapter_download_sheet.dart` with this public function:

```dart
Future<void> showChapterDownloadSheet(
  BuildContext context, {
  required DetailViewModel viewModel,
  required List<ComicChapter> chapters,
}) async {
  // Move the existing detail_page.dart download sheet, task status,
  // enqueue, pause, resume, retry, and offline-reader behavior here unchanged.
}
```

Also expose the single-chapter enqueue operation used by `ChapterGrid`:

```dart
Future<void> enqueueDetailChapter(
  BuildContext context, {
  required DetailViewModel viewModel,
  required ComicChapter chapter,
}) async {
  final source = ComicSource.find(viewModel.sourceKey);
  if (source?.loadComicPages == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('当前漫画源不可用或不支持章节下载')),
    );
    return;
  }
  try {
    await DownloadManager.instance.enqueue(
      sourceKey: viewModel.sourceKey,
      comicId: viewModel.data!.info.comicId,
      chapterId: chapter.id,
      title: viewModel.data!.info.title,
      coverUrl: viewModel.data!.info.cover,
      chapterTitle: chapter.title,
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('加入下载失败：$error')),
    );
  }
}
```

Move the existing `_showDownloadSheet`, `_downloadAction`, `_enqueueChapter`, and `_downloadStatusLabel` logic from `detail_page.dart` into focused private helpers in this file. Preserve:

- `DownloadManager.instance.findTask`
- pending/downloading/paused/completed/failed labels
- pause/resume/retry actions
- `ComicState.fromDownload` offline opening
- SnackBar error isolation

- [ ] **Step 4: Make `ChapterGrid` a full-page chapter component**

Keep its existing full list/grid responsibility and lazy thumbnails. The page app bar owns the `全部章节` title, so change the internal section heading to `章节列表`. Keep per-chapter download buttons and the `onDownloadAll` entry. Use `LayoutBuilder` so:

- narrow widths use one or two columns without overflow;
- widths above 720 use up to three/four columns through `SliverGridDelegateWithMaxCrossAxisExtent`;
- every chapter card remains at least 44px tappable.

- [ ] **Step 5: Implement `DetailChaptersPage`**

Use a page-owned `DetailViewModel`:

```dart
class DetailChaptersPage extends StatelessWidget {
  const DetailChaptersPage({
    super.key,
    required this.sourceKey,
    required this.comicId,
  });

  final String sourceKey;
  final String comicId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DetailViewModel(sourceKey: sourceKey, comicId: comicId)..load(),
      child: const _DetailChaptersScaffold(),
    );
  }
}
```

The success body builds `ChapterGrid` and wires:

```dart
onSelect: (chapter) => openDetailReader(context, vm, chapter),
onDownload: (chapter) => enqueueDetailChapter(context, vm, chapter),
onDownloadAll: () => showChapterDownloadSheet(
  context,
  viewModel: vm,
  chapters: vm.chapters,
),
```

Extract the current detail reader-opening logic into `detail_navigation.dart` as `openDetailReader(BuildContext, DetailViewModel, ComicChapter?)`, so both detail and chapter pages use one implementation. Import `ReaderChapter`, `ComicState`, and the reader route dependencies there.

When `entry == null` and `viewModel.readRecord != null`, resume the saved chapter and page:

```dart
final record = viewModel.readRecord;
final start = entry != null
    ? chapters.firstWhere(
        (chapter) => chapter.id == entry.id,
        orElse: () => chapters.last,
      )
    : record == null
    ? chapters.last
    : chapters.firstWhere(
        (chapter) => chapter.id == record.chapterId,
        orElse: () => chapters.last,
      );
final pageNo = entry == null && record?.chapterId == start.id
    ? record!.pageNo.clamp(0, 1 << 30)
    : 0;
```

Pass `pageNo` into `ComicState`. A direct recent-chapter tap always starts that selected chapter at page zero; the main `继续阅读` action resumes saved progress.

The page must handle loading, error/retry, and empty chapter states without affecting the underlying detail page route.

- [ ] **Step 6: Run tests and commit**

```powershell
dart format lib/views/detail/detail_chapters_page.dart lib/views/detail/detail_navigation.dart lib/views/detail/widgets/chapter_download_sheet.dart lib/views/detail/widgets/chapter_grid.dart test/detail_subpages_test.dart
flutter test --no-pub test/detail_subpages_test.dart test/detail_redesign_test.dart test/download_manager_logic_test.dart
git add lib/views/detail/detail_chapters_page.dart lib/views/detail/detail_navigation.dart lib/views/detail/widgets/chapter_download_sheet.dart lib/views/detail/widgets/chapter_grid.dart test/detail_subpages_test.dart
git commit -m "feat: add full chapter and download page"
```

Expected: PASS.

---

### Task 7: Build the full comments page

**Files:**
- Modify: `lib/views/detail/detail_comments_page.dart`
- Modify: `lib/views/detail/widgets/comment_section.dart`
- Modify: `lib/views/detail/widgets/comment_composer.dart`
- Modify: `test/detail_subpages_test.dart`
- Modify: `test/detail_view_model_test.dart`

- [ ] **Step 1: Add failing full-comment-page test**

Add to `test/detail_subpages_test.dart` using the same in-memory source pattern:

```dart
testWidgets('full comments page loads, paginates, and shows the composer', (
  tester,
) async {
  final source = ComicSource.named(
    name: 'Comment page test',
    key: 'comment-page-test',
    filePath: 'test',
    loadComicInfo: (_) async => Res<ComicInfoData>(
      const ComicInfoData(
        title: 'Comic',
        subTitle: 'Author',
        cover: '',
        description: null,
        tags: <String, List<String>>{},
        chapters: null,
        chapterList: <ComicChapter>[],
        thumbnails: null,
        sourceKey: 'comment-page-test',
        comicId: 'comic',
      ),
    ),
    commentsLoader: (_, __, page, ___) async => Res<CommentPageData>(
      CommentPageData(
        comments: <Comment>[
          Comment('Alice', null, '第一页评论', null, 0, 'comment-1'),
        ],
        page: page,
        totalPages: 2,
        totalComments: 2,
      ),
    ),
    sendCommentFunc: (_, __, ___, ____) async => const Res<bool>(true),
  );
  ComicSource.sources.add(source);
  addTearDown(() => ComicSource.sources.remove(source));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const DetailCommentsPage(
        sourceKey: 'comment-page-test',
        comicId: 'comic',
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('全部评论'), findsOneWidget);
  expect(find.text('第一页评论'), findsOneWidget);
  expect(find.byType(TextField), findsOneWidget);
  expect(find.text('加载更多评论'), findsOneWidget);
});
```

The test source must provide `loadComicInfo`, a two-page `commentsLoader`, and `sendCommentFunc` returning `Res<bool>(true)`.

- [ ] **Step 2: Run and verify failure**

```powershell
flutter test --no-pub test/detail_subpages_test.dart
```

Expected: FAIL because the temporary route shell does not load comments or build the composer.

- [ ] **Step 3: Implement `DetailCommentsPage`**

Use a page-owned `DetailViewModel`. After `load()` succeeds, activate comments exactly once:

```dart
final vm = DetailViewModel(sourceKey: sourceKey, comicId: comicId);
unawaited(vm.load().then((_) async {
  if (vm.state == DetailLoadState.success) await vm.activateComments();
}));
return vm;
```

The scaffold contains:

```dart
Scaffold(
  appBar: AppBar(title: const Text('全部评论')),
  body: switch (vm.state) {
    DetailLoadState.loading || DetailLoadState.idle => const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    DetailLoadState.error => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(vm.error ?? '评论加载失败'),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: vm.reload,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    DetailLoadState.success => ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          CommentSection(
            comments: vm.comments,
            loading: vm.commentsLoading,
            hasMore: vm.hasMoreComments,
            onReply: vm.beginReply,
            onLoadMore: vm.loadMoreComments,
          ),
          CommentComposer(
            replyTarget: vm.replyTarget,
            sending: vm.commentSending,
            error: vm.commentSendError,
            onCancelReply: vm.cancelReply,
            onSend: vm.sendComment,
          ),
        ],
      ),
  },
)
```

If `vm.canLoadComments == false`, render `当前漫画源不支持评论` and omit the composer.

- [ ] **Step 4: Preserve comment behavior tests**

Keep `detail_view_model_test.dart` assertions for:

- comments remain lazy until activated;
- duplicate activation does not refetch page one;
- pagination uses the remote total/page metadata;
- stale generations do not overwrite reloaded comments;
- successful sends refresh page one only when comments are active.

Add one assertion that a source without `commentsLoader` reports `canLoadComments == false`.

- [ ] **Step 5: Run tests and commit**

```powershell
dart format lib/views/detail/detail_comments_page.dart lib/views/detail/widgets/comment_section.dart lib/views/detail/widgets/comment_composer.dart test/detail_subpages_test.dart test/detail_view_model_test.dart
flutter test --no-pub test/detail_subpages_test.dart test/detail_view_model_test.dart test/detail_tabs_test.dart
git add lib/views/detail/detail_comments_page.dart lib/views/detail/widgets/comment_section.dart lib/views/detail/widgets/comment_composer.dart test/detail_subpages_test.dart test/detail_view_model_test.dart
git commit -m "feat: add full comments page"
```

Expected: PASS.

---

### Task 8: Add skeleton, empty states, recommendation hiding, and responsive coverage

**Files:**
- Create: `lib/views/detail/widgets/detail_loading_skeleton.dart`
- Modify: `lib/views/detail/detail_page.dart`
- Modify: `lib/views/detail/widgets/recommendation_carousel.dart`
- Modify: `test/detail_redesign_test.dart`
- Modify: `test/detail_theme_test.dart`

- [ ] **Step 1: Add failing state and responsive tests**

Add to `test/detail_redesign_test.dart`:

```dart
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
  expect(find.byKey(const ValueKey('detail-skeleton-chapters')), findsOneWidget);
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
```

Add a responsive test that pumps the approved composition at `Size(375, 812)`, `Size(768, 1024)`, and `Size(1280, 900)`, then calls `tester.takeException()` and expects null after each pump. Use `tester.view.physicalSize` and reset it with `addTearDown`.

- [ ] **Step 2: Verify failure**

```powershell
flutter test --no-pub test/detail_redesign_test.dart
```

Expected: FAIL because the skeleton is missing and empty recommendations currently render an empty-state card.

- [ ] **Step 3: Implement the loading skeleton**

Build `DetailLoadingSkeleton` from theme-colored boxes with the same seam geometry as `HeroHeader`. Required keys:

```dart
const ValueKey('detail-skeleton-hero')
const ValueKey('detail-skeleton-cover')
const ValueKey('detail-skeleton-chapters')
```

Use stable `AspectRatio`/`SizedBox` geometry and theme muted/elevated surfaces. Do not add shimmer packages. If an animation is used, disable it when `MediaQuery.disableAnimationsOf(context)` is true.

Replace `_Loading` in `detail_page.dart` with `DetailLoadingSkeleton` while keeping the top app bar available.

- [ ] **Step 4: Hide empty recommendations**

At the top of `RecommendationCarousel.build`:

```dart
if (items.isEmpty) return const SizedBox.shrink();
```

Remove the existing `暂无推荐` placeholder branch. Preserve horizontal scrolling, `ComicCard.poster`, headers, selection, and refresh.

Wrap the horizontal list in an `AnimatedSwitcher` keyed by the visible item IDs:

```dart
final motionDisabled = MediaQuery.disableAnimationsOf(context);
final batchKey = ValueKey<String>(items.map((item) => item.id).join('|'));
return AnimatedSwitcher(
  duration: motionDisabled ? Duration.zero : const Duration(milliseconds: 220),
  switchInCurve: Curves.easeOutCubic,
  switchOutCurve: Curves.easeInCubic,
  transitionBuilder: (child, animation) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.04, 0),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    ),
  ),
  child: SizedBox(
    key: batchKey,
    height: 210,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
      itemBuilder: (context, index) {
        final item = items[index];
        return ComicCard.poster(
          title: item.title,
          coverUrl: item.cover,
          subtitle: item.author,
          rating: item.rating,
          width: 132,
          headers: coverHeaders,
          onTap: onSelect == null ? null : () => onSelect!(item),
        );
      },
    ),
  ),
);
```

Do not add rotation, bounce, or scale animation.

- [ ] **Step 5: Apply responsive content width**

In `detail_page.dart`, wrap non-hero sections with a shared helper:

```dart
Widget _constrainedDetailContent(BuildContext context, Widget child) {
  return LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: constraints.maxWidth >= 1100 ? 1040 : double.infinity,
        ),
        child: child,
      ),
    ),
  );
}
```

Do not constrain the full-bleed backdrop. Apply the content maximum to metadata, synopsis, chapters, actions, comments, and recommendations. Ensure text scale 1.3 does not overlap title, score, tags, or buttons.

- [ ] **Step 6: Run state/theme/responsive tests and commit**

```powershell
dart format lib/views/detail/detail_page.dart lib/views/detail/widgets/detail_loading_skeleton.dart lib/views/detail/widgets/recommendation_carousel.dart test/detail_redesign_test.dart test/detail_theme_test.dart
flutter test --no-pub test/detail_redesign_test.dart test/detail_theme_test.dart
git add lib/views/detail/detail_page.dart lib/views/detail/widgets/detail_loading_skeleton.dart lib/views/detail/widgets/recommendation_carousel.dart test/detail_redesign_test.dart test/detail_theme_test.dart
git commit -m "feat: finish responsive detail states"
```

Expected: PASS.

---

### Task 9: Final integration, regression verification, and scope audit

**Files:**
- Verify all files listed in this plan.
- Do not modify unrelated files during this task.

- [ ] **Step 1: Format the complete detail scope**

```powershell
dart format lib/main.dart lib/views/detail test/detail_actions_test.dart test/detail_redesign_test.dart test/detail_subpages_test.dart test/detail_tabs_test.dart test/detail_theme_test.dart test/detail_view_model_test.dart test/routes_test.dart
```

Expected: formatter exits 0.

- [ ] **Step 2: Run targeted tests**

```powershell
flutter test --no-pub test/detail_redesign_test.dart test/detail_subpages_test.dart test/detail_actions_test.dart test/detail_tabs_test.dart test/detail_theme_test.dart test/detail_view_model_test.dart test/detail_view_model_favorite_test.dart test/detail_domain_test.dart test/routes_test.dart test/download_manager_logic_test.dart
```

Expected: all targeted tests pass with zero failures.

- [ ] **Step 3: Run static analysis**

```powershell
flutter analyze --no-pub
```

Expected: `No issues found!`

- [ ] **Step 4: Run the full existing test suite**

```powershell
flutter test --no-pub
```

Expected: all tests pass with zero failures. If an unrelated pre-existing test fails, record the exact test and prove it also fails at the pre-task commit before changing unrelated code.

- [ ] **Step 5: Audit forbidden copy and button/download placement**

```powershell
rg -n "人已评分|人评价|评分人数|人气榜|热度榜|No\.1|StickyActionBar|DetailTabBar" lib/views/detail test
rg -n "DownloadManager|download_rounded|showChapterDownloadSheet" lib/views/detail/detail_page.dart lib/views/detail/detail_chapters_page.dart lib/views/detail/widgets
```

Expected:

- first command returns no production matches;
- `detail_page.dart` contains no download manager/button/sheet references;
- download references exist only in the full chapter page/grid/download-sheet scope;
- exactly one `detail-favorite-button` and one `detail-read-button` are built by the detail composition.

- [ ] **Step 6: Audit Git scope**

```powershell
git status --short
git diff --check
git diff --name-only HEAD~8..HEAD
```

Expected: only approved detail, route, and test files plus the approved spec/plan commits. Do not stage `.superpowers/**`, `tools/**`, prior reader verifier documents, or unrelated user files.

- [ ] **Step 7: Final integration commit if verification required fixes**

Only if Steps 1–6 required tracked fixes:

```powershell
git add lib/main.dart lib/views/detail test/detail_actions_test.dart test/detail_redesign_test.dart test/detail_subpages_test.dart test/detail_tabs_test.dart test/detail_theme_test.dart test/detail_view_model_test.dart test/routes_test.dart
git commit -m "test: verify comic detail redesign"
```

- [ ] **Step 8: Report to Codex**

Report:

- exact changed/created/deleted files;
- commits created;
- targeted/full test counts and results;
- analyze result;
- forbidden-copy/download/button placement audit;
- remaining device-only risks, especially image crop, text scale, and scroll restoration;
- no push performed.
