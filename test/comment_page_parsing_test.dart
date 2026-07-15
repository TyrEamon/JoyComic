import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/jm/jm_network.dart';
import 'package:joycomic/network/picacg/picacg_network.dart';

void main() {
  group('parseJmCommentPage', () {
    test('preserves totals, pages, and typed replies', () {
      final result = parseJmCommentPage({
        'total': '21',
        'page_size': '20',
        'list': [
          {
            'CID': 'c1',
            'username': 'Alice',
            'content': '<p>Hello</p>',
            'addtime': 'now',
            'likes': '4',
            'isLiked': true,
            'replys': [
              {'CID': 'r1', 'username': 'Bob', 'content': 'Reply'},
            ],
          },
        ],
      }, page: 1);

      expect(result.error, isFalse);
      final page = result.data;
      expect(page.page, 1);
      expect(page.totalPages, 2);
      expect(page.totalComments, 21);
      expect(page.comments.single.id, 'c1');
      expect(page.comments.single.replyCount, 1);
      expect(page.comments.single.likeCount, 4);
      expect(page.comments.single.isLiked, isTrue);
      expect(page.comments.single.replies.single.id, 'r1');
      expect(page.comments.single.content, 'Hello');
    });

    test('rejects malformed and missing required metadata', () {
      final payloads = <Object?>[
        null,
        const <Object?>[],
        const <String, Object?>{'total': 0},
        const <String, Object?>{'list': <Object?>[]},
        const <String, Object?>{'list': 'bad', 'total': 0},
        const <String, Object?>{
          'list': <Object?>[1],
          'total': 1,
        },
        const <String, Object?>{'list': <Object?>[], 'total': 'bad'},
        const <String, Object?>{'list': <Object?>[], 'total': -1},
        const <String, Object?>{
          'list': <Object?>[],
          'total': 0,
          'pages': 'bad',
        },
        const <String, Object?>{
          'list': <Object?>[],
          'total': 0,
          'page_size': 0,
        },
      ];

      for (final payload in payloads) {
        final result = parseJmCommentPage(payload, page: 1);
        expect(result.error, isTrue, reason: '$payload');
        expect(result.errorMessage, '评论解析失败', reason: '$payload');
      }
    });

    test('allows absent or null nested replies', () {
      final absent = parseJmCommentPage({
        'list': <Object?>[
          <String, Object?>{'CID': 'c1'},
        ],
        'total': 1,
      }, page: 1);
      final nullReplies = parseJmCommentPage({
        'list': <Object?>[
          <String, Object?>{'CID': 'c1', 'replys': null},
        ],
        'total': 1,
      }, page: 1);

      expect(absent.error, isFalse);
      expect(nullReplies.error, isFalse);
      expect(nullReplies.data.comments.single.replies, isEmpty);
    });

    test('rejects malformed nested replies', () {
      final values = <Object?>[
        'bad',
        <Object?>[1],
      ];

      for (final key in const <String>['replys', 'replies']) {
        for (final replies in values) {
          final result = parseJmCommentPage({
            'list': <Object?>[
              <String, Object?>{'CID': 'c1', key: replies},
            ],
            'total': 1,
          }, page: 1);
          expect(result.error, isTrue, reason: '$key: $replies');
          expect(result.errorMessage, '评论解析失败', reason: '$key: $replies');
        }
      }
    });

    test('rejects a current page beyond reported total pages', () {
      final result = parseJmCommentPage({
        'list': <Object?>[],
        'total': 20,
        'page': 2,
        'pages': 1,
      }, page: 2);

      expect(result.error, isTrue);
      expect(result.errorMessage, '评论解析失败');
    });
  });

  group('parsePicacgCommentPage', () {
    test('keeps total pages separate from total comments', () {
      final result = parsePicacgCommentPage({
        'data': {
          'comments': {
            'page': 2,
            'pages': 4,
            'total': 37,
            'docs': [
              {
                '_id': 'c1',
                '_user': {'name': 'Alice'},
                'content': 'Hello',
                'commentsCount': 3,
                'likesCount': 7,
                'isLiked': true,
              },
            ],
          },
        },
      }, requestedPage: 2);

      expect(result.error, isFalse);
      final page = result.data;
      expect(page.page, 2);
      expect(page.totalPages, 4);
      expect(page.totalComments, 37);
      expect(page.comments.single.id, 'c1');
      expect(page.comments.single.replyCount, 3);
      expect(page.comments.single.likeCount, 7);
      expect(page.comments.single.isLiked, isTrue);
    });

    test('rejects malformed and missing required metadata', () {
      final payloads = <Object?>[
        null,
        const <Object?>[],
        const <String, Object?>{},
        const <String, Object?>{'data': <Object?>[]},
        const <String, Object?>{'data': <String, Object?>{}},
        const <String, Object?>{
          'data': {'comments': <Object?>[]},
        },
        const <String, Object?>{
          'data': {
            'comments': {'docs': 'bad', 'total': 0, 'pages': 1},
          },
        },
        const <String, Object?>{
          'data': {
            'comments': {
              'docs': <Object?>[1],
              'total': 1,
              'pages': 1,
            },
          },
        },
        const <String, Object?>{
          'data': {
            'comments': {'docs': <Object?>[], 'pages': 1},
          },
        },
        const <String, Object?>{
          'data': {
            'comments': {'docs': <Object?>[], 'total': 0},
          },
        },
        const <String, Object?>{
          'data': {
            'comments': {'docs': <Object?>[], 'total': -1, 'pages': 1},
          },
        },
        const <String, Object?>{
          'data': {
            'comments': {'docs': <Object?>[], 'total': 0, 'pages': 0},
          },
        },
      ];

      for (final payload in payloads) {
        final result = parsePicacgCommentPage(payload, requestedPage: 1);
        expect(result.error, isTrue, reason: '$payload');
        expect(result.errorMessage, '评论解析失败', reason: '$payload');
      }
    });

    test('allows absent or null nested replies', () {
      final absent = parsePicacgCommentPage({
        'data': {
          'comments': {
            'docs': <Object?>[
              <String, Object?>{'_id': 'c1'},
            ],
            'total': 1,
            'pages': 1,
          },
        },
      }, requestedPage: 1);
      final nullReplies = parsePicacgCommentPage({
        'data': {
          'comments': {
            'docs': <Object?>[
              <String, Object?>{'_id': 'c1', 'childrens': null},
            ],
            'total': 1,
            'pages': 1,
          },
        },
      }, requestedPage: 1);

      expect(absent.error, isFalse);
      expect(nullReplies.error, isFalse);
      expect(nullReplies.data.comments.single.replies, isEmpty);
    });

    test('rejects malformed nested replies', () {
      final values = <Object?>[
        'bad',
        <Object?>[1],
      ];

      for (final key in const <String>['childrens', 'replies']) {
        for (final replies in values) {
          final result = parsePicacgCommentPage({
            'data': {
              'comments': {
                'docs': <Object?>[
                  <String, Object?>{'_id': 'c1', key: replies},
                ],
                'total': 1,
                'pages': 1,
              },
            },
          }, requestedPage: 1);
          expect(result.error, isTrue, reason: '$key: $replies');
          expect(result.errorMessage, '评论解析失败', reason: '$key: $replies');
        }
      }
    });

    test('rejects a current page beyond reported total pages', () {
      final result = parsePicacgCommentPage({
        'data': {
          'comments': {'docs': <Object?>[], 'total': 1, 'pages': 1, 'page': 2},
        },
      }, requestedPage: 2);

      expect(result.error, isTrue);
      expect(result.errorMessage, '评论解析失败');
    });
  });
}
