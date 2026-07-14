import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/common/source_content_models.dart';

void main() {
  group('normalizeCategories', () {
    test('rejects empty key or title and web-only entries', () {
      final values = normalizeCategories([
        const SourceCategory(key: '', title: 'empty key'),
        const SourceCategory(key: 'empty-title', title: ''),
        const SourceCategory(key: 'blank', title: '   '),
        const SourceCategory(key: 'web', title: 'Web', webOnly: true),
        const SourceCategory(key: 'love', title: '恋爱'),
      ]);

      expect(values.map((category) => category.key), ['love']);
    });

    test('keeps the first category for each key', () {
      final values = normalizeCategories([
        const SourceCategory(key: 'love', title: '恋爱'),
        const SourceCategory(key: 'love', title: '重复分类'),
        const SourceCategory(key: 'school', title: '校园'),
      ]);

      expect(values.map((category) => category.title), ['恋爱', '校园']);
    });
  });

  test('category metadata keeps hierarchy, visuals, params, and sort options', () {
    const category = SourceCategory(
      key: 'sub-1',
      title: '子分类',
      parentKey: 'parent-1',
      param: 'sub-slug',
      icon: 'icon-name',
      cover: 'https://example.test/cover.jpg',
      sortOptions: [
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

  test('content page preserves category param, requested page, and sort', () {
    const query = SourceContentQuery(
      categoryKey: 'category-id',
      param: 'category-slug',
      page: 4,
      sort: 'popular',
    );
    const page = SourceContentPage(
      query: query,
      comics: [],
      maxPage: 9,
    );

    expect(page.query.categoryKey, 'category-id');
    expect(page.query.param, 'category-slug');
    expect(page.query.page, 4);
    expect(page.query.sort, 'popular');
    expect(page.maxPage, 9);
  });

  test('category adapter safely stringifies string and numeric keys', () {
    final numeric = SourceCategory.fromJson({
      '_id': 12,
      'title': '数字键',
      'thumb': 'https://example.test/12.jpg',
    });
    final child = SourceCategory.fromJson(
      {
        'CID': '34',
        'name': '字符串键',
      },
      parentKey: 12,
      param: 56,
    );

    expect(numeric.key, '12');
    expect(numeric.cover, 'https://example.test/12.jpg');
    expect(child.key, '34');
    expect(child.parentKey, '12');
    expect(child.param, '56');
  });
}
