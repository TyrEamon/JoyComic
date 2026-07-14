import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/views/category/category_page.dart';
import 'package:joycomic/views/common/source_content_models.dart';
import 'package:joycomic/views/common/source_content_page.dart' as content_view;

void main() {
  setUp(ComicSource.sources.clear);
  tearDown(ComicSource.sources.clear);

  testWidgets('shows one tab per enabled category-capable source', (
    tester,
  ) async {
    ComicSource.sources.addAll([
      _source('jm', '禁漫', '禁漫分类'),
      _source('picacg', '哔咔', '哔咔分类'),
      ComicSource.named(key: 'unsupported', name: '无分类能力', filePath: 'test'),
    ]);

    await tester.pumpWidget(const MaterialApp(home: CategoryPage()));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('category-source-tab-jm')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('category-source-tab-picacg')),
      findsOneWidget,
    );
    expect(find.text('无分类能力'), findsNothing);
    expect(find.text('禁漫分类'), findsOneWidget);
  });

  testWidgets('switches tabs without reloading either source state', (
    tester,
  ) async {
    var jmLoads = 0;
    var picacgLoads = 0;
    ComicSource.sources.addAll([
      _source('jm', '禁漫', '禁漫分类', onLoad: () => jmLoads++),
      _source('picacg', '哔咔', '哔咔分类', onLoad: () => picacgLoads++),
    ]);

    await tester.pumpWidget(const MaterialApp(home: CategoryPage()));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('category-source-tab-picacg')));
    await tester.pumpAndSettle();

    expect(find.text('禁漫分类'), findsNothing);
    expect(find.text('哔咔分类'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('category-source-tab-jm')));
    await tester.pumpAndSettle();

    expect(find.text('禁漫分类'), findsOneWidget);
    expect(jmLoads, 1);
    expect(picacgLoads, 1);
  });

  test('category content location round-trips encoded route values', () {
    final location = buildCategoryContentLocation(
      sourceKey: 'jm/source',
      category: SourceCategory(
        key: '父 子/分类?',
        title: '编码分类',
        param: '参数 & 值',
        sortOptions: const [SourceSortOption(key: 'month sort', title: '月排行')],
      ),
    );
    final uri = Uri.parse(location);

    expect(uri.pathSegments, ['content', 'jm/source']);
    expect(uri.queryParameters, {
      'kind': 'category',
      'category': '父 子/分类?',
      'param': '参数 & 值',
      'sort': 'month sort',
    });
    expect(location, isNot(contains('/detail/')));
  });

  testWidgets('renders child categories beneath their parent', (tester) async {
    ComicSource.sources.add(
      ComicSource.named(
        key: 'jm',
        name: '禁漫',
        filePath: 'test',
        loadSourceCategories: () async => Res([
          SourceCategory(key: 'parent', title: '父分类'),
          SourceCategory(key: 'child', title: '子分类', parentKey: 'parent'),
        ]),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: CategoryPage()));
    await tester.pump();

    expect(find.text('父分类'), findsOneWidget);
    expect(find.text('子分类'), findsOneWidget);
    expect(find.byIcon(Icons.subdirectory_arrow_right), findsOneWidget);
  });

  testWidgets('switching result sort reloads page one with the new sort', (
    tester,
  ) async {
    final queries = <SourceContentQuery>[];
    ComicSource.sources.add(
      ComicSource.named(
        key: 'jm',
        name: '禁漫',
        filePath: 'test',
        loadSourceCategories: () async => Res([
          SourceCategory(
            key: 'category',
            title: '分类',
            sortOptions: const [
              SourceSortOption(key: 'latest', title: '最新'),
              SourceSortOption(key: 'popular', title: '热门'),
            ],
          ),
        ]),
        loadSourceContent: (query) async {
          queries.add(query);
          return Res(
            SourceContentPage(query: query, comics: const [], maxPage: 1),
          );
        },
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: content_view.SourceContentPage(
          sourceKey: 'jm',
          kind: 'category',
          category: 'category',
          sort: 'latest',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('source-content-sort-popular')));
    await tester.pump();

    expect(queries.map((query) => query.sort), ['latest', 'popular']);
    expect(queries.last.page, 1);
  });
  testWidgets('shows an empty state when no category source is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CategoryPage()));

    expect(find.text('暂无可用分类源'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
  });
}

ComicSource _source(
  String key,
  String name,
  String categoryTitle, {
  VoidCallback? onLoad,
}) {
  return ComicSource.named(
    key: key,
    name: name,
    filePath: 'test',
    loadSourceCategories: () async {
      onLoad?.call();
      return Res([SourceCategory(key: '$key-category', title: categoryTitle)]);
    },
  );
}
