/// Source-neutral discovery models shared by built-in sources and discovery UI.
library source_content_models;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../network/base_comic.dart';
import '../../network/res.dart';

const _deepCollectionEquality = DeepCollectionEquality();

@immutable
class SourceSortOption {
  final String key;
  final String title;

  const SourceSortOption({required this.key, required this.title});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceSortOption && key == other.key && title == other.title;

  @override
  int get hashCode => Object.hash(key, title);
}

@immutable
class SourceCategory {
  final String key;
  final String title;
  final String? parentKey;

  /// Source-specific category value sent to the remote endpoint.
  final String? param;
  final String? icon;
  final String? cover;
  final bool webOnly;
  final List<SourceSortOption> sortOptions;

  SourceCategory({
    required this.key,
    required this.title,
    this.parentKey,
    this.param,
    this.icon,
    this.cover,
    this.webOnly = false,
    List<SourceSortOption> sortOptions = const [],
  }) : sortOptions = List<SourceSortOption>.unmodifiable(sortOptions);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceCategory &&
          key == other.key &&
          title == other.title &&
          parentKey == other.parentKey &&
          param == other.param &&
          icon == other.icon &&
          cover == other.cover &&
          webOnly == other.webOnly &&
          _deepCollectionEquality.equals(sortOptions, other.sortOptions);

  @override
  int get hashCode => Object.hash(
        key,
        title,
        parentKey,
        param,
        icon,
        cover,
        webOnly,
        _deepCollectionEquality.hash(sortOptions),
      );
}

/// Removes entries that cannot be routed or displayed, web-only entries, and
/// duplicate keys. The first valid category for a key wins.
List<SourceCategory> normalizeCategories(Iterable<SourceCategory> categories) {
  final keys = <String>{};
  final visible = <SourceCategory>[];
  for (final category in categories) {
    final key = category.key.trim();
    if (key.isEmpty || category.title.trim().isEmpty || category.webOnly) {
      continue;
    }
    if (!keys.add(key)) continue;
    visible.add(category);
  }
  return visible;
}

@immutable
class SourceContentQuery {
  final String categoryKey;
  final String? param;
  final int page;
  final String? sort;

  const SourceContentQuery({
    required this.categoryKey,
    this.param,
    this.page = 1,
    this.sort,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceContentQuery &&
          categoryKey == other.categoryKey &&
          param == other.param &&
          page == other.page &&
          sort == other.sort;

  @override
  int get hashCode => Object.hash(categoryKey, param, page, sort);
}

@immutable
class SourceContentPage {
  final SourceContentQuery query;
  final List<BaseComic> comics;
  final int? maxPage;

  SourceContentPage({
    required this.query,
    required List<BaseComic> comics,
    this.maxPage,
  }) : comics = List<BaseComic>.unmodifiable(comics);

  bool get hasMore {
    final lastPage = maxPage;
    return lastPage == null || query.page < lastPage;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceContentPage &&
          query == other.query &&
          maxPage == other.maxPage &&
          _deepCollectionEquality.equals(comics, other.comics);

  @override
  int get hashCode => Object.hash(
        query,
        maxPage,
        _deepCollectionEquality.hash(comics),
      );
}

@immutable
class SourceContentSection {
  final String key;
  final String title;
  final List<BaseComic> comics;
  final SourceContentQuery? moreQuery;

  SourceContentSection({
    required this.key,
    required this.title,
    required List<BaseComic> comics,
    this.moreQuery,
  }) : comics = List<BaseComic>.unmodifiable(comics);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SourceContentSection &&
          key == other.key &&
          title == other.title &&
          moreQuery == other.moreQuery &&
          _deepCollectionEquality.equals(comics, other.comics);

  @override
  int get hashCode => Object.hash(
        key,
        title,
        moreQuery,
        _deepCollectionEquality.hash(comics),
      );
}

@immutable
class HomeSourceResult {
  final String sourceKey;
  final String sourceName;
  final Res<List<SourceContentSection>> result;

  const HomeSourceResult({
    required this.sourceKey,
    required this.sourceName,
    required this.result,
  });
}

@immutable
class HomeContentSection {
  final String sourceKey;
  final String sourceName;
  final String key;
  final String title;
  final List<BaseComic> comics;
  final SourceContentQuery? moreQuery;

  HomeContentSection({
    required this.sourceKey,
    required this.sourceName,
    required this.key,
    required this.title,
    required List<BaseComic> comics,
    this.moreQuery,
  }) : comics = List<BaseComic>.unmodifiable(comics);
}

@immutable
class HomeSourceError {
  final String sourceKey;
  final String sourceName;
  final String message;

  const HomeSourceError({
    required this.sourceKey,
    required this.sourceName,
    required this.message,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomeSourceError &&
          sourceKey == other.sourceKey &&
          sourceName == other.sourceName &&
          message == other.message;

  @override
  int get hashCode => Object.hash(sourceKey, sourceName, message);
}

@immutable
class HomeContent {
  final List<HomeContentSection> sections;
  final List<HomeSourceError> errors;

  HomeContent({
    required List<HomeContentSection> sections,
    required List<HomeSourceError> errors,
  })  : sections = List<HomeContentSection>.unmodifiable(sections),
        errors = List<HomeSourceError>.unmodifiable(errors);
}

class _HomeSectionAccumulator {
  _HomeSectionAccumulator({
    required this.sourceKey,
    required this.sourceName,
    required this.key,
    required this.title,
  });

  final String sourceKey;
  final String sourceName;
  final String key;
  final String title;
  final List<BaseComic> comics = <BaseComic>[];
  final Set<String> _comicIds = <String>{};
  SourceContentQuery? moreQuery;

  void merge(SourceContentSection section) {
    moreQuery ??= section.moreQuery;
    for (final comic in section.comics) {
      if (_comicIds.add(comic.id)) comics.add(comic);
    }
  }

  HomeContentSection? build() {
    if (comics.isEmpty) return null;
    return HomeContentSection(
      sourceKey: sourceKey,
      sourceName: sourceName,
      key: key,
      title: title,
      comics: comics,
      moreQuery: moreQuery,
    );
  }
}

/// Combines source home responses without allowing one failed source to hide
/// successful content from another source.
///
/// Source order and the first occurrence of each source-local section key are
/// retained. Duplicate sections merge comics by id in first-seen order, keep
/// the first title and first non-null more query, and are omitted only when all
/// occurrences are empty.
HomeContent mergeHomeSections(Iterable<HomeSourceResult> sourceResults) {
  final accumulators = <_HomeSectionAccumulator>[];
  final accumulatorsByKey = <String, _HomeSectionAccumulator>{};
  final errors = <HomeSourceError>[];

  for (final sourceResult in sourceResults) {
    final result = sourceResult.result;
    if (result.error) {
      errors.add(HomeSourceError(
        sourceKey: sourceResult.sourceKey,
        sourceName: sourceResult.sourceName,
        message: result.errorMessageWithoutNull,
      ));
      continue;
    }

    for (final section in result.data) {
      final identity = '${sourceResult.sourceKey}:${section.key}';
      final accumulator = accumulatorsByKey.putIfAbsent(identity, () {
        final value = _HomeSectionAccumulator(
          sourceKey: sourceResult.sourceKey,
          sourceName: sourceResult.sourceName,
          key: section.key,
          title: section.title,
        );
        accumulators.add(value);
        return value;
      });
      accumulator.merge(section);
    }
  }

  final sections = <HomeContentSection>[];
  for (final accumulator in accumulators) {
    final section = accumulator.build();
    if (section != null) sections.add(section);
  }
  return HomeContent(sections: sections, errors: errors);
}

/// Returns whether a root scroll update represents real movement toward the
/// list tail close enough to request another page.
///
/// [scrollDelta] is positive for the non-reversed vertical grids used by
/// ComicGrid. Top pulls, out-of-range metrics and non-scrollable short lists
/// are deliberately rejected.
bool shouldRequestNextPage({
  required int depth,
  required double scrollDelta,
  required double pixels,
  required double minScrollExtent,
  required double maxScrollExtent,
  required double extentAfter,
  double threshold = 320.0,
}) {
  if (depth != 0 || scrollDelta <= 0) return false;
  if (maxScrollExtent <= minScrollExtent) return false;
  if (pixels <= minScrollExtent || pixels > maxScrollExtent) return false;
  return extentAfter >= 0 && extentAfter < threshold;
}

/// Monotonic token gate for dropping stale asynchronous request completions.
class RequestGenerationGate {
  int _current = 0;

  int get current => _current;

  int begin() => ++_current;

  bool accepts(int generation) => generation == _current;
}

@immutable
class SourceContentMergeResult {
  final List<BaseComic> comics;
  final int currentPage;
  final int addedCount;
  final bool reachedEnd;

  SourceContentMergeResult({
    required List<BaseComic> comics,
    required this.currentPage,
    required this.addedCount,
    required this.reachedEnd,
  }) : comics = List<BaseComic>.unmodifiable(comics);
}

/// Merges one source-content response without advancing past an empty or
/// duplicate-only page. Unknown limits remain open only while new ids arrive.
SourceContentMergeResult mergeSourceContentPage({
  required List<BaseComic> existingComics,
  required List<BaseComic> incomingComics,
  required int previousPage,
  required int requestedPage,
  required int? maxPage,
  required bool replace,
}) {
  final ids = <String>{};
  final comics = <BaseComic>[];
  if (!replace) {
    for (final comic in existingComics) {
      if (ids.add(comic.id)) comics.add(comic);
    }
  }

  var addedCount = 0;
  for (final comic in incomingComics) {
    if (!ids.add(comic.id)) continue;
    comics.add(comic);
    addedCount++;
  }

  final madeNoProgress =
      incomingComics.isEmpty || (!replace && addedCount == 0);
  final currentPage = madeNoProgress
      ? (replace ? 0 : previousPage)
      : requestedPage;
  final reachedKnownEnd = maxPage != null && requestedPage >= maxPage;
  return SourceContentMergeResult(
    comics: comics,
    currentPage: currentPage,
    addedCount: addedCount,
    reachedEnd: madeNoProgress || reachedKnownEnd,
  );
}

typedef LoadSourceCategories = Future<Res<List<SourceCategory>>> Function();
typedef LoadSourceContent = Future<Res<SourceContentPage>> Function(
  SourceContentQuery query,
);
typedef LoadHomeSections = Future<Res<List<SourceContentSection>>> Function();
