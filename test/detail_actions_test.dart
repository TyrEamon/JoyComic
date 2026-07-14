import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/database/favorites_helper.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/views/detail/detail_page.dart';
import 'package:joycomic/views/detail/detail_view_model.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'detail comments load subsequent pages until the remote total is reached',
    () async {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);
      final requestedPages = <int>[];
      final source = ComicSource.named(
        name: 'Test',
        key: 'comments',
        filePath: 'test',
        commentsLoader: (_, __, page, ___) async {
          requestedPages.add(page);
          return Res<List<Comment>>(
            page == 1
                ? const <Comment>[
                    Comment('A', null, 'one', null, 0, '1'),
                    Comment('B', null, 'two', null, 0, '2'),
                  ]
                : const <Comment>[Comment('C', null, 'three', null, 0, '3')],
            subData: 3,
          );
        },
      );
      ComicSource.sources.add(source);
      addTearDown(() => ComicSource.sources.remove(source));
      final viewModel = DetailViewModel(
        sourceKey: source.key,
        comicId: 'comic',
        favoritesHelper: FavoritesHelper(database),
      );
      addTearDown(viewModel.dispose);

      await viewModel.loadComments();
      expect(viewModel.comments.map((comment) => comment.id), <String?>[
        '1',
        '2',
      ]);
      expect(viewModel.hasMoreComments, isTrue);

      await viewModel.loadMoreComments();
      expect(requestedPages, <int>[1, 2]);
      expect(viewModel.comments.map((comment) => comment.id), <String?>[
        '1',
        '2',
        '3',
      ]);
      expect(viewModel.hasMoreComments, isFalse);
    },
  );

  test('recommendations rotate in deterministic local batches', () {
    const items = <int>[1, 2, 3, 4, 5];
    expect(rotateRecommendationItems(items, 0, batchSize: 3), <int>[1, 2, 3]);
    expect(rotateRecommendationItems(items, 3, batchSize: 3), <int>[4, 5, 1]);
  });
}
