import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/database/favorites_helper.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/database/read_record_helper.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/views/detail/detail_view_model.dart';
import 'package:joycomic/views/reader/state/comic_state.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('load keeps comments lazy until activateComments is called', () async {
    var commentCalls = 0;
    final source = ComicSource.named(
      name: 'Lazy comments',
      key: 'lazy-comments',
      filePath: 'test',
      loadComicInfo: (_) async => Res<ComicInfoData>(_detailInfo()),
      commentsLoader: (_, __, page, ___) async {
        commentCalls++;
        return Res<CommentPageData>(
          CommentPageData(
            comments: const <Comment>[
              Comment('Alice', null, 'Hello', null, 0, 'comment-1'),
            ],
            page: page,
            totalPages: 4,
            totalComments: 37,
          ),
        );
      },
    );
    final viewModel = _mount(source);

    await viewModel.load();
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.state, DetailLoadState.success);
    expect(commentCalls, 0);
    expect(viewModel.commentsLoaded, isFalse);

    await viewModel.activateComments();
    await viewModel.activateComments();

    expect(commentCalls, 1);
    expect(viewModel.commentsLoaded, isTrue);
    expect(viewModel.commentTotal, 37);
    expect(viewModel.comments, hasLength(1));
    expect(viewModel.hasMoreComments, isTrue);
  });

  test(
    'typed chapters, authors, and calculated rating drive derived state',
    () async {
      final source = ComicSource.named(
        name: 'Typed detail',
        key: 'typed-detail',
        filePath: 'test',
        loadComicInfo: (_) async => Res<ComicInfoData>(
          _detailInfo(
            authors: const <String>['Author A', 'Author B'],
            views: 10000,
            likes: 1200,
          ),
        ),
      );
      final viewModel = _mount(source);

      await viewModel.load();

      expect(viewModel.author, 'Author A、Author B');
      expect(viewModel.chapters.map((chapter) => chapter.id), <String>[
        '1',
        '2',
      ]);
      expect(viewModel.rating, isNotNull);
      expect(viewModel.rating, inInclusiveRange(5.5, 9.8));
      expect(
        ReaderChapter.fromComicChapters(
          viewModel.chapters,
        ).map((chapter) => (chapter.id, chapter.name, chapter.order)),
        <(String, String, int)>[('1', '第一章', 1), ('2', '第二章', 2)],
      );
    },
  );

  test(
    'failed reply keeps the reply target and exposes the send error',
    () async {
      final source = ComicSource.named(
        name: 'Failed send',
        key: 'failed-send',
        filePath: 'test',
        loadComicInfo: (_) async => Res<ComicInfoData>(_detailInfo()),
        sendCommentFunc: (_, __, ___, ____) async =>
            const Res<bool>(null, errorMessage: 'send denied'),
      );
      final viewModel = _mount(source);
      await viewModel.load();
      const comment = Comment('Alice', null, 'Parent', null, 0, 'comment-1');

      viewModel.beginReply(comment);
      final result = await viewModel.sendComment(' reply text ');

      expect(result, isFalse);
      expect(viewModel.replyTarget?.id, 'comment-1');
      expect(viewModel.replyTarget?.userName, 'Alice');
      expect(viewModel.commentSendError, 'send denied');
      expect(viewModel.commentSending, isFalse);
    },
  );

  test(
    'successful reply clears reply state and reloads comment page one',
    () async {
      final requestedPages = <int>[];
      final sentTargets = <CommentReplyTarget?>[];
      final source = ComicSource.named(
        name: 'Successful send',
        key: 'successful-send',
        filePath: 'test',
        loadComicInfo: (_) async => Res<ComicInfoData>(_detailInfo()),
        commentsLoader: (_, __, page, ___) async {
          requestedPages.add(page);
          return Res<CommentPageData>(
            CommentPageData(
              comments: <Comment>[
                Comment('User', null, 'page $page', null, 0, 'comment-$page'),
              ],
              page: page,
              totalPages: 1,
              totalComments: 8,
            ),
          );
        },
        sendCommentFunc: (_, __, ___, replyTo) async {
          sentTargets.add(replyTo);
          return const Res<bool>(true);
        },
      );
      final viewModel = _mount(source);
      await viewModel.load();
      await viewModel.activateComments();
      const parent = Comment('Alice', null, 'Parent', null, 0, 'parent-1');
      viewModel.beginReply(parent);

      final result = await viewModel.sendComment('reply');

      expect(result, isTrue);
      expect(sentTargets.single?.id, 'parent-1');
      expect(requestedPages, <int>[1, 1]);
      expect(viewModel.replyTarget, isNull);
      expect(viewModel.commentSendError, isNull);
      expect(viewModel.commentTotal, 8);
      expect(viewModel.comments.single.id, 'comment-1');
    },
  );

  test(
    'chapter thumbnail loads are cached and limited to three concurrent calls',
    () async {
      var active = 0;
      var maxActive = 0;
      var pageCalls = 0;
      final chapters = <ComicChapter>[
        for (var index = 1; index <= 6; index++)
          ComicChapter(id: '$index', title: 'Chapter $index', order: index),
      ];
      final source = ComicSource.named(
        name: 'Thumbnail pool',
        key: 'thumbnail-pool',
        filePath: 'test',
        loadComicInfo: (_) async =>
            Res<ComicInfoData>(_detailInfo(chapters: chapters)),
        loadComicPages: (_, chapterId) async {
          active++;
          pageCalls++;
          if (active > maxActive) maxActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          active--;
          return Res<List<String>>(<String>['https://img/$chapterId/1.webp']);
        },
      );
      final viewModel = _mount(source);
      await viewModel.load();

      final first = await Future.wait([
        for (final chapter in viewModel.chapters)
          viewModel.loadChapterThumbnail(chapter),
      ]);
      final second = await Future.wait([
        for (final chapter in viewModel.chapters)
          viewModel.loadChapterThumbnail(chapter),
      ]);

      expect(first.whereType<String>(), hasLength(6));
      expect(second, first);
      expect(pageCalls, 6);
      expect(maxActive, lessThanOrEqualTo(3));
    },
  );

  test(
    'page requests are deduplicated and inline single chapter pages bypass the source',
    () async {
      var remoteCalls = 0;
      final gate = Completer<void>();
      final source = ComicSource.named(
        name: 'Page cache',
        key: 'page-cache',
        filePath: 'test',
        loadComicInfo: (_) async => Res<ComicInfoData>(
          _detailInfo(
            chapters: const <ComicChapter>[
              ComicChapter(id: 'single', title: '全本', order: 1),
            ],
            singlePages: const <String>['inline-1', 'inline-2'],
          ),
        ),
        loadComicPages: (_, __) async {
          remoteCalls++;
          await gate.future;
          return const Res<List<String>>(<String>['remote']);
        },
      );
      final viewModel = _mount(source);
      await viewModel.load();
      final chapter = viewModel.chapters.single;

      final first = viewModel.loadChapterPages(chapter);
      final second = viewModel.loadChapterPages(chapter);
      gate.complete();

      expect(identical(first, second), isTrue);
      expect((await first).data, <String>['inline-1', 'inline-2']);
      expect(remoteCalls, 0);
    },
  );

  test('read action label switches after a reading record is saved', () async {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    JoyDatabase.migrateCore(database);
    FavoriteNotifier.instance.loadFromDb(database);
    final source = ComicSource.named(
      name: 'Read progress',
      key: 'read-progress',
      filePath: 'test',
      loadComicInfo: (_) async => Res<ComicInfoData>(_detailInfo()),
    );
    ComicSource.sources.add(source);
    addTearDown(() => ComicSource.sources.remove(source));
    final records = ReadRecordHelper(database);
    final viewModel = DetailViewModel(
      sourceKey: source.key,
      comicId: 'comic-1',
      favoritesHelper: FavoritesHelper(database),
      readRecordHelper: records,
    );
    addTearDown(viewModel.dispose);

    await viewModel.load();
    expect(viewModel.readActionLabel, '开始阅读');
    expect(viewModel.hasReadProgress, isFalse);

    records.upsert(
      const ReadRecord(
        source: 'read-progress',
        comic: 'comic-1',
        title: 'Comic',
        chapterId: '2',
        chapterTitle: '第二章',
        pageNo: 3,
        updatedAt: 1,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.hasReadProgress, isTrue);
    expect(viewModel.readActionLabel, '继续阅读');
    expect(viewModel.readRecord?.chapterId, '2');
  });

  test('sources without commentsLoader report canLoadComments false', () async {
    final source = ComicSource.named(
      name: 'No comments',
      key: 'no-comments',
      filePath: 'test',
      loadComicInfo: (_) async => Res<ComicInfoData>(_detailInfo()),
    );
    final viewModel = _mount(source);
    await viewModel.load();
    expect(viewModel.canLoadComments, isFalse);
  });
}

DetailViewModel _mount(ComicSource source) {
  final database = sqlite3.openInMemory();
  addTearDown(database.dispose);
  JoyDatabase.migrateCore(database);
  FavoriteNotifier.instance.loadFromDb(database);
  ComicSource.sources.add(source);
  addTearDown(() => ComicSource.sources.remove(source));
  final viewModel = DetailViewModel(
    sourceKey: source.key,
    comicId: 'comic-1',
    favoritesHelper: FavoritesHelper(database),
    readRecordHelper: ReadRecordHelper(database),
  );
  addTearDown(viewModel.dispose);
  return viewModel;
}

ComicInfoData _detailInfo({
  List<String> authors = const <String>['Author'],
  int? views = 1200,
  int? likes = 120,
  List<ComicChapter>? chapters,
  List<String>? singlePages,
}) {
  final typedChapters =
      chapters ??
      const <ComicChapter>[
        ComicChapter(id: '1', title: '第一章', order: 1),
        ComicChapter(id: '2', title: '第二章', order: 2),
      ];
  return ComicInfoData.snapshot(
    title: 'Comic',
    subTitle: authors.isEmpty ? null : authors.first,
    cover: 'cover',
    description: 'Synopsis',
    tags: const <String, List<String>>{},
    chapters: <String, String>{
      for (final chapter in typedChapters) chapter.id: chapter.title,
    },
    thumbnails: null,
    sourceKey: 'test',
    comicId: 'comic-1',
    authors: authors,
    viewCount: views,
    likeCount: likes,
    commentCount: 37,
    chapterList: typedChapters,
    singleChapterPages: singlePages,
  );
}
