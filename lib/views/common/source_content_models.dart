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

typedef LoadSourceCategories = Future<Res<List<SourceCategory>>> Function();
typedef LoadSourceContent = Future<Res<SourceContentPage>> Function(
  SourceContentQuery query,
);
typedef LoadHomeSections = Future<Res<List<SourceContentSection>>> Function();
