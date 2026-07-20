import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/views/detail/detail_chapters_page.dart';
import 'package:joycomic/views/detail/detail_comments_page.dart';
import 'package:joycomic/views/detail/detail_view_model.dart';

void main() {
  test('mobile download actions live on the full chapters page only', () {
    final detail = File('lib/views/detail/detail_page.dart').readAsStringSync();
    final chapters = File(
      'lib/views/detail/detail_chapters_page.dart',
    ).readAsStringSync();
    expect(detail, isNot(contains('download_rounded')));
    expect(detail, isNot(contains('DownloadManager')));
    expect(chapters, contains('ChapterGrid('));
    expect(chapters, contains('showChapterDownloadSheet('));
  });

  test(
    'recent and full chapter surfaces route thumbnails through the descriptor API',
    () {
      final detail = File('lib/views/detail/detail_page.dart').readAsStringSync();
      final chapters = File(
        'lib/views/detail/detail_chapters_page.dart',
      ).readAsStringSync();
      final thumbnail = File(
        'lib/views/detail/widgets/chapter_thumbnail.dart',
      ).readAsStringSync();
      expect(detail, contains('loadChapterThumbnailDescriptor'));
      expect(chapters, contains('loadChapterThumbnailDescriptor'));
      expect(thumbnail, contains('readerImageProvider'));
      expect(thumbnail, isNot(contains('CachedNetworkImage')));
      expect(thumbnail, contains('bytesTransformer'));
    },
  );

  testWidgets('full chapters page exposes download and empty states', (
    tester,
  ) async {
    final source = ComicSource.named(
      name: 'Chapter page test',
      key: 'chapter-page-test',
      filePath: 'test',
      loadComicInfo: (_) async => const Res<ComicInfoData>(
        ComicInfoData(
          title: 'Comic',
          subTitle: 'Author',
          cover: '',
          description: 'Synopsis',
          tags: <String, List<String>>{},
          chapters: null,
          chapterList: <ComicChapter>[
            ComicChapter(id: '1', title: 'Chapter 1', order: 1),
            ComicChapter(id: '2', title: 'Chapter 2', order: 2),
          ],
          thumbnails: null,
          sourceKey: 'chapter-page-test',
          comicId: 'comic',
        ),
      ),
      loadComicPages: (_, __) async => const Res<List<String>>(<String>[]),
    );
    ComicSource.sources.add(source);
    addTearDown(() => ComicSource.sources.remove(source));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const DetailChaptersPage(
          sourceKey: 'chapter-page-test',
          comicId: 'comic',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('全部章节'), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsWidgets);
  });

  testWidgets('full comments page loads, paginates, and shows the composer', (
    tester,
  ) async {
    final source = ComicSource.named(
      name: 'Comment page test',
      key: 'comment-page-test',
      filePath: 'test',
      loadComicInfo: (_) async => const Res<ComicInfoData>(
        ComicInfoData(
          title: 'Comic',
          subTitle: 'Author',
          cover: '',
          description: null,
          tags: <String, List<String>>{},
          chapters: null,
          chapterList: <ComicChapter>[],
          thumbnails: null,
          sourceKey: 'comment-page-test',
          comicId: 'comic',
        ),
      ),
      commentsLoader: (_, __, page, ___) async => Res<CommentPageData>(
        CommentPageData(
          comments: <Comment>[
            Comment(
              page == 1 ? 'Alice' : 'Bob',
              null,
              page == 1 ? '第一页评论' : '第二页评论',
              null,
              0,
              'comment-$page',
            ),
          ],
          page: page,
          totalPages: 2,
          totalComments: 2,
        ),
      ),
      sendCommentFunc: (_, __, ___, ____) async => const Res<bool>(true),
    );
    ComicSource.sources.add(source);
    addTearDown(() => ComicSource.sources.remove(source));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const DetailCommentsPage(
          sourceKey: 'comment-page-test',
          comicId: 'comic',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('全部评论'), findsOneWidget);
    expect(find.text('第一页评论'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('加载更多评论'), findsOneWidget);

    await tester.tap(find.text('加载更多评论'));
    await tester.pumpAndSettle();
    expect(find.text('第二页评论'), findsOneWidget);
    expect(find.text('第一页评论'), findsOneWidget);
  });

  testWidgets(
    'comments retry after detail load error activates page one comments',
    (tester) async {
      var infoCalls = 0;
      var commentPages = <int>[];
      final source = ComicSource.named(
        name: 'Comment retry test',
        key: 'comment-retry-test',
        filePath: 'test',
        loadComicInfo: (_) async {
          infoCalls++;
          if (infoCalls == 1) {
            return const Res<ComicInfoData>(
              null,
              errorMessage: 'detail failed',
            );
          }
          return const Res<ComicInfoData>(
            ComicInfoData(
              title: 'Comic',
              subTitle: 'Author',
              cover: '',
              description: null,
              tags: <String, List<String>>{},
              chapters: null,
              chapterList: <ComicChapter>[],
              thumbnails: null,
              sourceKey: 'comment-retry-test',
              comicId: 'comic',
            ),
          );
        },
        commentsLoader: (_, __, page, ___) async {
          commentPages.add(page);
          return Res<CommentPageData>(
            CommentPageData(
              comments: const <Comment>[
                Comment('Alice', null, '重试后评论', null, 0, 'comment-1'),
              ],
              page: page,
              totalPages: 1,
              totalComments: 1,
            ),
          );
        },
      );
      ComicSource.sources.add(source);
      addTearDown(() => ComicSource.sources.remove(source));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const DetailCommentsPage(
            sourceKey: 'comment-retry-test',
            comicId: 'comic',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('detail failed'), findsOneWidget);
      expect(commentPages, isEmpty);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(infoCalls, 2);
      expect(commentPages, <int>[1]);
      expect(find.text('重试后评论'), findsOneWidget);
    },
  );

  test(
    'loadDetailAndActivateComments loads detail then requests comment page 1',
    () async {
      var infoCalls = 0;
      final pages = <int>[];
      final source = ComicSource.named(
        name: 'Helper activate',
        key: 'helper-activate',
        filePath: 'test',
        loadComicInfo: (_) async {
          infoCalls++;
          return const Res<ComicInfoData>(
            ComicInfoData(
              title: 'Comic',
              subTitle: null,
              cover: '',
              description: null,
              tags: <String, List<String>>{},
              chapters: null,
              chapterList: <ComicChapter>[],
              thumbnails: null,
              sourceKey: 'helper-activate',
              comicId: 'comic',
            ),
          );
        },
        commentsLoader: (_, __, page, ___) async {
          pages.add(page);
          return Res<CommentPageData>(
            CommentPageData(
              comments: const <Comment>[
                Comment('A', null, 'one', null, 0, '1'),
              ],
              page: page,
              totalPages: 1,
              totalComments: 1,
            ),
          );
        },
      );
      ComicSource.sources.add(source);
      addTearDown(() => ComicSource.sources.remove(source));

      final vm = DetailViewModel(sourceKey: source.key, comicId: 'comic');
      addTearDown(vm.dispose);

      await loadDetailAndActivateComments(vm);
      expect(infoCalls, 1);
      expect(pages, <int>[1]);
      expect(vm.comments, hasLength(1));
    },
  );

  test(
    'loadDetailAndActivateComments after error retry requests comment page 1',
    () async {
      var infoCalls = 0;
      final pages = <int>[];
      final source = ComicSource.named(
        name: 'Helper retry',
        key: 'helper-retry',
        filePath: 'test',
        loadComicInfo: (_) async {
          infoCalls++;
          if (infoCalls == 1) {
            return const Res<ComicInfoData>(null, errorMessage: 'boom');
          }
          return const Res<ComicInfoData>(
            ComicInfoData(
              title: 'Comic',
              subTitle: null,
              cover: '',
              description: null,
              tags: <String, List<String>>{},
              chapters: null,
              chapterList: <ComicChapter>[],
              thumbnails: null,
              sourceKey: 'helper-retry',
              comicId: 'comic',
            ),
          );
        },
        commentsLoader: (_, __, page, ___) async {
          pages.add(page);
          return Res<CommentPageData>(
            CommentPageData(
              comments: const <Comment>[
                Comment('A', null, 'after retry', null, 0, '1'),
              ],
              page: page,
              totalPages: 1,
              totalComments: 1,
            ),
          );
        },
      );
      ComicSource.sources.add(source);
      addTearDown(() => ComicSource.sources.remove(source));

      final vm = DetailViewModel(sourceKey: source.key, comicId: 'comic');
      addTearDown(vm.dispose);

      await loadDetailAndActivateComments(vm);
      expect(vm.state, DetailLoadState.error);
      expect(pages, isEmpty);

      await loadDetailAndActivateComments(vm);
      expect(infoCalls, 2);
      expect(pages, <int>[1]);
      expect(vm.comments.single.content, 'after retry');
    },
  );
}
