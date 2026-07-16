import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/jm/jm_network.dart';
import 'package:joycomic/network/res.dart';

void main() {
  test('JmVideoItem parses fields and normalizes relative photo', () {
    final item = JmVideoItem.fromJson(<String, dynamic>{
      'id': 'v1',
      'title': 'Video One',
      'photo': '/media/video.jpg',
      'tags': <String>['H动漫', 'HD'],
      'backlink': 'https://18comic.vip/video/v1',
    }, imageBaseUrl: 'https://img.example');
    expect(item.id, 'v1');
    expect(item.title, 'Video One');
    expect(item.photo, 'https://img.example/media/video.jpg');
    expect(item.tags, <String>['H动漫', 'HD']);
    expect(item.backlink, 'https://18comic.vip/video/v1');
  });

  test('JmVideoDetail parses source, full URL, and related videos', () {
    final detail = JmVideoDetail.fromJson(<String, dynamic>{
      'video': <String, dynamic>{
        'vid': 'v2',
        'title': 'Detail',
        'photo': 'cover.jpg',
        'video_src': 'https://cdn.example/video.m3u8',
        'full_url': 'https://18comic.vip/video/v2',
        'tags': <String>['movie'],
      },
      'related_videos': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'r1', 'title': 'Related'},
      ],
    }, imageBaseUrl: 'https://img.example');
    expect(detail.id, 'v2');
    expect(detail.videoSrc, 'https://cdn.example/video.m3u8');
    expect(detail.fullUrl, 'https://18comic.vip/video/v2');
    expect(detail.relatedVideos.single.id, 'r1');
  });

  test('getVideos sends category search and pagination parameters', () async {
    late String requestedUrl;
    final network = JmNetwork(
      getRequest: (url) async {
        requestedUrl = url;
        return const Res<dynamic>(<String, dynamic>{
          'list': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'v1', 'title': 'One'},
          ],
          'total': '41',
        });
      },
    );
    final result = await network.getVideos(
      page: 2,
      videoType: 'video',
      searchQuery: 'H动漫',
    );
    final uri = Uri.parse(requestedUrl);
    expect(uri.path, endsWith('/videos'));
    expect(uri.queryParameters['page'], '2');
    expect(uri.queryParameters['video_type'], 'video');
    expect(uri.queryParameters['search_query'], 'H动漫');
    expect(result.data.items.single.id, 'v1');
    expect(result.data.total, 41);
  });

  test('video detail falls back from vid to id parameter', () async {
    final requests = <String>[];
    final network = JmNetwork(
      getRequest: (url) async {
        requests.add(url);
        if (Uri.parse(url).queryParameters.containsKey('vid')) {
          return const Res<dynamic>(null, errorMessage: 'unsupported');
        }
        return const Res<dynamic>(<String, dynamic>{
          'video': <String, dynamic>{'vid': 'v3', 'title': 'Fallback'},
          'related_videos': <dynamic>[],
        });
      },
    );
    final result = await network.getVideoDetail('v3');
    expect(result.error, isFalse);
    expect(requests, hasLength(2));
    expect(Uri.parse(requests.first).queryParameters['vid'], 'v3');
    expect(Uri.parse(requests.last).queryParameters['id'], 'v3');
  });

  test('latest hanime parses list payload', () async {
    final network = JmNetwork(
      getRequest: (_) async => const Res<dynamic>(<String, dynamic>{
        'list': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'h1', 'title': 'Latest'},
        ],
      }),
    );
    final result = await network.getLatestHanime();
    expect(result.data.single.id, 'h1');
  });

  test('video model collections are immutable defensive copies', () {
    final itemTags = <String>['HD'];
    final item = JmVideoItem(
      id: 'item',
      title: 'Item',
      photo: '',
      tags: itemTags,
      backlink: '',
    );
    final related = <JmVideoItem>[item];
    final detailTags = <String>['movie'];
    final detail = JmVideoDetail(
      id: 'detail',
      title: 'Detail',
      description: '',
      photo: '',
      videoSrc: '',
      fullUrl: '',
      tags: detailTags,
      backlink: '',
      relatedVideos: related,
    );

    itemTags.add('mutated');
    detailTags.add('mutated');
    related.clear();

    expect(item.tags, <String>['HD']);
    expect(detail.tags, <String>['movie']);
    expect(detail.relatedVideos, <JmVideoItem>[item]);
    expect(() => item.tags.add('blocked'), throwsUnsupportedError);
    expect(() => detail.tags.clear(), throwsUnsupportedError);
    expect(() => detail.relatedVideos.clear(), throwsUnsupportedError);
  });

  test(
    'video cover normalization handles protocol-relative and unsafe URLs',
    () {
      expect(
        normalizeJmVideoUrl('//cdn.example/cover.jpg', 'https://img.example'),
        'https://cdn.example/cover.jpg',
      );
      expect(
        normalizeJmVideoUrl('file:///private/cover.jpg', 'https://img.example'),
        isEmpty,
      );
    },
  );

  test('getVideos infers another page when total is omitted', () async {
    final network = JmNetwork(
      getRequest: (_) async => Res<dynamic>(<String, dynamic>{
        'list': <Map<String, dynamic>>[
          for (var index = 0; index < 20; index++)
            <String, dynamic>{'id': 'v$index', 'title': 'Video $index'},
        ],
      }),
    );

    final result = await network.getVideos();

    expect(result.error, isFalse);
    expect(result.data.items, hasLength(20));
    expect(result.data.total, 21);
  });

  test('getVideos rejects malformed successful responses', () async {
    final nonMap = JmNetwork(
      getRequest: (_) async => const Res<dynamic>(<dynamic>[]),
    );
    final missingList = JmNetwork(
      getRequest: (_) async =>
          const Res<dynamic>(<String, dynamic>{'total': 1}),
    );

    expect((await nonMap.getVideos()).error, isTrue);
    expect((await missingList.getVideos()).error, isTrue);
  });

  test('latest hanime rejects malformed items', () async {
    final network = JmNetwork(
      getRequest: (_) async => const Res<dynamic>(<String, dynamic>{
        'list': <dynamic>[null, 'not-an-item'],
      }),
    );

    final result = await network.getLatestHanime();

    expect(result.error, isTrue);
  });

  test('video detail rejects malformed related videos', () async {
    final network = JmNetwork(
      getRequest: (_) async => const Res<dynamic>(<String, dynamic>{
        'video': <String, dynamic>{'vid': 'v4', 'title': 'Detail'},
        'related_videos': <dynamic>[null],
      }),
    );

    final result = await network.getVideoDetail('v4');

    expect(result.error, isTrue);
  });
}
