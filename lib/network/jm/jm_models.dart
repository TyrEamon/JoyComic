/// 禁漫数据模型。
///
/// 与禁漫 API 响应对齐：单曲列表项、单曲详情（含剧集/分章映射）、分类等。
/// 列表项 [JmComicBrief] 与详情 [JmComicInfo] 均实现 [BaseComic]。
library;

import '../base_comic.dart';
import '../json_value.dart';
import 'package:flutter/foundation.dart';

import 'jm_image.dart';

/// 禁漫单曲列表项。
@immutable
class JmComicBrief extends BaseComic {
  @override
  final String id;
  final String author;
  final String name;
  final String rawDescription;
  final List<ComicCategoryInfo> categories;

  const JmComicBrief({
    required this.id,
    required this.author,
    required this.name,
    required this.rawDescription,
    this.categories = const [],
  });

  factory JmComicBrief.fromJson(Map<String, dynamic> json) {
    final categories = <ComicCategoryInfo>[];
    for (final key in const ['category', 'category_sub']) {
      final category = jsonMap(json[key]);
      final id = jsonString(category['id']);
      final name = jsonString(category['title'] ?? category['name']);
      if (id.isNotEmpty && name.isNotEmpty) {
        categories.add(ComicCategoryInfo(id, name));
      }
    }
    return JmComicBrief(
      id: jsonString(json['id'] ?? json['_id']),
      author: jsonString(json['author']),
      name: jsonString(json['name'] ?? json['title']),
      rawDescription: jsonString(json['description']),
      categories: categories,
    );
  }

  @override
  String get title => name;

  @override
  String get cover => getJmCoverUrl(id);

  @override
  String get subTitle => author;

  @override
  String get description => rawDescription;

  @override
  List<String> get tags => categories.map((e) => e.name).toList();
}

/// 禁漫分类信息。
@immutable
class ComicCategoryInfo {
  final String id;
  final String name;
  const ComicCategoryInfo(this.id, this.name);
}

/// 禁漫章节/分章信息：章节序号 → 章节id 映射（由详情接口提供）。
@immutable
class JmChapter {
  /// 业务侧章节序号（从 1 开始）。
  final int order;

  /// 禁漫章节 id（用于拉取内文图）。
  final String chapterId;

  /// 章节标题。
  final String title;

  /// 远端提供的章节页数；缺失时为 null。
  final int? pageCount;

  const JmChapter({
    required this.order,
    required this.chapterId,
    required this.title,
    this.pageCount,
  });
}

/// 禁漫单曲详情。
class JmComicInfo extends BaseComic {
  final String name;
  @override
  final String id;
  final List<String> author;
  final String _description;
  final int likes;
  final int views;
  final int comments;

  /// 专辑系列标识；单行本通常为 0 或缺失。
  final int? seriesId;

  /// 详情响应内联的原始图片 key 或绝对 URL。
  final List<String> images;

  /// 一级、二级分类名称，与 [tags] 标签分开保存。
  final List<String> categories;

  /// 章节映射：章节序号 → 章节id。
  final Map<int, String> series;

  /// 章节标题列表（按远端 order 排序，与 [series] 的有序 entries 对齐）。
  final List<String> epNames;
  @override
  final List<String> tags;
  final List<String> works;
  final List<String> actors;
  final List<JmComicBrief> relatedComics;
  final bool liked;
  final bool favorite;
  final List<JmChapter> _chapters;

  JmComicInfo({
    required this.name,
    required this.id,
    required List<String> author,
    required String description,
    required this.likes,
    required this.views,
    required Map<int, String> series,
    required List<String> tags,
    required List<String> works,
    required List<String> actors,
    required List<JmComicBrief> relatedComics,
    required this.liked,
    required this.favorite,
    required this.comments,
    required List<String> epNames,
    this.seriesId,
    List<String> images = const <String>[],
    List<String> categories = const <String>[],
    List<JmChapter> chapters = const <JmChapter>[],
  }) : author = List<String>.unmodifiable(author),
       _description = description,
       series = Map<int, String>.unmodifiable(Map<int, String>.of(series)),
       epNames = List<String>.unmodifiable(epNames),
       tags = List<String>.unmodifiable(tags),
       works = List<String>.unmodifiable(works),
       actors = List<String>.unmodifiable(actors),
       relatedComics = List<JmComicBrief>.unmodifiable(relatedComics),
       images = List<String>.unmodifiable(images),
       categories = List<String>.unmodifiable(categories),
       _chapters = List<JmChapter>.unmodifiable(chapters);

  /// 可遍历的章节列表，优先使用解析器保留的远端顺序和页数。
  List<JmChapter> get chapters {
    if (_chapters.isNotEmpty || series.isEmpty) return _chapters;
    final entries = series.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return List<JmChapter>.unmodifiable([
      for (var index = 0; index < entries.length; index++)
        JmChapter(
          order: entries[index].key,
          chapterId: entries[index].value,
          title: index < epNames.length
              ? epNames[index]
              : '第${entries[index].key}话',
        ),
    ]);
  }

  JmComicBrief toBrief() => JmComicBrief(
    id: id,
    author: author.isNotEmpty ? author.first : '',
    name: name,
    rawDescription: _description,
    categories: const [],
  );

  @override
  String get title => name;

  @override
  String get cover => getJmCoverUrl(id);

  @override
  String get subTitle => author.isNotEmpty ? author.first : '';

  @override
  String get description => _description;
}

/// 禁漫分类（一级分类 + 子分类）。
@immutable
class JmCategory {
  final String name;
  final String slug;
  final List<JmSubCategory> subCategories;

  const JmCategory(this.name, this.slug, this.subCategories);
  // slug 为空表示服务端未提供可路由标识，由源适配层丢弃整组分类。
}

@immutable
class JmSubCategory {
  final String cid;
  final String name;
  final String slug;
  const JmSubCategory(this.cid, this.name, this.slug);
}
