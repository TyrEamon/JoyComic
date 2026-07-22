import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/database/read_record_helper.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/views/reader/providers/reader_provider.dart';
import 'package:joycomic/views/reader/state/comic_state.dart';
import 'package:joycomic/views/reader/utils/reader_image_provider.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  ReadRecordHelper records() {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    JoyDatabase.migrateCore(database);
    return ReadRecordHelper(database);
  }

  ComicState state() => const ComicState(
    id: 'comic-1',
    title: 'Comic',
    coverUrl: '',
    author: 'Author',
    chapters: [
      ReaderChapter(id: 'ep-1', order: 1, name: 'Chapter 1'),
    ],
    chapter: ReaderChapter(id: 'ep-1', order: 1, name: 'Chapter 1'),
    pageNo: 0,
    sourceKey: 'jm',
    type: ReaderType.network,
  );

  test('chapter load emits a short trace id and final success state', () async {
    final provider = ReaderProvider(
      state: state(),
      readRecordHelper: records(),
      imageLoader: (comicId, ep) async => const Res<List<String>>(
        <String>['https://cdn.example/media/ep-1/00001.webp'],
      ),
      imageConfigResolver: (imageKey, comicId, epId) => <String, dynamic>{
        'url': imageKey,
        'cacheKey': 'jm|$comicId|$epId|00001',
        'headers': <String, String>{
          'Authorization': 'Bearer secret-token',
          'Cookie': 'session=abc',
        },
        'fallbackUrls': <String>['https://cdn2.example/media/ep-1/00001.webp'],
        'transform': <String, String>{
          'type': 'jm',
          'episodeId': epId,
          'imageName': '00001.webp',
        },
      },
    );
    addTearDown(provider.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(provider.loadingState, ReaderLoadState.success);
    expect(provider.traceId, isNotNull);
    expect(provider.traceId!.length, lessThanOrEqualTo(12));
    expect(provider.images, hasLength(1));
    expect(provider.images.single.bytesTransformer, isNotNull);
    expect(provider.images.single.cacheKey, 'jm|comic-1|ep-1|00001');
  });

  test('load error keeps a copyable trace id', () async {
    final provider = ReaderProvider(
      state: state(),
      readRecordHelper: records(),
      imageLoader: (comicId, ep) async =>
          const Res<List<String>>(null, errorMessage: 'network down'),
    );
    addTearDown(provider.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(provider.loadingState, ReaderLoadState.error);
    expect(provider.traceId, isNotNull);
    expect(provider.loadingErrorMessage, contains('network down'));
  });

  test(
    'vertical scroll actions preserve slider jump and pixel scrolling',
    () async {
      final provider = ReaderProvider(
        state: state(),
        readRecordHelper: records(),
        imageLoader: (comicId, ep) async => const Res<List<String>>(
          <String>[
            'https://cdn.example/1.webp',
            'https://cdn.example/2.webp',
            'https://cdn.example/3.webp',
          ],
        ),
      );
      addTearDown(provider.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final owner = Object();
      int? jumpedTo;
      double? scrolledBy;
      Duration? scrollDuration;
      provider.attachVerticalScrollActions(
        owner,
        VerticalReaderScrollActions(
          isAttached: () => true,
          jumpToIndex: (index) => jumpedTo = index,
          scrollBy: (offset, duration) {
            scrolledBy = offset;
            scrollDuration = duration;
          },
        ),
      );

      provider.onSliderChanged(1);
      expect(jumpedTo, 1);

      provider.pageTurnForVertical(25);
      expect(scrolledBy, 25);
      expect(scrollDuration, isNotNull);

      provider.detachVerticalScrollActions(owner);
      provider.onSliderChanged(2);
      expect(jumpedTo, 1);
    },
  );
  test('reader diagnostic helpers redact secrets and query strings', () {
    final redacted = ReaderDiagnostics.redactUrl(
      'https://cdn.example/path/img.webp?token=secret&sig=abc',
    );
    expect(redacted, contains('cdn.example'));
    expect(redacted, isNot(contains('token=secret')));
    expect(redacted, isNot(contains('sig=abc')));

    final summary = ReaderDiagnostics.headerSummary(
      <String, String>{
        'Authorization': 'Bearer secret',
        'Cookie': 'a=b',
        'Referer': 'https://jm.example/',
        'User-Agent': 'JoyComic',
      },
    );
    expect(summary, contains('Referer'));
    expect(summary, isNot(contains('Bearer secret')));
    expect(summary, isNot(contains('a=b')));
    expect(summary.toLowerCase(), isNot(contains('authorization')));
    expect(summary.toLowerCase(), isNot(contains('cookie')));
  });

  test(
    'provider load log detail never persists API/network secrets',
    () {
      const raw =
          'API failed https://host/path?token=secret Authorization: Bearer secret '
          'Cookie: session=xyz';
      final loggable = ReaderDiagnostics.formatProviderLoadFailure(
        traceId: 'tr12ab34',
        chapterId: 'ep-1',
        error: raw,
      );
      expect(loggable, contains('trace=tr12ab34'));
      expect(loggable, contains('chapter=ep-1'));
      expect(loggable, isNot(contains('token=secret')));
      expect(loggable, isNot(contains('Bearer secret')));
      expect(loggable, isNot(contains('session=xyz')));
      expect(loggable, isNot(contains('https://host/path?token=secret')));
      expect(loggable.toLowerCase(), isNot(contains('authorization')));

      final thrown = ReaderDiagnostics.formatProviderLoadFailure(
        traceId: 'tr99',
        chapterId: 'ep-2',
        error: Exception(
          'DioException uri=https://cdn.example/a.webp?token=secret '
          'headers={Authorization: Bearer secret, Cookie: a=b}',
        ),
      );
      expect(thrown, isNot(contains('token=secret')));
      expect(thrown, isNot(contains('Bearer secret')));
      expect(thrown, isNot(contains('Cookie: a=b')));
    },
  );

  test(
    'load error preserves useful display text while logging only sanitized detail',
    () async {
      const rawApi =
          'upstream 403 https://host/path?token=secret Authorization: Bearer secret Cookie: x=y';
      final provider = ReaderProvider(
        state: state(),
        readRecordHelper: records(),
        imageLoader: (comicId, ep) async =>
            const Res<List<String>>(null, errorMessage: rawApi),
      );
      addTearDown(provider.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(provider.loadingState, ReaderLoadState.error);
      // Display may keep the original useful message for the user.
      expect(provider.loadingErrorMessage, rawApi);
      // But the loggable form derived from the same error must be clean.
      final loggable = ReaderDiagnostics.formatProviderLoadFailure(
        traceId: provider.traceId,
        chapterId: 'ep-1',
        error: rawApi,
      );
      expect(loggable, isNot(contains('token=secret')));
      expect(loggable, isNot(contains('Bearer secret')));
      expect(loggable, isNot(contains('Cookie: x=y')));
    },
  );
}
