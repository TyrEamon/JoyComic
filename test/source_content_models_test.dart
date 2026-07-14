import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/built_in/jm.dart';
import 'package:joycomic/network/base_comic.dart';
import 'package:joycomic/network/jm/jm_network.dart';
import 'package:joycomic/network/picacg/picacg_network.dart';
import 'package:joycomic/views/common/source_content_models.dart';

void main() {
  group('normalizeCategories', () {
    test('rejects empty key or title and web-only entries', () {
      final values = normalizeCategories([
        SourceCategory(key: '', title: 'empty key'),
        SourceCategory(key: 'empty-title', title: ''),
        SourceCategory(key: 'blank', title: '   '),
        SourceCategory(key: 'web', title: 'Web', webOnly: true),
        SourceCategory(key: 'love', title: '恋爱'),
      ]);

      expect(values.map((category) => category.key), ['love']);
    });

    test('keeps the first category for each key', () {
      final values = normalizeCategories([
        SourceCategory(key: 'love', title: '恋爱'),
        SourceCategory(key: 'love', title: '重复分类'),
        SourceCategory(key: 'school', title: '校园'),
      ]);

      expect(values.map((category) => category.title), ['恋爱', '校园']);
    });
  });

  group('source discovery value semantics', () {
    test('keeps hierarchy, visuals, params, and sort options', () {
      final category = SourceCategory(
        key: 'sub-1',
        title: '子分类',
        parentKey: 'parent-1',
        param: 'sub-slug',
        icon: 'icon-name',
        cover: 'https://example.test/cover.jpg',
        sortOptions: const [
          SourceSortOption(key: 'latest', title: '最新'),
          SourceSortOption(key: 'popular', title: '热门'),
        ],
      );

      expect(category.parentKey, 'parent-1');
      expect(category.param, 'sub-slug');
      expect(category.icon, 'icon-name');
      expect(category.cover, 'https://example.test/cover.jpg');
      expect(category.sortOptions.map((option) => option.key), [
        'latest',
        'popular',
      ]);
    });

    test('compares every value object by fields', () {
      const sortA = SourceSortOption(key: 'latest', title: '最新');
      const sortB = SourceSortOption(key: 'latest', title: '最新');
      const sortDifferent = SourceSortOption(key: 'popular', title: '热门');
      expect(sortA, sortB);
      expect(sortA.hashCode, sortB.hashCode);
      expect(sortA, isNot(sortDifferent));

      final categoryA = SourceCategory(
        key: 'category',
        title: '分类',
        parentKey: 'parent',
        param: 'slug',
        icon: 'icon',
        cover: 'cover',
        sortOptions: const [sortA],
      );
      final categoryB = SourceCategory(
        key: 'category',
        title: '分类',
        parentKey: 'parent',
        param: 'slug',
        icon: 'icon',
        cover: 'cover',
        sortOptions: const [sortB],
      );
      final categoryDifferent = SourceCategory(
        key: 'category',
        title: '不同分类',
        sortOptions: const [sortA],
      );
      expect(categoryA, categoryB);
      expect(categoryA.hashCode, categoryB.hashCode);
      expect(categoryA, isNot(categoryDifferent));

      const queryA = SourceContentQuery(
        categoryKey: 'category',
        param: 'slug',
        page: 2,
        sort: 'latest',
      );
      const queryB = SourceContentQuery(
        categoryKey: 'category',
        param: 'slug',
        page: 2,
        sort: 'latest',
      );
      const queryDifferent = SourceContentQuery(
        categoryKey: 'category',
        page: 3,
      );
      expect(queryA, queryB);
      expect(queryA.hashCode, queryB.hashCode);
      expect(queryA, isNot(queryDifferent));

      final pageA = SourceContentPage(
        query: queryA,
        comics: const [_TestComic('comic')],
        maxPage: 4,
      );
      final pageB = SourceContentPage(
        query: queryB,
        comics: const [_TestComic('comic')],
        maxPage: 4,
      );
      final pageDifferent = SourceContentPage(
        query: queryA,
        comics: const [_TestComic('other')],
        maxPage: 4,
      );
      expect(pageA, pageB);
      expect(pageA.hashCode, pageB.hashCode);
      expect(pageA, isNot(pageDifferent));

      final sectionA = SourceContentSection(
        key: 'section',
        title: '分区',
        comics: const [_TestComic('comic')],
        moreQuery: queryA,
      );
      final sectionB = SourceContentSection(
        key: 'section',
        title: '分区',
        comics: const [_TestComic('comic')],
        moreQuery: queryB,
      );
      final sectionDifferent = SourceContentSection(
        key: 'other',
        title: '分区',
        comics: const [_TestComic('comic')],
        moreQuery: queryA,
      );
      expect(sectionA, sectionB);
      expect(sectionA.hashCode, sectionB.hashCode);
      expect(sectionA, isNot(sectionDifferent));
    });

    test('defensively copies and locks every list field', () {
      final mutableOptions = <SourceSortOption>[
        const SourceSortOption(key: 'latest', title: '最新'),
      ];
      final category = SourceCategory(
        key: 'category',
        title: '分类',
        sortOptions: mutableOptions,
      );
      mutableOptions.clear();
      expect(category.sortOptions, hasLength(1));
      expect(
        () => category.sortOptions.add(
          const SourceSortOption(key: 'popular', title: '热门'),
        ),
        throwsUnsupportedError,
      );

      final mutablePageComics = <BaseComic>[const _TestComic('page')];
      final page = SourceContentPage(
        query: const SourceContentQuery(categoryKey: 'category'),
        comics: mutablePageComics,
      );
      mutablePageComics.clear();
      expect(page.comics, hasLength(1));
      expect(() => page.comics.clear(), throwsUnsupportedError);

      final mutableSectionComics = <BaseComic>[const _TestComic('section')];
      final section = SourceContentSection(
        key: 'section',
        title: '分区',
        comics: mutableSectionComics,
      );
      mutableSectionComics.clear();
      expect(section.comics, hasLength(1));
      expect(() => section.comics.clear(), throwsUnsupportedError);
    });
  });

  test('content page preserves category param, requested page, and sort', () {
    const query = SourceContentQuery(
      categoryKey: 'category-id',
      param: 'category-slug',
      page: 4,
      sort: 'popular',
    );
    final page = SourceContentPage(
      query: query,
      comics: const [],
      maxPage: 9,
    );

    expect(page.query.categoryKey, 'category-id');
    expect(page.query.param, 'category-slug');
    expect(page.query.page, 4);
    expect(page.query.sort, 'popular');
    expect(page.maxPage, 9);
  });

  test('drops JM categories without real identifiers', () {
    final categories = parseJmCategories({
      'categories': [
        {
          'name': '缺少父标识',
          'sub_categories': [
            {'name': '缺少子标识'},
          ],
        },
        {
          'name': '有效父分类',
          'id': 9,
          'sub_categories': [
            {'name': '缺少 CID'},
            {'name': '有效子分类', 'CID': 42, 'slug': 'child-slug'},
          ],
        },
      ],
    });

    expect(categories, hasLength(2));
    expect(categories.first.slug, isEmpty);
    expect(categories.first.subCategories, isEmpty);
    expect(categories[1].slug, '9');
    expect(categories[1].subCategories, hasLength(1));
    expect(categories[1].subCategories.single.cid, '42');

    final visible = adaptJmSourceCategories(categories);
    expect(visible.map((category) => category.key), ['9', '42']);
  });

  test('discards an orphan JM subcategory with a real CID', () {
    final categories = adaptJmSourceCategories([
      JmCategory('缺少父标识', '', const [
        JmSubCategory('42', '孤儿子分类', 'child-slug'),
      ]),
    ]);

    expect(categories, isEmpty);
  });

  group('jmCategoryMaxPage', () {
    test('uses the stable protocol page size for a partial final page', () {
      expect(
        jmCategoryMaxPage(total: 101, currentPage: 6, itemCount: 1),
        6,
      );
    });

    test('calculates max page from a full page', () {
      expect(
        jmCategoryMaxPage(total: 101, currentPage: 1, itemCount: 20),
        6,
      );
    });

    test('returns null for content without pagination metadata', () {
      expect(
        jmCategoryMaxPage(total: 0, currentPage: 2, itemCount: 20),
        isNull,
      );
    });

    test('stops at the current page when the response page is empty', () {
      expect(
        jmCategoryMaxPage(total: 0, currentPage: 2, itemCount: 0),
        2,
      );
    });

    test('prefers explicit page count or page size when available', () {
      expect(
        jmCategoryMaxPage(
          total: 101,
          currentPage: 1,
          itemCount: 20,
          pageCount: 7,
        ),
        7,
      );
      expect(
        jmCategoryMaxPage(
          total: 101,
          currentPage: 1,
          itemCount: 20,
          pageSize: 50,
        ),
        3,
      );
    });
  });

  group('parsePicacgCategories', () {
    test('parses ids, titles, covers and filters web-only or malformed items', () {
      final categories = parsePicacgCategories({
        'data': {
          'categories': [
            {
              '_id': 12,
              'title': '数字分类',
              'thumb': {
                'fileServer': 'https://img.example.test',
                'path': 'category/12.jpg',
              },
            },
            {'_id': 'web', 'title': '网页分类', 'isWeb': true},
            {'_id': '', 'title': '空标识'},
            {'_id': 'empty-title', 'title': ''},
            {'title': '标题可作为标识'},
            'not-a-map',
          ],
        },
      });

      expect(categories, hasLength(2));
      expect(categories.first.key, '12');
      expect(categories.first.title, '数字分类');
      expect(categories.first.param, '数字分类');
      expect(
        categories.first.cover,
        'https://img.example.test/static/category/12.jpg',
      );
      expect(categories[1].key, '标题可作为标识');
      expect(categories.map((category) => category.key), isNot(contains('web')));
    });

    test('returns empty for malformed category containers', () {
      expect(parsePicacgCategories({'data': {'categories': 'bad'}}), isEmpty);
      expect(parsePicacgCategories([]), isEmpty);
    });
  });

  group('picacgMaxPage', () {
    test('returns null for content without pagination metadata', () {
      expect(
        picacgMaxPage(currentPage: 2, itemCount: 20),
        isNull,
      );
    });

    test('stops at the current page when the response page is empty', () {
      expect(picacgMaxPage(currentPage: 3, itemCount: 0), 3);
    });

    test('uses explicit page count or total and page size', () {
      expect(
        picacgMaxPage(currentPage: 1, itemCount: 20, pageCount: 5),
        5,
      );
      expect(
        picacgMaxPage(
          currentPage: 1,
          itemCount: 20,
          total: 101,
          pageSize: 20,
        ),
        6,
      );
    });
  });
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

  @override
  bool operator ==(Object other) => other is _TestComic && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
