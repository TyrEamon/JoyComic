import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/foundation/source_session_notifier.dart';
import 'package:joycomic/network/base_comic.dart';
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
    expect(find.text('哔咔分类'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('category-source-tab-jm')));
    await tester.pumpAndSettle();

    expect(find.text('禁漫分类'), findsOneWidget);
    expect(jmLoads, 1);
    expect(picacgLoads, 1);
  });

  testWidgets('refreshing the current source does not initialize a lazy tab', (
    tester,
  ) async {
    var jmLoads = 0;
    var picacgLoads = 0;
    ComicSource.sources.addAll([
      _source('jm', '禁漫', '禁漫分类', onLoad: () => jmLoads++),
      _source('picacg', '哔咔', '哔咔分类', onLoad: () => picacgLoads++),
    ]);

    await tester.pumpWidget(const MaterialApp(home: CategoryPage()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();

    expect(jmLoads, 2);
    expect(picacgLoads, 0);
  });

  testWidgets('shows one source error and retries that source', (tester) async {
    var loads = 0;
    ComicSource.sources.add(
      ComicSource.named(
        key: 'jm',
        name: '禁漫',
        filePath: 'test',
        loadSourceCategories: () async {
          loads++;
          if (loads == 1) {
            return const Res<List<SourceCategory>>(null, errorMessage: '网络错误');
          }
          return Res([SourceCategory(key: 'ok', title: '重试成功')]);
        },
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: CategoryPage()));
    await tester.pump();
    expect(find.text('禁漫分类加载失败'), findsOneWidget);
    expect(find.text('网络错误'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();

    expect(loads, 2);
    expect(find.text('重试成功'), findsOneWidget);
  });

  testWidgets('shows a source-specific empty category state', (tester) async {
    ComicSource.sources.add(
      ComicSource.named(
        key: 'jm',
        name: '禁漫',
        filePath: 'test',
        loadSourceCategories: () async => const Res(<SourceCategory>[]),
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: CategoryPage()));
    await tester.pump();

    expect(find.text('禁漫暂无分类'), findsOneWidget);
    expect(find.text('刷新'), findsOneWidget);
  });

  testWidgets('source login change reloads its categories automatically', (
    tester,
  ) async {
    var loads = 0;
    final source = ComicSource.named(
      key: 'picacg',
      name: '哔咔',
      filePath: 'test',
      requiresLoginForBrowsing: true,
      loadSourceCategories: () async {
        loads++;
        if (!ComicSource.find('picacg')!.isLogin) {
          return const Res<List<SourceCategory>>(null, errorMessage: '未登录');
        }
        return Res([SourceCategory(key: 'after-login', title: '登录后分类')]);
      },
    );
    ComicSource.sources.add(source);

    await tester.pumpWidget(const MaterialApp(home: CategoryPage()));
    await tester.pump();
    expect(find.text('哔咔分类加载失败'), findsOneWidget);
    expect(loads, 1);

    source.data['authenticated'] = true;
    SourceSessionNotifier.instance.notifyChanged('picacg');
    await tester.pump();

    expect(loads, 2);
    expect(find.text('登录后分类'), findsOneWidget);
  });

  testWidgets('stale pre-login category response cannot replace fresh data', (
    tester,
  ) async {
    final staleResponse = Completer<Res<List<SourceCategory>>>();
    var loads = 0;
    final source = ComicSource.named(
      key: 'picacg',
      name: '哔咔',
      filePath: 'test',
      requiresLoginForBrowsing: true,
      loadSourceCategories: () {
        loads++;
        if (loads == 1) return staleResponse.future;
        return Future.value(Res([SourceCategory(key: 'fresh', title: '最新分类')]));
      },
    );
    ComicSource.sources.add(source);

    await tester.pumpWidget(const MaterialApp(home: CategoryPage()));
    await tester.pump();

    source.data['authenticated'] = true;
    SourceSessionNotifier.instance.notifyChanged('picacg');
    await tester.pump();
    expect(find.text('最新分类'), findsOneWidget);

    staleResponse.complete(Res([SourceCategory(key: 'stale', title: '旧分类')]));
    await tester.pump();

    expect(find.text('最新分类'), findsOneWidget);
    expect(find.text('旧分类'), findsNothing);
  });

  testWidgets('switching tabs preserves each source scroll position', (
    tester,
  ) async {
    List<SourceCategory> categories(String prefix) => [
      for (var i = 0; i < 40; i++)
        SourceCategory(key: '$prefix-$i', title: '$prefix 分类 $i'),
    ];
    ComicSource.sources.addAll([
      ComicSource.named(
        key: 'jm',
        name: '禁漫',
        filePath: 'test',
        loadSourceCategories: () async => Res(categories('禁漫')),
      ),
      ComicSource.named(
        key: 'picacg',
        name: '哔咔',
        filePath: 'test',
        loadSourceCategories: () async => Res(categories('哔咔')),
      ),
    ]);

    await tester.pumpWidget(const MaterialApp(home: CategoryPage()));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    final jmList = tester.widget<ListView>(find.byType(ListView));
    final offset = jmList.controller!.offset;
    expect(offset, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('category-source-tab-picacg')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-source-tab-jm')));
    await tester.pumpAndSettle();

    final restored = tester.widget<ListView>(find.byType(ListView));
    expect(restored.controller!.offset, offset);
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

  testWidgets('sort clears old pages and reached end before loading page one', (
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
          if (query.sort == 'popular') {
            return Res(
              SourceContentPage(
                query: query,
                comics: const [_TestComic('new-popular')],
                maxPage: 1,
              ),
            );
          }
          final comics = query.page == 1
              ? [for (var i = 0; i < 15; i++) _TestComic('old-$i')]
              : const [_TestComic('old-tail')];
          return Res(
            SourceContentPage(query: query, comics: comics, maxPage: 2),
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
    await tester.pumpAndSettle();
    await tester.fling(find.byType(GridView), const Offset(0, -3000), 1200);
    await tester.pumpAndSettle();

    expect(queries.any((query) => query.page == 2), isTrue);
    expect(find.text('已经到底了'), findsOneWidget);
    expect(find.text('old-tail'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('source-content-sort-popular')));
    await tester.pumpAndSettle();

    expect(
      queries.last,
      const SourceContentQuery(
        categoryKey: 'category',
        page: 1,
        sort: 'popular',
      ),
    );
    expect(find.text('old-tail'), findsNothing);
    expect(find.text('new-popular'), findsOneWidget);
    expect(find.text('已经到底了'), findsOneWidget);
  });

  testWidgets('category content reloads after its source logs in', (
    tester,
  ) async {
    var contentLoads = 0;
    final source = ComicSource.named(
      key: 'picacg',
      name: '哔咔',
      filePath: 'test',
      requiresLoginForBrowsing: true,
      loadSourceCategories: () async =>
          Res([SourceCategory(key: 'category', title: '分类')]),
      loadSourceContent: (query) async {
        contentLoads++;
        if (!ComicSource.find('picacg')!.isLogin) {
          return const Res<SourceContentPage>(null, errorMessage: '未登录');
        }
        return Res(
          SourceContentPage(
            query: query,
            comics: const [_TestComic('登录后漫画')],
            maxPage: 1,
          ),
        );
      },
    );
    ComicSource.sources.add(source);

    await tester.pumpWidget(
      const MaterialApp(
        home: content_view.SourceContentPage(
          sourceKey: 'picacg',
          kind: 'category',
          category: 'category',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('未登录'), findsOneWidget);
    expect(contentLoads, 1);

    source.data['authenticated'] = true;
    SourceSessionNotifier.instance.notifyChanged('picacg');
    await tester.pumpAndSettle();

    expect(contentLoads, 2);
    expect(find.text('登录后漫画'), findsOneWidget);
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

class _TestComic extends BaseComic {
  @override
  final String id;

  const _TestComic(this.id);

  @override
  String get title => id;

  @override
  String get subTitle => '';

  @override
  String get cover => '';

  @override
  List<String> get tags => const [];

  @override
  String get description => '';
}
