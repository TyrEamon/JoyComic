import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/built_in/picacg.dart';
import 'package:joycomic/comic_source/detail_models.dart';
import 'package:joycomic/network/picacg/picacg_network.dart';
import 'package:joycomic/network/res.dart';

void main() {
  Map<String, dynamic> commentPage({
    int page = 1,
    int pages = 4,
    int total = 37,
    List<Map<String, dynamic>>? docs,
  }) => <String, dynamic>{
    'data': <String, dynamic>{
      'comments': <String, dynamic>{
        'page': page,
        'pages': pages,
        'total': total,
        'docs': docs ?? <Map<String, dynamic>>[],
      },
    },
  };

  test('comment parser preserves remote totals and nested reply metadata', () {
    final result = parsePicacgCommentPage(
      commentPage(
        page: 2,
        pages: 4,
        total: 37,
        docs: <Map<String, dynamic>>[
          <String, dynamic>{
            '_id': 'parent-1',
            'content': 'Parent',
            'created_at': '2026-07-15',
            'commentsCount': '5',
            'likesCount': '9',
            'isLiked': true,
            '_user': <String, dynamic>{'name': 'Parent user'},
            'childrens': <Map<String, dynamic>>[
              <String, dynamic>{
                '_id': 'child-1',
                'content': 'Child',
                'likesCount': 2,
                'isLiked': false,
                '_user': <String, dynamic>{'name': 'Child user'},
              },
            ],
          },
        ],
      ),
      requestedPage: 2,
    );

    expect(result.error, isFalse);
    expect(result.data.page, 2);
    expect(result.data.totalPages, 4);
    expect(result.data.totalComments, 37);
    expect(result.data.comments, hasLength(1));
    final parent = result.data.comments.single;
    expect(parent.id, 'parent-1');
    expect(parent.replyCount, 5);
    expect(parent.likeCount, 9);
    expect(parent.isLiked, isTrue);
    expect(parent.replies.single.id, 'child-1');
    expect(parent.replies.single.userName, 'Child user');
    expect(parent.replies.single.likeCount, 2);
    expect(() => result.data.comments.clear(), throwsUnsupportedError);
    expect(() => parent.replies.clear(), throwsUnsupportedError);
  });

  test(
    'comment list and children requests use separate typed endpoints',
    () async {
      final requestedUrls = <String>[];
      final network = PicacgNetwork(
        getRequest: (url) async {
          requestedUrls.add(url);
          return Res<Map<String, dynamic>>(
            commentPage(page: requestedUrls.length),
          );
        },
      );

      final topLevel = await network.getComments('comic-1', page: 1);
      final children = await network.getCommentChildren('comment-1', page: 2);

      expect(topLevel.error, isFalse);
      expect(children.error, isFalse);
      expect(requestedUrls, <String>[
        '$defaultPicacgApiUrl/comics/comic-1/comments?page=1',
        '$defaultPicacgApiUrl/comments/comment-1/childrens?page=2',
      ]);
    },
  );

  test(
    'sendComment and replyComment trim content and select the right endpoint',
    () async {
      final calls = <({String url, Map<String, String>? body})>[];
      final network = PicacgNetwork(
        postRequest: (url, body) async {
          calls.add((url: url, body: body));
          return const Res<Map<String, dynamic>>(<String, dynamic>{
            'data': <String, dynamic>{},
          });
        },
      );

      final topLevel = await network.sendComment('comic-1', '  top level  ');
      final reply = await network.replyComment('comment-1', '  reply  ');

      expect(topLevel.data, isTrue);
      expect(reply.data, isTrue);
      expect(calls.map((call) => call.url), <String>[
        '$defaultPicacgApiUrl/comics/comic-1/comments',
        '$defaultPicacgApiUrl/comments/comment-1',
      ]);
      expect(calls[0].body, <String, String>{'content': 'top level'});
      expect(calls[1].body, <String, String>{'content': 'reply'});
    },
  );

  test(
    'comment sending rejects blank input and propagates request failures',
    () async {
      var calls = 0;
      final network = PicacgNetwork(
        postRequest: (url, body) async {
          calls++;
          return const Res<Map<String, dynamic>>(null, errorMessage: 'denied');
        },
      );

      final blank = await network.sendComment('comic-1', '   ');
      expect(blank.error, isTrue);
      expect(calls, 0);

      final failed = await network.replyComment('comment-1', 'hello');
      expect(failed.error, isTrue);
      expect(failed.errorMessage, 'denied');
      expect(calls, 1);
    },
  );

  test('source comment loaders and sender use reply target ids', () async {
    final getUrls = <String>[];
    final postUrls = <String>[];
    final network = PicacgNetwork(
      getRequest: (url) async {
        getUrls.add(url);
        return Res<Map<String, dynamic>>(commentPage());
      },
      postRequest: (url, body) async {
        postUrls.add(url);
        return const Res<Map<String, dynamic>>(<String, dynamic>{});
      },
    );
    final source = buildPicacgSource(network: network);

    await source.commentsLoader!('comic-1', null, 1, null);
    await source.commentsLoader!('comic-1', null, 2, 'comment-1');
    await source.sendCommentFunc!('comic-1', null, 'top', null);
    await source.sendCommentFunc!(
      'comic-1',
      null,
      'reply',
      const CommentReplyTarget(id: 'comment-1', userName: 'Alice'),
    );

    expect(getUrls, <String>[
      '$defaultPicacgApiUrl/comics/comic-1/comments?page=1',
      '$defaultPicacgApiUrl/comments/comment-1/childrens?page=2',
    ]);
    expect(postUrls, <String>[
      '$defaultPicacgApiUrl/comics/comic-1/comments',
      '$defaultPicacgApiUrl/comments/comment-1',
    ]);
  });
}
