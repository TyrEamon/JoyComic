import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/built_in/picacg.dart';
import 'package:joycomic/network/picacg/picacg_network.dart';
import 'package:joycomic/network/res.dart';

void main() {
  group('picacgItemToComicInfoData', () {
    test(
      'maps typed metrics, metadata, and chapters without fake count tags',
      () {
        final detail = ComicItem(
          id: 'comic-1',
          title: 'Pica detail',
          author: 'Author A',
          description: 'Remote synopsis',
          thumbUrl: 'https://img.example/cover.webp',
          chineseTeam: 'Team C',
          categories: <String>['青年'],
          tags: <String>['冒险', '长篇'],
          views: 4567,
          likes: 321,
          comments: 37,
          isLiked: true,
          isFavourite: true,
          epsCount: 2,
          pagesCount: 48,
          time: '2026-07-15T00:00:00Z',
          episodes: const <PicacgEpisode>[
            PicacgEpisode(title: '第一章', order: 1),
            PicacgEpisode(title: '第二章', order: 2),
          ],
          recommendation: <ComicItemBrief>[],
        );

        final info = picacgItemToComicInfoData(detail);

        expect(info.title, 'Pica detail');
        expect(info.description, 'Remote synopsis');
        expect(info.authors, <String>['Author A']);
        expect(info.categories, <String>['青年']);
        expect(info.labels, <String>['冒险', '长篇']);
        expect(info.viewCount, 4567);
        expect(info.likeCount, 321);
        expect(info.commentCount, 37);
        expect(info.isLiked, isTrue);
        expect(info.isFavorite, isTrue);
        expect(info.tags['作者'], <String>['Author A']);
        expect(info.tags['汉化组'], <String>['Team C']);
        expect(info.tags['分类'], <String>['青年']);
        expect(info.tags['标签'], <String>['冒险', '长篇']);
        expect(info.tags, isNot(contains('热度')));
        expect(info.tags, isNot(contains('评价人数')));
        expect(info.chapters, <String, String>{'1': '第一章', '2': '第二章'});
        expect(
          info.chapterList.map(
            (chapter) => (chapter.id, chapter.title, chapter.order),
          ),
          <(String, String, int)>[('1', '第一章', 1), ('2', '第二章', 2)],
        );
      },
    );

    test('ComicItem snapshots detail collections at the parsing boundary', () {
      final categories = <String>['青年'];
      final tags = <String>['冒险'];
      final episodes = <PicacgEpisode>[
        const PicacgEpisode(title: '第一章', order: 1),
      ];
      final recommendations = <ComicItemBrief>[
        const ComicItemBrief(
          title: 'Related',
          author: 'Other',
          likes: 1,
          coverPath: 'cover',
          id: 'related',
        ),
      ];
      final detail = ComicItem(
        id: 'comic-1',
        title: 'Snapshot',
        author: 'Author',
        description: 'Synopsis',
        thumbUrl: 'cover',
        chineseTeam: '',
        categories: categories,
        tags: tags,
        views: 1,
        likes: 2,
        comments: 3,
        isLiked: false,
        isFavourite: false,
        epsCount: 1,
        pagesCount: 10,
        time: '',
        episodes: episodes,
        recommendation: recommendations,
      );

      categories.add('mutated');
      tags.add('mutated');
      episodes.clear();
      recommendations.clear();

      expect(detail.categories, <String>['青年']);
      expect(detail.tagList, <String>['冒险']);
      expect(detail.episodes, hasLength(1));
      expect(detail.recommendation, hasLength(1));
      expect(() => detail.categories.add('blocked'), throwsUnsupportedError);
      expect(() => detail.tagList.add('blocked'), throwsUnsupportedError);
      expect(() => detail.episodes.clear(), throwsUnsupportedError);
      expect(() => detail.recommendation.clear(), throwsUnsupportedError);
    });
  });

  test(
    'getComicInfo parses views aliases and keeps categories separate from tags',
    () async {
      final requestedUrls = <String>[];
      final network = PicacgNetwork(
        getRequest: (url) async {
          requestedUrls.add(url);
          if (url.endsWith('/comics/comic-1')) {
            return const Res<Map<String, dynamic>>(<String, dynamic>{
              'data': <String, dynamic>{
                'comic': <String, dynamic>{
                  '_id': 'comic-1',
                  'title': 'Parsed detail',
                  'description': 'Parsed synopsis',
                  'author': 'Fallback author',
                  '_creator': <String, dynamic>{'name': 'Creator'},
                  'thumb': <String, dynamic>{
                    'fileServer': 'https://img.example',
                    'path': 'cover.webp',
                  },
                  'chineseTeam': 'Team',
                  'categories': <String>['青年'],
                  'tags': <String>['冒险'],
                  'viewsCount': '4567',
                  'likesCount': '321',
                  'commentsCount': '37',
                  'isLiked': true,
                  'isFavourite': true,
                  'epsCount': 1,
                  'pagesCount': 12,
                },
              },
            });
          }
          if (url.contains('/comics/comic-1/eps?page=1')) {
            return const Res<Map<String, dynamic>>(<String, dynamic>{
              'data': <String, dynamic>{
                'eps': <String, dynamic>{
                  'pages': 1,
                  'docs': <Map<String, dynamic>>[
                    <String, dynamic>{'order': '1', 'title': '第一章'},
                  ],
                },
              },
            });
          }
          if (url.endsWith('/comics/comic-1/recommendation')) {
            return const Res<Map<String, dynamic>>(<String, dynamic>{
              'data': <String, dynamic>{'comics': <dynamic>[]},
            });
          }
          return const Res<Map<String, dynamic>>(
            null,
            errorMessage: 'unexpected request',
          );
        },
      );

      final result = await network.getComicInfo('comic-1');

      expect(result.error, isFalse);
      expect(result.data.views, 4567);
      expect(result.data.likes, 321);
      expect(result.data.comments, 37);
      expect(result.data.categories, <String>['青年']);
      expect(result.data.tagList, <String>['冒险']);
      expect(result.data.episodes.single.order, 1);
      expect(requestedUrls, hasLength(3));
    },
  );

  for (final entry in <MapEntry<String, Object>>[
    const MapEntry<String, Object>('totalViews', '88'),
    const MapEntry<String, Object>('views', 99),
  ]) {
    test('getComicInfo accepts ${entry.key} as a view-count alias', () async {
      final network = PicacgNetwork(
        getRequest: (url) async {
          if (url.endsWith('/comics/alias')) {
            return Res<Map<String, dynamic>>(<String, dynamic>{
              'data': <String, dynamic>{
                'comic': <String, dynamic>{
                  '_id': 'alias',
                  'title': 'Alias',
                  'author': 'Author',
                  'thumb': 'cover',
                  entry.key: entry.value,
                },
              },
            });
          }
          if (url.contains('/comics/alias/eps?page=1')) {
            return const Res<Map<String, dynamic>>(<String, dynamic>{
              'data': <String, dynamic>{
                'eps': <String, dynamic>{'pages': 1, 'docs': <dynamic>[]},
              },
            });
          }
          return const Res<Map<String, dynamic>>(<String, dynamic>{
            'data': <String, dynamic>{'comics': <dynamic>[]},
          });
        },
      );

      final result = await network.getComicInfo('alias');

      expect(result.data.views, entry.key == 'views' ? 99 : 88);
    });
  }
}
