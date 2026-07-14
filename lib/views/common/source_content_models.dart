/// Source-neutral discovery models shared by built-in sources and discovery UI.
library source_content_models;

import 'package:flutter/foundation.dart';

import '../../network/base_comic.dart';
import '../../network/json_value.dart';
import '../../network/res.dart';

@immutable
class SourceSortOption {
  final String key;
  final String title;

  const SourceSortOption({required this.key, required this.title});
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

  const SourceCategory({
    required this.key,
    required this.title,
    this.parentKey,
    this.param,
    this.icon,
    this.cover,
    this.webOnly = false,
    this.sortOptions = const [],
  });

  /// Adapts common remote category shapes without assuming scalar types.
  factory SourceCategory.fromJson(
    Object? value, {
    Object? parentKey,
    Object? param,
    Object? icon,
    Object? cover,
    List<SourceSortOption> sortOptions = const [],
  }) {
    final json = jsonMap(value);
    return SourceCategory(
      key: _scalarString(
        json['key'] ?? json['_id'] ?? json['id'] ?? json['CID'] ?? json['slug'],
      ),
      title: _scalarString(json['title'] ?? json['name']),
      parentKey: _optionalScalarString(parentKey ?? json['parentKey']),
      param: _optionalScalarString(param ?? json['param']),
      icon: _optionalScalarString(icon ?? json['icon']),
      cover: _optionalScalarString(cover ?? json['cover'] ?? json['thumb']),
      webOnly: jsonBool(json['webOnly'] ?? json['isWeb']),
      sortOptions: sortOptions,
    );
  }
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
}

@immutable
class SourceContentPage {
  final SourceContentQuery query;
  final List<BaseComic> comics;
  final int? maxPage;

  const SourceContentPage({
    required this.query,
    required this.comics,
    this.maxPage,
  });

  bool get hasMore {
    final lastPage = maxPage;
    return lastPage == null || query.page < lastPage;
  }
}

@immutable
class SourceContentSection {
  final String key;
  final String title;
  final List<BaseComic> comics;
  final SourceContentQuery? moreQuery;

  const SourceContentSection({
    required this.key,
    required this.title,
    required this.comics,
    this.moreQuery,
  });
}

typedef LoadSourceCategories = Future<Res<List<SourceCategory>>> Function();
typedef LoadSourceContent = Future<Res<SourceContentPage>> Function(
  SourceContentQuery query,
);
typedef LoadHomeSections = Future<Res<List<SourceContentSection>>> Function();

String _scalarString(Object? value) {
  if (value is! String && value is! num && value is! bool) return '';
  return jsonString(value).trim();
}

String? _optionalScalarString(Object? value) {
  final text = _scalarString(value);
  return text.isEmpty ? null : text;
}
