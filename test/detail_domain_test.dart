import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/foundation/detail_rating.dart';
import 'package:joycomic/foundation/detail_text.dart';
import 'package:joycomic/network/base_comic.dart';
import 'package:joycomic/network/res.dart';

void main() {
  group('normalizeDetailText', () {
    test('normalizes HTML synopsis and entities', () {
      expect(
        normalizeDetailText('<p>A&amp;B</p><div>C<br>D</div>'),
        'A&B\nC\nD',
      );
    });

    test('handles uppercase structural tags', () {
      expect(
        normalizeDetailText('<P>A</P><DIV>B<BR class="x">C</DIV>'),
        'A\nB\nC',
      );
    });

    test('decodes required named and numeric entities', () {
      expect(
        normalizeDetailText(
          '&amp;&lt;&gt;&quot;&apos;&nbsp;&#38;&#60;&#62;&#34;&#39;&#160;'
          '&#x26;&#x3c;&#x3e;&#x22;&#x27;&#xa0;',
        ),
        '&<>"\' &<>"\' &<>"\'',
      );
    });

    test('normalizes line endings and collapses excessive blank lines', () {
      expect(normalizeDetailText('A  \r\nB\t \rC\n\n\n\nD  '), 'A\nB\nC\n\nD');
    });

    test('replaces invalid numeric entities with replacement characters', () {
      expect(
        normalizeDetailText('A&#0;B&#xD800;C&#x110000;D'),
        'A\uFFFDB\uFFFDC\uFFFDD',
      );
    });
  });

  test('rating is bounded, monotonic, and absent without metrics', () {
    final low = calculateDetailRating(views: 100000, likes: 1000)!;
    final high = calculateDetailRating(views: 100000, likes: 10000)!;

    expect(calculateDetailRating(views: null, likes: null), isNull);
    expect(calculateDetailRating(views: 0, likes: 0), isNull);
    expect(low, inInclusiveRange(5.5, 9.8));
    expect(high, inInclusiveRange(5.5, 9.8));
    expect(high, greaterThan(low));
  });

  test('source ratings are clamped and likes-only ratings are bounded', () {
    expect(calculateDetailRating(sourceRating: -1), 0);
    expect(calculateDetailRating(sourceRating: 11), 10);
    expect(calculateDetailRating(likes: 100), inInclusiveRange(5.5, 9.8));
  });

  test('comment totals and pages remain independent', () {
    final page = CommentPageData(
      comments: [],
      page: 1,
      totalPages: 3,
      totalComments: 27,
    );

    expect(page.totalPages, 3);
    expect(page.totalComments, 27);
    expect(page.hasMore, isTrue);
    expect(page, isNot(isA<Iterable<Comment>>()));
  });

  test('typed comment loader preserves page data and arguments', () async {
    final expected = CommentPageData(
      comments: const <Comment>[Comment('Mimi', null, 'Hello', null)],
      page: 2,
      totalPages: 4,
      totalComments: 37,
    );
    late List<Object?> arguments;
    final source = ComicSource.named(
      name: 'Typed comments',
      key: 'typed-comments',
      filePath: 'test',
      commentsLoader: (id, subId, page, replyToId) async {
        arguments = <Object?>[id, subId, page, replyToId];
        return Res<CommentPageData>(expected);
      },
    );

    final CommentsLoader loader = source.commentsLoader!;
    final result = await loader('comic-1', 'chapter-2', 2, 'parent-3');

    expect(arguments, <Object?>['comic-1', 'chapter-2', 2, 'parent-3']);
    expect(identical(result.data, expected), isTrue);
  });

  test('typed comment sender preserves arguments and reply target', () async {
    late List<Object?> arguments;
    final source = ComicSource.named(
      name: 'Typed sender',
      key: 'typed-sender',
      filePath: 'test',
      sendCommentFunc: (id, subId, content, replyTo) async {
        arguments = <Object?>[id, subId, content, replyTo];
        return const Res<bool>(true);
      },
    );
    const target = CommentReplyTarget(id: 'comment-1', userName: 'Mimi');

    final SendCommentFunc sender = source.sendCommentFunc!;
    final result = await sender('comic-1', 'chapter-2', 'Hello', target);

    expect(result.data, isTrue);
    expect(arguments.take(3).toList(), <Object?>[
      'comic-1',
      'chapter-2',
      'Hello',
    ]);
    expect(identical(arguments[3], target), isTrue);
  });

  test('comment snapshots defensively copy replies', () {
    final replies = <Comment>[const Comment('Reply', null, 'one', null)];
    final comment = Comment.snapshot(
      'Mimi',
      null,
      'Hello',
      null,
      1,
      'comment-1',
      0,
      false,
      replies,
    );

    replies.clear();

    expect(comment.replies, hasLength(1));
    expect(
      () => comment.replies.add(const Comment('Other', null, 'two', null)),
      throwsUnsupportedError,
    );
  });

  test('comment pages defensively copy comments', () {
    final comments = <Comment>[const Comment('Mimi', null, 'Hello', null)];
    final page = CommentPageData(
      comments: comments,
      page: 1,
      totalPages: 1,
      totalComments: 1,
    );

    comments.clear();

    expect(page.comments, hasLength(1));
    expect(() => page.comments.clear(), throwsUnsupportedError);
  });

  test('comic info deeply snapshots all collection fields', () {
    final tags = <String, List<String>>{
      'genre': <String>['action'],
    };
    final chapters = <String, String>{'1': 'One'};
    final thumbnails = <String>['thumb'];
    final suggestions = <BaseComic>[_TestComic('suggestion')];
    final authors = <String>['Author'];
    final categories = <String>['Category'];
    final labels = <String>['Label'];
    final chapterList = <ComicChapter>[
      const ComicChapter(id: '1', title: 'One', order: 1),
    ];
    final singleChapterPages = <String>['page'];
    final info = ComicInfoData.snapshot(
      title: 'Comic',
      subTitle: null,
      cover: '',
      description: null,
      tags: tags,
      chapters: chapters,
      thumbnails: thumbnails,
      suggestions: suggestions,
      sourceKey: 'test',
      comicId: 'comic-1',
      authors: authors,
      categories: categories,
      labels: labels,
      chapterList: chapterList,
      singleChapterPages: singleChapterPages,
    );

    tags['genre']!.add('changed');
    tags['new'] = <String>['new'];
    chapters['2'] = 'Two';
    thumbnails.add('changed');
    suggestions.add(_TestComic('changed'));
    authors.add('changed');
    categories.add('changed');
    labels.add('changed');
    chapterList.add(const ComicChapter(id: '2', title: 'Two', order: 2));
    singleChapterPages.add('changed');

    expect(info.tags, <String, List<String>>{
      'genre': <String>['action'],
    });
    expect(info.chapters, <String, String>{'1': 'One'});
    expect(info.thumbnails, <String>['thumb']);
    expect(info.suggestions, hasLength(1));
    expect(info.authors, <String>['Author']);
    expect(info.categories, <String>['Category']);
    expect(info.labels, <String>['Label']);
    expect(info.chapterList, hasLength(1));
    expect(info.singleChapterPages, <String>['page']);
    expect(() => info.tags['genre']!.add('blocked'), throwsUnsupportedError);
    expect(
      () => info.tags['new'] = <String>['blocked'],
      throwsUnsupportedError,
    );
    expect(() => info.chapters!['2'] = 'blocked', throwsUnsupportedError);
    expect(() => info.thumbnails!.add('blocked'), throwsUnsupportedError);
    expect(() => info.suggestions!.clear(), throwsUnsupportedError);
    expect(() => info.authors.add('blocked'), throwsUnsupportedError);
    expect(() => info.categories.add('blocked'), throwsUnsupportedError);
    expect(() => info.labels.add('blocked'), throwsUnsupportedError);
    expect(() => info.chapterList.clear(), throwsUnsupportedError);
    expect(() => info.singleChapterPages!.clear(), throwsUnsupportedError);
  });

  test('legacy unnamed constructors remain const-compatible', () {
    const reply = Comment('Reply', null, 'one', null);
    const comment = Comment(
      'Mimi',
      null,
      'Hello',
      null,
      null,
      'comment-1',
      0,
      false,
      <Comment>[reply],
    );
    const info = ComicInfoData(
      title: 'Comic',
      subTitle: null,
      cover: '',
      description: null,
      tags: <String, List<String>>{
        'genre': <String>['action'],
      },
      chapters: <String, String>{'1': 'One'},
      thumbnails: <String>['thumb'],
      suggestions: null,
      sourceKey: 'test',
      comicId: 'comic-1',
      authors: <String>['Author'],
      categories: <String>['Category'],
      labels: <String>['Label'],
      chapterList: <ComicChapter>[
        ComicChapter(id: '1', title: 'One', order: 1),
      ],
      singleChapterPages: <String>['page'],
    );

    expect(comment.replyCount, 0);
    expect(comment.replies.single, same(reply));
    expect(info.tags['genre'], <String>['action']);
    expect(info.chapterList.single.id, '1');
  });

  test('comment reply target retains its identity', () {
    const target = CommentReplyTarget(id: 'comment-1', userName: 'Mimi');

    expect(target.id, 'comment-1');
    expect(target.userName, 'Mimi');
  });

  test('comment normalizes a nullable legacy reply count to zero', () {
    const comment = Comment('Mimi', null, 'Hello', null, null, 'comment-1');

    expect(comment.replyCount, 0);
    expect(comment.id, 'comment-1');
  });

  test('detail contracts provide safe compatibility defaults', () {
    const chapter = ComicChapter(id: 'ep-1', title: 'Episode 1', order: 1);
    const comment = Comment('Mimi', null, 'Hello', null);
    const info = ComicInfoData(
      title: 'Comic',
      subTitle: null,
      cover: '',
      description: null,
      tags: {},
      chapters: null,
      thumbnails: null,
      sourceKey: 'test',
      comicId: 'comic-1',
    );

    expect(chapter.pageCount, isNull);
    expect(comment.replyCount, 0);
    expect(comment.likeCount, 0);
    expect(comment.isLiked, isFalse);
    expect(comment.replies, isEmpty);
    expect(info.authors, isEmpty);
    expect(info.categories, isEmpty);
    expect(info.labels, isEmpty);
    expect(info.chapterList, isEmpty);
    expect(info.singleChapterPages, isNull);
  });
}

class _TestComic extends BaseComic {
  _TestComic(this.id);

  @override
  final String id;
  @override
  String get title => id;
  @override
  String get subTitle => '';
  @override
  String get cover => '';
  @override
  List<String> get tags => const <String>[];
  @override
  String get description => '';
}
