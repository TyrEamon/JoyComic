import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/base_comic.dart';
import 'package:joycomic/views/common/source_content_models.dart';

void main() {
  group('shouldRequestNextPage', () {
    test('accepts only a root forward scroll near the list end', () {
      expect(
        shouldRequestNextPage(
          depth: 0,
          scrollDelta: 24,
          pixels: 720,
          minScrollExtent: 0,
          maxScrollExtent: 1000,
          extentAfter: 280,
        ),
        isTrue,
      );
      expect(
        shouldRequestNextPage(
          depth: 1,
          scrollDelta: 24,
          pixels: 720,
          minScrollExtent: 0,
          maxScrollExtent: 1000,
          extentAfter: 280,
        ),
        isFalse,
      );
      expect(
        shouldRequestNextPage(
          depth: 0,
          scrollDelta: -24,
          pixels: 720,
          minScrollExtent: 0,
          maxScrollExtent: 1000,
          extentAfter: 280,
        ),
        isFalse,
      );
      expect(
        shouldRequestNextPage(
          depth: 0,
          scrollDelta: 0,
          pixels: 720,
          minScrollExtent: 0,
          maxScrollExtent: 1000,
          extentAfter: 280,
        ),
        isFalse,
      );
      expect(
        shouldRequestNextPage(
          depth: 0,
          scrollDelta: 24,
          pixels: 500,
          minScrollExtent: 0,
          maxScrollExtent: 1000,
          extentAfter: 500,
        ),
        isFalse,
      );
    });

    test('rejects top pull, overscroll, and non-scrollable short lists', () {
      expect(
        shouldRequestNextPage(
          depth: 0,
          scrollDelta: 10,
          pixels: 0,
          minScrollExtent: 0,
          maxScrollExtent: 1000,
          extentAfter: 1000,
        ),
        isFalse,
      );
      expect(
        shouldRequestNextPage(
          depth: 0,
          scrollDelta: 10,
          pixels: -10,
          minScrollExtent: 0,
          maxScrollExtent: 1000,
          extentAfter: 1010,
        ),
        isFalse,
      );
      expect(
        shouldRequestNextPage(
          depth: 0,
          scrollDelta: 10,
          pixels: 1010,
          minScrollExtent: 0,
          maxScrollExtent: 1000,
          extentAfter: 0,
        ),
        isFalse,
      );
      expect(
        shouldRequestNextPage(
          depth: 0,
          scrollDelta: 10,
          pixels: -10,
          minScrollExtent: 0,
          maxScrollExtent: 0,
          extentAfter: 10,
        ),
        isFalse,
      );
    });
  });

  group('RequestGenerationGate', () {
    test('a newer refresh invalidates an older refresh completion', () {
      final gate = RequestGenerationGate();
      final firstRefresh = gate.begin();
      final secondRefresh = gate.begin();

      expect(firstRefresh, 1);
      expect(secondRefresh, 2);
      expect(gate.accepts(firstRefresh), isFalse);
      expect(gate.accepts(secondRefresh), isTrue);
    });

    test('a refresh invalidates an in-flight single-source retry', () {
      final gate = RequestGenerationGate();
      gate.begin();
      final retryGeneration = gate.current;

      expect(gate.accepts(retryGeneration), isTrue);

      final refreshGeneration = gate.begin();
      expect(gate.accepts(retryGeneration), isFalse);
      expect(gate.accepts(refreshGeneration), isTrue);
    });
  });

  group('mergeSourceContentPage', () {
    test('stops without advancing when an appended page adds no new ids', () {
      final result = mergeSourceContentPage(
        existingComics: const [_TestComic('a'), _TestComic('b')],
        incomingComics: const [_TestComic('a'), _TestComic('b')],
        previousPage: 1,
        requestedPage: 2,
        maxPage: null,
        replace: false,
      );

      expect(result.comics.map((comic) => comic.id), ['a', 'b']);
      expect(result.addedCount, 0);
      expect(result.currentPage, 1);
      expect(result.reachedEnd, isTrue);
    });

    test('an early empty page always stops without advancing', () {
      final result = mergeSourceContentPage(
        existingComics: const [_TestComic('a')],
        incomingComics: const [],
        previousPage: 1,
        requestedPage: 2,
        maxPage: 99,
        replace: false,
      );

      expect(result.comics.map((comic) => comic.id), ['a']);
      expect(result.currentPage, 1);
      expect(result.reachedEnd, isTrue);
    });

    test('an empty replacement stops without advancing to page one', () {
      final result = mergeSourceContentPage(
        existingComics: const [_TestComic('stale')],
        incomingComics: const [],
        previousPage: 3,
        requestedPage: 1,
        maxPage: 99,
        replace: true,
      );

      expect(result.comics, isEmpty);
      expect(result.addedCount, 0);
      expect(result.currentPage, 0);
      expect(result.reachedEnd, isTrue);
    });

    test('merges new ids and stops when the known max page is reached', () {
      final result = mergeSourceContentPage(
        existingComics: const [_TestComic('a'), _TestComic('b')],
        incomingComics: const [_TestComic('b'), _TestComic('c')],
        previousPage: 1,
        requestedPage: 2,
        maxPage: 2,
        replace: false,
      );

      expect(result.comics.map((comic) => comic.id), ['a', 'b', 'c']);
      expect(result.addedCount, 1);
      expect(result.currentPage, 2);
      expect(result.reachedEnd, isTrue);
    });

    test('keeps an unknown limit open while a page adds new ids', () {
      final result = mergeSourceContentPage(
        existingComics: const [_TestComic('a')],
        incomingComics: const [_TestComic('b')],
        previousPage: 1,
        requestedPage: 2,
        maxPage: null,
        replace: false,
      );

      expect(result.comics.map((comic) => comic.id), ['a', 'b']);
      expect(result.addedCount, 1);
      expect(result.currentPage, 2);
      expect(result.reachedEnd, isFalse);
    });
  });
}

class _TestComic extends BaseComic {
  @override
  final String id;

  const _TestComic(this.id);

  @override
  String get title => id;

  @override
  String get subTitle => '';

  @override
  String get cover => '';

  @override
  List<String> get tags => const [];

  @override
  String get description => '';
}
