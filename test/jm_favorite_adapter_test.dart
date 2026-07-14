import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/built_in/jm.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/database/favorites_helper.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/network/res.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('JM favorite adapter preserves a remote false result', () async {
    final result = await adaptJmFavoriteToggle(
      'comic-false',
      (comicId) async => const Res(false),
    );

    expect(result.error, isFalse);
    expect(result.data, isFalse);
  });

  test('JM remote favorite error does not update local state', () async {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    JoyDatabase.migrateCore(database);
    FavoriteNotifier.instance.loadFromDb(database);

    final previousSources = List<ComicSource>.of(ComicSource.sources);
    addTearDown(() {
      ComicSource.sources
        ..clear()
        ..addAll(previousSources);
    });
    final source = buildJmSource(
      favoriteToggle: (comicId) async => const Res.error('JM remote failed'),
    );
    ComicSource.sources
      ..clear()
      ..add(source);
    final helper = FavoritesHelper(database);
    final revision = FavoriteNotifier.instance.revision;

    await expectLater(
      helper.toggleFavorite(
        sourceKey: 'jm',
        comicId: 'comic-error',
        title: 'Should not persist',
        coverUrl: 'cover',
      ),
      throwsStateError,
    );

    expect(helper.get('jm', 'comic-error'), isNull);
    expect(FavoriteNotifier.instance.isFavorited('jm', 'comic-error'), isFalse);
    expect(FavoriteNotifier.instance.revision, revision);
  });
}
