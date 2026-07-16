import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/built_in/jm.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/foundation/source_credential_store.dart';
import 'package:joycomic/network/jm/jm_image.dart';
import 'package:joycomic/network/jm/jm_network.dart';
import 'package:joycomic/network/jm/jm_parsing.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/network/source_state.dart';

void main() {
  group('jmInfoToComicInfoData', () {
    test('maps typed JM detail metadata without compatibility count tags', () {
      final info = parseJmComicInfoResponse({
        'name': 'Album title',
        'author': ['Author A', 'Author B'],
        'description': '<p>Intro &amp; details</p>',
        'series_id': '88',
        'category': {'title': 'Main category'},
        'category_sub': {'name': 'Sub category'},
        'tags': ['Label A', 'Label B'],
        'total_views': '1200',
        'likes': 120,
        'comment_total': '7',
        'liked': 1,
        'is_favorite': '1',
        'images': [
          'inline-1.webp',
          {'image': 'inline-2.webp'},
        ],
        'series': [
          {
            'id': 'chapter-20',
            'sort': '20',
            'name': 'Later chapter',
            'page_count': '32',
          },
          {
            'id': 'chapter-3',
            'sort': 3,
            'name': 'Earlier chapter',
            'pageCount': 12,
          },
        ],
      }, id: 'comic-88')!;

      final data = jmInfoToComicInfoData(info);

      expect(data.title, 'Album title');
      expect(data.description, 'Intro & details');
      expect(data.authors, <String>['Author A', 'Author B']);
      expect(data.categories, <String>['Main category', 'Sub category']);
      expect(data.labels, <String>['Label A', 'Label B']);
      expect(data.viewCount, 1200);
      expect(data.likeCount, 120);
      expect(data.commentCount, 7);
      expect(data.sourceKey, 'jm');
      expect(data.comicId, 'comic-88');
      expect(data.isFavorite, isTrue);
      expect(data.isLiked, isTrue);
      expect(data.singleChapterPages, info.images);
      expect(data.chapterList, hasLength(2));
      expect(data.chapterList.map((chapter) => chapter.id), <String>[
        'chapter-3',
        'chapter-20',
      ]);
      expect(data.chapterList.map((chapter) => chapter.title), <String>[
        'Earlier chapter',
        'Later chapter',
      ]);
      expect(data.chapterList.map((chapter) => chapter.order), <int>[3, 20]);
      expect(data.chapterList.map((chapter) => chapter.pageCount), <int?>[
        12,
        32,
      ]);
      expect(data.tags.containsKey('热度'), isFalse);
      expect(data.tags.containsKey('评价人数'), isFalse);
      expect(data.tags.containsKey('收藏'), isFalse);
    });

    test('synthesizes exactly one chapter for all single-volume markers', () {
      final cases = <(String, Map<String, dynamic>)>[
        ('integer zero', <String, dynamic>{'series_id': 0}),
        ('string zero', <String, dynamic>{'series_id': '0'}),
        ('null', <String, dynamic>{'series_id': null}),
        ('absent', <String, dynamic>{}),
      ];

      for (final testCase in cases) {
        final info = parseJmComicInfoResponse(<String, dynamic>{
          'name': 'Single volume',
          'series': <dynamic>[],
          ...testCase.$2,
        }, id: 'single-${testCase.$1}')!;

        final data = jmInfoToComicInfoData(info);

        expect(data.chapterList, hasLength(1), reason: testCase.$1);
        expect(data.chapterList.single.id, info.id, reason: testCase.$1);
        expect(data.chapterList.single.order, 1, reason: testCase.$1);
        expect(
          data.chapterList.single.title,
          'Single volume',
          reason: testCase.$1,
        );
      }
    });

    test('uses 第 1 话 only when a synthetic chapter has an empty title', () {
      final info = parseJmComicInfoResponse({
        'name': '',
        'series_id': 0,
        'series': <dynamic>[],
      }, id: 'untitled-single')!;

      final data = jmInfoToComicInfoData(info);

      expect(data.chapterList, hasLength(1));
      expect(data.chapterList.single.id, 'untitled-single');
      expect(data.chapterList.single.order, 1);
      expect(data.chapterList.single.title, '第 1 话');
    });

    test('keeps real album chapters and never adds a synthetic chapter', () {
      final info = parseJmComicInfoResponse({
        'name': 'Album',
        'series_id': 0,
        'series': [
          {'id': 'real-2', 'sort': 2, 'name': 'Two'},
          {'id': 'real-1', 'sort': 1, 'name': 'One'},
        ],
      }, id: 'album-id')!;

      final data = jmInfoToComicInfoData(info);

      expect(data.chapterList, hasLength(2));
      expect(data.chapterList.map((chapter) => chapter.id), <String>[
        'real-1',
        'real-2',
      ]);
      expect(
        data.chapterList.where((chapter) => chapter.id == 'album-id'),
        isEmpty,
      );
    });

    test('preserves duplicate-sort chapters in the typed adapter list', () {
      final info = parseJmComicInfoResponse({
        'name': 'Duplicate album',
        'series_id': 9,
        'series': [
          {'id': 'first', 'sort': 1, 'name': 'First'},
          {'id': 'duplicate', 'sort': 1, 'name': 'Duplicate'},
        ],
      }, id: 'duplicate-album')!;

      final data = jmInfoToComicInfoData(info);

      expect(data.chapterList, hasLength(2));
      expect(data.chapterList.map((chapter) => chapter.order), <int>[1, 2]);
      expect(data.chapterList.map((chapter) => chapter.id), <String>[
        'first',
        'duplicate',
      ]);
    });
  });

  test('JmComicInfo snapshots every collection passed to its constructor', () {
    final author = <String>['Author'];
    final series = <int, String>{1: 'chapter-1'};
    final epNames = <String>['Chapter one'];
    final tags = <String>['Tag'];
    final works = <String>['Work'];
    final actors = <String>['Actor'];
    final related = <JmComicBrief>[
      const JmComicBrief(
        id: 'related-1',
        author: 'Related author',
        name: 'Related',
        rawDescription: '',
      ),
    ];
    final images = <String>['page.webp'];
    final categories = <String>['Category'];
    final chapters = <JmChapter>[
      const JmChapter(order: 1, chapterId: 'chapter-1', title: 'Chapter one'),
    ];
    final info = JmComicInfo(
      name: 'Snapshot',
      id: 'snapshot',
      author: author,
      description: '',
      likes: 1,
      views: 2,
      series: series,
      tags: tags,
      works: works,
      actors: actors,
      relatedComics: related,
      liked: false,
      favorite: false,
      comments: 3,
      epNames: epNames,
      images: images,
      categories: categories,
      chapters: chapters,
    );

    author.add('Changed');
    series[2] = 'changed';
    epNames.add('Changed');
    tags.add('Changed');
    works.add('Changed');
    actors.add('Changed');
    related.clear();
    images.add('changed.webp');
    categories.add('Changed');
    chapters.clear();

    expect(info.author, <String>['Author']);
    expect(info.series, <int, String>{1: 'chapter-1'});
    expect(info.epNames, <String>['Chapter one']);
    expect(info.tags, <String>['Tag']);
    expect(info.works, <String>['Work']);
    expect(info.actors, <String>['Actor']);
    expect(info.relatedComics.single.id, 'related-1');
    expect(info.images, <String>['page.webp']);
    expect(info.categories, <String>['Category']);
    expect(info.chapters.single.chapterId, 'chapter-1');
    expect(() => info.author.add('blocked'), throwsUnsupportedError);
    expect(() => info.series[2] = 'blocked', throwsUnsupportedError);
    expect(() => info.epNames.add('blocked'), throwsUnsupportedError);
    expect(() => info.tags.add('blocked'), throwsUnsupportedError);
    expect(() => info.works.add('blocked'), throwsUnsupportedError);
    expect(() => info.actors.add('blocked'), throwsUnsupportedError);
    expect(() => info.relatedComics.clear(), throwsUnsupportedError);
    expect(() => info.images.add('blocked'), throwsUnsupportedError);
    expect(() => info.categories.add('blocked'), throwsUnsupportedError);
    expect(() => info.chapters.clear(), throwsUnsupportedError);
  });

  test(
    'JM source init restores the persisted image host for singleton paths',
    () async {
      final originalBaseUrl = jmBaseUrl;
      final singleton = JmNetwork();
      final originalState = singleton.state;
      addTearDown(() {
        jmBaseUrl = originalBaseUrl;
        singleton.state = originalState;
      });
      jmBaseUrl = 'https://stale-global.example';
      final source = buildJmSource(
        credentialStore: SourceCredentialStore(_MemorySecretStore()),
      );
      source.data['imageBaseUrl'] = 'https://persisted-images.example';

      await source.initData!(source);

      expect(jmBaseUrl, 'https://persisted-images.example');
      expect(source.data['apiBaseUrl'], 'https://${jmBuiltInDomains.first}');
      expect(source.data['selectedShuntKey'], jmExpressShuntKey);
    },
  );

  group('JM page loading contract', () {
    test('relative inline pages prefer the network state image host', () async {
      final originalBaseUrl = jmBaseUrl;
      addTearDown(() => jmBaseUrl = originalBaseUrl);
      jmBaseUrl = 'https://wrong-global.example';
      final network = JmNetwork(
        getRequest: (_) async => const Res<dynamic>(<String, dynamic>{
          'name': 'State-host comic',
          'series_id': 0,
          'series': <dynamic>[],
          'images': <String>['relative.webp'],
        }),
      );
      network.state = _TestJmState(
        imageBaseUrl: 'https://state-images.example',
      );

      final pages = await network.getComicPages('state-comic', null);

      expect(pages.data, <String>[
        'https://state-images.example/media/photos/state-comic/relative.webp',
      ]);
      expect(
        pages.data.single,
        isNot(startsWith('https://wrong-global.example/')),
      );
    });

    test(
      'uses per-comic inline pages for null or matching chapter ids and delegates other chapters',
      () async {
        final requestedChapterIds = <String>[];
        final network = JmNetwork(
          getRequest: (url) async {
            final uri = Uri.parse(url);
            if (uri.path.endsWith('/album')) {
              final comicId = uri.queryParameters['id']!;
              return Res<dynamic>(<String, dynamic>{
                'name': 'Comic $comicId',
                'series_id': 0,
                'series': const <dynamic>[],
                'images': <dynamic>[
                  {'image': '$comicId-inline.webp'},
                ],
              });
            }
            if (uri.path.endsWith('/chapter')) {
              final chapterId = uri.queryParameters['id']!;
              requestedChapterIds.add(chapterId);
              return Res<dynamic>(<String, dynamic>{
                'images': <String>['$chapterId-remote.webp'],
              });
            }
            return const Res<dynamic>.error('unexpected GET');
          },
        );

        await network.getComicInfo('comic-a');
        await network.getComicInfo('comic-b');

        final aDefault = await network.getComicPages('comic-a', null);
        final aMatching = await network.getComicPages('comic-a', 'comic-a');
        final bDefault = await network.getComicPages('comic-b', null);
        final aAgain = await network.getComicPages('comic-a', null);

        expect(aDefault.data, <String>[
          getJmImageUrl('comic-a-inline.webp', 'comic-a'),
        ]);
        expect(aMatching.data, aDefault.data);
        expect(bDefault.data, <String>[
          getJmImageUrl('comic-b-inline.webp', 'comic-b'),
        ]);
        expect(aAgain.data, aDefault.data);
        expect(requestedChapterIds, isEmpty);

        final remote = await network.getComicPages('comic-a', 'chapter-9');

        expect(requestedChapterIds, <String>['chapter-9']);
        expect(remote.data, <String>[
          getJmImageUrl('chapter-9-remote.webp', 'chapter-9'),
        ]);
      },
    );

    test(
      'cold cache loads inline pages from album without calling chapter',
      () async {
        var albumCalls = 0;
        var chapterCalls = 0;
        final network = JmNetwork(
          getRequest: (url) async {
            final uri = Uri.parse(url);
            if (uri.path.endsWith('/album')) {
              albumCalls++;
              return const Res<dynamic>(<String, dynamic>{
                'name': 'Cold comic',
                'series_id': 0,
                'series': <dynamic>[],
                'images': 'cold-inline.webp',
              });
            }
            if (uri.path.endsWith('/chapter')) {
              chapterCalls++;
              return const Res<dynamic>(<String, dynamic>{
                'images': <String>['unexpected.webp'],
              });
            }
            return const Res<dynamic>.error('unexpected GET');
          },
        );

        final pages = await network.getComicPages('cold-comic', null);

        expect(pages.error, isFalse);
        expect(pages.data, <String>[
          getJmImageUrl('cold-inline.webp', 'cold-comic'),
        ]);
        expect(albumCalls, 1);
        expect(chapterCalls, 0);
      },
    );

    test(
      'cold cache propagates album errors without calling chapter',
      () async {
        var chapterCalls = 0;
        final network = JmNetwork(
          getRequest: (url) async {
            final uri = Uri.parse(url);
            if (uri.path.endsWith('/album')) {
              return const Res<dynamic>.error('album failed');
            }
            if (uri.path.endsWith('/chapter')) {
              chapterCalls++;
              return const Res<dynamic>(<String, dynamic>{
                'images': <String>['hidden.webp'],
              });
            }
            return const Res<dynamic>.error('unexpected GET');
          },
        );

        final pages = await network.getComicPages('error-comic', 'error-comic');

        expect(pages.error, isTrue);
        expect(pages.errorMessage, 'album failed');
        expect(chapterCalls, 0);
      },
    );

    test(
      'cold cache falls back after a successful detail with no images',
      () async {
        var albumCalls = 0;
        var chapterCalls = 0;
        final network = JmNetwork(
          getRequest: (url) async {
            final uri = Uri.parse(url);
            if (uri.path.endsWith('/album')) {
              albumCalls++;
              return const Res<dynamic>(<String, dynamic>{
                'name': 'No inline pages',
                'series_id': 0,
                'series': <dynamic>[],
              });
            }
            if (uri.path.endsWith('/chapter')) {
              chapterCalls++;
              return const Res<dynamic>(<String, dynamic>{
                'images': <String>['fallback.webp'],
              });
            }
            return const Res<dynamic>.error('unexpected GET');
          },
        );

        final pages = await network.getComicPages('fallback-comic', null);

        expect(pages.data, <String>[
          getJmImageUrl('fallback.webp', 'fallback-comic'),
        ]);
        expect(albumCalls, 1);
        expect(chapterCalls, 1);
      },
    );

    test(
      'cached raw keys follow the current host and replace or clear safely',
      () async {
        final originalBaseUrl = jmBaseUrl;
        addTearDown(() => jmBaseUrl = originalBaseUrl);
        var albumCalls = 0;
        var chapterCalls = 0;
        var albumImages = <dynamic>['first.webp'];
        final network = JmNetwork(
          getRequest: (url) async {
            final uri = Uri.parse(url);
            if (uri.path.endsWith('/album')) {
              albumCalls++;
              return Res<dynamic>(<String, dynamic>{
                'name': 'Mutable response',
                'series_id': 0,
                'series': const <dynamic>[],
                'images': albumImages,
              });
            }
            if (uri.path.endsWith('/chapter')) {
              chapterCalls++;
              return const Res<dynamic>(<String, dynamic>{
                'images': <String>['fallback.webp'],
              });
            }
            return const Res<dynamic>.error('unexpected GET');
          },
        );

        await network.getComicInfo('cache-comic');
        albumImages[0] = 'mutated-after-parse.webp';
        jmBaseUrl = 'https://host-one.example';
        final first = await network.getComicPages('cache-comic', null);

        expect(first.data, <String>[
          'https://host-one.example/media/photos/cache-comic/first.webp',
        ]);
        expect(() => first.data.add('blocked'), throwsUnsupportedError);

        jmBaseUrl = 'https://host-two.example';
        final sameCache = await network.getComicPages('cache-comic', null);
        expect(sameCache.data, <String>[
          'https://host-two.example/media/photos/cache-comic/first.webp',
        ]);

        albumImages = <dynamic>[
          'second.webp',
          'https://fixed.example/absolute.webp',
        ];
        await network.getComicInfo('cache-comic');
        final replaced = await network.getComicPages('cache-comic', null);
        expect(replaced.data, <String>[
          'https://host-two.example/media/photos/cache-comic/second.webp',
          'https://fixed.example/absolute.webp',
        ]);

        albumImages = <dynamic>[];
        await network.getComicInfo('cache-comic');
        final cleared = await network.getComicPages('cache-comic', null);
        expect(cleared.data, <String>[
          'https://host-two.example/media/photos/cache-comic/fallback.webp',
        ]);
        expect(albumCalls, 4);
        expect(chapterCalls, 1);
      },
    );

    test(
      'inline page cache is bounded and evicts the least recent comic',
      () async {
        final albumCalls = <String, int>{};
        final network = JmNetwork(
          getRequest: (url) async {
            final uri = Uri.parse(url);
            final comicId = uri.queryParameters['id']!;
            albumCalls.update(comicId, (count) => count + 1, ifAbsent: () => 1);
            return Res<dynamic>(<String, dynamic>{
              'name': comicId,
              'series_id': 0,
              'series': const <dynamic>[],
              'images': <String>['$comicId.webp'],
            });
          },
        );

        for (var index = 0; index < 65; index++) {
          await network.getComicInfo('comic-$index');
        }
        await network.getComicPages('comic-0', null);

        expect(albumCalls['comic-0'], 2);
        expect(albumCalls['comic-64'], 1);
      },
    );

    test(
      'default singleton and custom instances keep independent caches',
      () async {
        final singletonA = JmNetwork();
        final singletonB = JmNetwork();
        JmGetRequest requestFor(String image) =>
            (_) async => Res<dynamic>(<String, dynamic>{
              'name': image,
              'series_id': 0,
              'series': const <dynamic>[],
              'images': <String>[image],
            });
        final customA = JmNetwork(getRequest: requestFor('a.webp'));
        final customB = JmNetwork(getRequest: requestFor('b.webp'));

        final pagesA = await customA.getComicPages('same-comic', null);
        final pagesB = await customB.getComicPages('same-comic', null);

        expect(identical(singletonA, singletonB), isTrue);
        expect(identical(customA, customB), isFalse);
        expect(identical(customA, singletonA), isFalse);
        expect(pagesA.data, <String>[getJmImageUrl('a.webp', 'same-comic')]);
        expect(pagesB.data, <String>[getJmImageUrl('b.webp', 'same-comic')]);
      },
    );
  });

  group('JM comment sending', () {
    test(
      'source sender trims top-level content and prefixes reply usernames',
      () async {
        final sentPayloads = <List<String>>[];
        final source = buildJmSource(
          commentSender: (comicId, content) async {
            sentPayloads.add(<String>[comicId, content]);
            return const Res(true);
          },
        );
        final sender = source.sendCommentFunc!;

        final topLevel = await sender('comic-1', null, '  hello world  ', null);
        final reply = await sender(
          'comic-1',
          null,
          '  thanks  ',
          const CommentReplyTarget(id: 'comment-7', userName: 'Mimi'),
        );

        expect(topLevel.data, isTrue);
        expect(reply.data, isTrue);
        expect(sentPayloads, <List<String>>[
          <String>['comic-1', 'hello world'],
          <String>['comic-1', '@Mimi thanks'],
        ]);
      },
    );

    test('network sendComment URL-encodes the form fields', () async {
      String? postedUrl;
      String? postedBody;
      final network = JmNetwork(
        postRequest: (url, body) async {
          postedUrl = url;
          postedBody = body;
          return const Res<dynamic>(<String, dynamic>{'success': true});
        },
      );

      final result = await network.sendComment('comic & 1', 'A+B & 中文');

      expect(result.data, isTrue);
      expect(Uri.parse(postedUrl!).path, endsWith('/comment'));
      expect(Uri.splitQueryString(postedBody!), <String, String>{
        'video_id': 'comic & 1',
        'comment': 'A+B & 中文',
        'status': 'true',
      });
    });

    test('network sendComment propagates request errors', () async {
      final network = JmNetwork(
        postRequest: (url, body) async =>
            const Res<dynamic>.error('comment rejected'),
      );

      final result = await network.sendComment('comic-1', 'hello');

      expect(result.error, isTrue);
      expect(result.errorMessage, 'comment rejected');
      expect(result.dataOrNull, isNull);
    });
  });

  test('strict JM CommentPageData parsing remains intact', () {
    final valid = parseJmCommentPage({
      'page': '1',
      'total': '21',
      'list': [
        {
          'id': 'comment-1',
          'username': 'Mimi',
          'content': 'Hello',
          'replys': <dynamic>[],
        },
      ],
    }, page: 1);
    final malformed = parseJmCommentPage({
      'page': 1,
      'total': 1,
      'list': [
        {'id': 'comment-1', 'replys': 'not-a-list'},
      ],
    }, page: 1);

    expect(valid.error, isFalse);
    expect(valid.data.page, 1);
    expect(valid.data.totalPages, 2);
    expect(valid.data.totalComments, 21);
    expect(valid.data.comments, hasLength(1));
    expect(malformed.error, isTrue);
    expect(malformed.errorMessage, '评论解析失败');
  });
}

class _TestJmState implements JmState {
  _TestJmState({required this.imageBaseUrl});

  @override
  String avs = '';
  @override
  String apiBaseUrl = 'https://api.example';
  @override
  String imageBaseUrl;
  @override
  String preferredDomain = '';
  @override
  List<JmShunt> shunts = const <JmShunt>[];
  @override
  int selectedShuntKey = 0;
  @override
  String? username;

  @override
  Future<void> clearAvs() async => avs = '';
  @override
  List<String>? getAccount() => null;
  @override
  Future<bool> reLogin() async => true;
  @override
  Future<void> setAvs(String value) async => avs = value;
  @override
  void setApiBaseUrl(String url) => apiBaseUrl = url;
  @override
  void setImageBaseUrl(String url) => imageBaseUrl = url;
  @override
  void setPreferredDomain(String domain) => preferredDomain = domain;
  @override
  void setSelectedShuntKey(int key) => selectedShuntKey = key;
  @override
  void setShunts(List<JmShunt> value) => shunts = value;
}

class _MemorySecretStore implements SecretKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
