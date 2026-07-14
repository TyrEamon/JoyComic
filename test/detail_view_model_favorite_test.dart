import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/database/favorites_helper.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/views/detail/detail_view_model.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    'detail favorite toggle notifies FavoriteNotifier exactly once',
    () async {
      final database = sqlite3.openInMemory();
      addTearDown(database.dispose);
      JoyDatabase.migrateCore(database);

      final notifier = FavoriteNotifier.instance;
      notifier.loadFromDb(database);
      final revision = notifier.revision;

      final helper = FavoritesHelper(database, (_, _, _) async {});
      final source = ComicSource.named(
        name: 'Test source',
        key: 'test-source',
        filePath: 'test',
        loadComicInfo: (_) async => const Res(
          ComicInfoData(
            title: 'Comic',
            subTitle: null,
            cover: '',
            description: null,
            tags: <String, List<String>>{},
            chapters: null,
            thumbnails: null,
            sourceKey: 'test-source',
            comicId: 'comic-1',
          ),
        ),
      );
      ComicSource.sources.add(source);
      addTearDown(() => ComicSource.sources.remove(source));
      final viewModel = DetailViewModel(
        sourceKey: 'test-source',
        comicId: 'comic-1',
        favoritesHelper: helper,
      );
      addTearDown(viewModel.dispose);
      await viewModel.load();

      var notifications = 0;
      void listener() => notifications++;
      notifier.addListener(listener);
      addTearDown(() => notifier.removeListener(listener));

      await viewModel.toggleFavorite();

      expect(viewModel.isFavorite, isTrue);
      expect(notifications, 1);
      expect(notifier.revision, revision + 1);
    },
  );
}
