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
      expect(info.series, {1: '99'});
      expect(info.epNames, ['第7話']);
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
  });
}
