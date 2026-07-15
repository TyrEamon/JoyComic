import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/jm/jm_parsing.dart';
import 'package:joycomic/network/picacg/picacg_parsing.dart';

void main() {
  group('parsePicacgEpisodePage', () {
    test('parses a normal response', () {
      final page = parsePicacgEpisodePage({
        'data': {
          'eps': {
            'pages': 2,
            'docs': [
              {'order': 1, 'title': '开篇'},
            ],
          },
        },
      });

      expect(page, isNotNull);
      final parsed = page!;
      expect(parsed.pages, 2);
      expect(parsed.episodes, hasLength(1));
      expect(parsed.episodes.single.order, 1);
      expect(parsed.episodes.single.title, '开篇');
    });

    test('accepts string orders and drops non-positive or invalid orders', () {
      final page = parsePicacgEpisodePage({
        'data': {
          'eps': {
            'pages': '3',
            'docs': [
              {'order': '2', 'title': ''},
              {'order': 0, 'title': 'zero'},
              {'order': '-1', 'title': 'negative'},
              {'order': 'bad', 'title': 'invalid'},
            ],
          },
        },
      });

      expect(page, isNotNull);
      final parsed = page!;
      expect(parsed.pages, 3);
      expect(parsed.episodes, hasLength(1));
      expect(parsed.episodes.single.order, 2);
      expect(parsed.episodes.single.title, '第2');
    });

    test('rejects malformed nested structures', () {
      expect(parsePicacgEpisodePage([]), isNull);
      expect(parsePicacgEpisodePage({'data': []}), isNull);
      expect(
        parsePicacgEpisodePage({
          'data': {'eps': 'not-a-map'},
        }),
        isNull,
      );
    });

    test('skips entries missing the required order', () {
      final page = parsePicacgEpisodePage({
        'data': {
          'eps': {
            'docs': [
              {'title': 'missing order'},
              {'order': null, 'title': 'null order'},
            ],
          },
        },
      });

      expect(page, isNotNull);
      final parsed = page!;
      expect(parsed.pages, 1);
      expect(parsed.episodes, isEmpty);
    });
  });

  group('parseJmComicInfoResponse', () {
    test('parses a normal detail response', () {
      final info = parseJmComicInfoResponse({
        'name': '漫画',
        'author': ['作者'],
        'description': '简介',
        'likes': 12,
        'total_views': 34,
        'comment_total': 5,
        'series': [
          {'id': 'chapter-1', 'sort': 1, 'name': '第一话'},
        ],
        'tags': ['标签'],
        'works': ['作品'],
        'actors': ['角色'],
      }, id: 'comic-1');

      expect(info, isNotNull);
      expect(info!.id, 'comic-1');
      expect(info.title, '漫画');
      expect(info.likes, 12);
      expect(info.views, 34);
      expect(info.comments, 5);
      expect(info.series, {1: 'chapter-1'});
      expect(info.epNames, ['第一话']);
    });

    test('accepts string counts and string chapter sort values', () {
      final info = parseJmComicInfoResponse({
        'name': '漫画',
        'likes': '12',
        'totalViews': '34',
        'comments': '5',
        'series': [
          {'id': 99, 'sort': '7', 'name': ''},
        ],
      }, id: 'comic-2');

      expect(info, isNotNull);
      expect(info!.likes, 12);
      expect(info.views, 34);
      expect(info.comments, 5);
      expect(info.series, {7: '99'});
      expect(info.epNames, ['第7話']);
      expect(info.chapters.single.order, 7);
    });

    test(
      'rejects malformed top-level structures and tolerates bad nesting',
      () {
        expect(parseJmComicInfoResponse([], id: 'comic-3'), isNull);

        final info = parseJmComicInfoResponse({
          'name': '漫画',
          'author': {'unexpected': true},
          'series': 'not-a-list',
          'related_list': {'unexpected': true},
        }, id: 'comic-3');

        expect(info, isNotNull);
        expect(info!.author, ['未知']);
        expect(info.series, isEmpty);
        expect(info.relatedComics, isEmpty);
      },
    );

    test(
      'skips chapters missing their required id and defaults missing fields',
      () {
        final info = parseJmComicInfoResponse({
          'series': [
            {'sort': 1, 'name': 'missing id'},
            {'id': null, 'sort': 2},
          ],
        }, id: 'comic-4');

        expect(info, isNotNull);
        expect(info!.title, 'Unknown');
        expect(info.author, ['未知']);
        expect(info.likes, 0);
        expect(info.views, 0);
        expect(info.comments, 0);
        expect(info.series, isEmpty);
        expect(info.epNames, isEmpty);
      },
    );

    test('parses series_id from integer, string, null, and absent values', () {
      final payloads = <Map<String, dynamic>>[
        <String, dynamic>{'series_id': 42},
        <String, dynamic>{'series_id': '42'},
        <String, dynamic>{'series_id': null},
        <String, dynamic>{},
      ];
      final expected = <int?>[42, 42, null, null];

      for (var index = 0; index < payloads.length; index++) {
        final info = parseJmComicInfoResponse(<String, dynamic>{
          'name': 'Series $index',
          'series': <dynamic>[],
          ...payloads[index],
        }, id: 'series-$index');

        expect(info, isNotNull, reason: 'case $index should parse');
        expect(info!.seriesId, expected[index], reason: 'case $index');
      }
    });

    test(
      'normalizes detail images, category names, synopsis, and scalar metrics',
      () {
        final info = parseJmComicInfoResponse({
          'name': 'Normalized detail',
          'description': '<p>Intro</p><div>Next &amp; more<br>Done</div>',
          'category': {'title': 'Main category'},
          'category_sub': {'name': 'Sub category'},
          'tags': ['Label only'],
          'images': [
            '00001.webp',
            {'image': '00002.webp'},
            {'image': null},
            {'unexpected': 'ignored.webp'},
          ],
          'total_views': '1200',
          'likes': 120,
          'comment_total': '7',
          'series': <dynamic>[],
        }, id: 'comic-images');

        expect(info, isNotNull);
        expect(info!.images, <String>['00001.webp', '00002.webp']);
        expect(info.categories, <String>['Main category', 'Sub category']);
        expect(info.tags, <String>['Label only']);
        expect(info.description, 'Intro\nNext & more\nDone');
        expect(info.views, 1200);
        expect(info.likes, 120);
        expect(info.comments, 7);
      },
    );

    test('uses each remote chapter sort value as its actual order', () {
      final info = parseJmComicInfoResponse({
        'name': 'Remote order',
        'series': [
          {'id': 'chapter-9', 'sort': '9', 'name': 'Ninth', 'page_count': '19'},
          {'id': 'chapter-2', 'sort': 2, 'name': 'Second', 'page_count': 12},
        ],
      }, id: 'comic-order');

      expect(info, isNotNull);
      expect(info!.series, <int, String>{9: 'chapter-9', 2: 'chapter-2'});
      expect(info.chapters.map((chapter) => chapter.order), <int>[2, 9]);
      expect(info.chapters.map((chapter) => chapter.chapterId), <String>[
        'chapter-2',
        'chapter-9',
      ]);
      expect(info.chapters.map((chapter) => chapter.title), <String>[
        'Second',
        'Ninth',
      ]);
    });

    test('accepts a top-level scalar image string as a raw image key', () {
      final info = parseJmComicInfoResponse({
        'name': 'Scalar image',
        'images': 'single.webp',
      }, id: 'scalar-string');

      expect(info, isNotNull);
      expect(info!.images, <String>['single.webp']);
    });

    test('accepts a top-level scalar image map as a raw image key', () {
      final info = parseJmComicInfoResponse({
        'name': 'Scalar image map',
        'images': {'image': 'mapped.webp'},
      }, id: 'scalar-map');

      expect(info, isNotNull);
      expect(info!.images, <String>['mapped.webp']);
    });

    test(
      'preserves absolute image URLs without binding relative keys to a host',
      () {
        final info = parseJmComicInfoResponse({
          'name': 'Mixed images',
          'images': ['relative.webp', 'https://images.example/absolute.webp'],
        }, id: 'mixed-images');

        expect(info, isNotNull);
        expect(info!.images, <String>[
          'relative.webp',
          'https://images.example/absolute.webp',
        ]);
      },
    );

    test('assigns a missing sort before an already reserved remote sort 2', () {
      final info = parseJmComicInfoResponse({
        'series': [
          {'id': 'remote-2', 'sort': 2, 'name': 'Remote two'},
          {'id': 'missing', 'name': 'Missing'},
        ],
      }, id: 'order-valid-then-missing')!;

      expect(info.chapters.map((chapter) => chapter.order), <int>[1, 2]);
      expect(info.chapters.map((chapter) => chapter.chapterId), <String>[
        'missing',
        'remote-2',
      ]);
      expect(info.series, <int, String>{1: 'missing', 2: 'remote-2'});
      expect(info.epNames, <String>['Missing', 'Remote two']);
    });

    test(
      'reserves a later valid sort 1 before assigning an earlier missing sort',
      () {
        final info = parseJmComicInfoResponse({
          'series': [
            {'id': 'missing', 'name': 'Missing'},
            {'id': 'remote-1', 'sort': 1, 'name': 'Remote one'},
          ],
        }, id: 'order-missing-then-valid')!;

        expect(info.chapters.map((chapter) => chapter.order), <int>[1, 2]);
        expect(info.chapters.map((chapter) => chapter.chapterId), <String>[
          'remote-1',
          'missing',
        ]);
        expect(info.series, <int, String>{1: 'remote-1', 2: 'missing'});
        expect(info.epNames, <String>['Remote one', 'Missing']);
      },
    );

    test('keeps every chapter when valid remote sorts are duplicated', () {
      final info = parseJmComicInfoResponse({
        'series': [
          {'id': 'first-3', 'sort': 3, 'name': 'First three'},
          {'id': 'duplicate-3', 'sort': 3, 'name': 'Duplicate three'},
          {'id': 'missing', 'sort': 0, 'name': 'Missing'},
        ],
      }, id: 'order-duplicate')!;

      expect(info.chapters, hasLength(3));
      expect(info.chapters.map((chapter) => chapter.order), <int>[1, 2, 3]);
      expect(info.chapters.map((chapter) => chapter.chapterId), <String>[
        'duplicate-3',
        'missing',
        'first-3',
      ]);
      expect(info.series, hasLength(3));
      expect(info.epNames, hasLength(3));
    });

    test('uses the first successfully parsed positive chapter page count', () {
      final info = parseJmComicInfoResponse({
        'series': [
          {
            'id': 'count-fallback',
            'sort': 1,
            'page_count': 'invalid',
            'photo_count': '14',
          },
          {
            'id': 'photos-list',
            'sort': 2,
            'page_count': 0,
            'pageCount': 'invalid',
            'photo_count': null,
            'photos': ['a', 'b', 'c'],
          },
          {'id': 'photos-scalar', 'sort': 3, 'photos': '5'},
        ],
      }, id: 'page-count-fallback')!;

      expect(info.chapters.map((chapter) => chapter.pageCount), <int?>[
        14,
        3,
        5,
      ]);
    });
  });
}
