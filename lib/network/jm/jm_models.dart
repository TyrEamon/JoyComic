/// 禁漫数据模型。
///
/// 与禁漫 API 响应对齐：单曲列表项、单曲详情（含剧集/分章映射）、分类等。
/// 列表项 [JmComicBrief] 与详情 [JmComicInfo] 均实现 [BaseComic]。
library jm_models;

import '../base_comic.dart';
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

  JmComicInfo? toDetailStub() => null;
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

  const JmChapter({
    required this.order,
    required this.chapterId,
    required this.title,
  });
}

/// 禁漫单曲详情。
class JmComicInfo extends BaseComic {
  @override
  final String name;
  final String id;
  final List<String> author;
  final String _description;
  final int likes;
  final int views;
  final int comments;

  /// 章节映射：章节序号 → 章节id。
  final Map<int, String> series;

  /// 章节标题列表（与 series 按 order 对齐）。
  final List<String> epNames;
  final List<String> tags;
  final List<String> works;
  final List<String> actors;
  final List<JmComicBrief> relatedComics;
  final bool liked;
  final bool favorite;

  JmComicInfo({
    required this.name,
    required this.id,
    required this.author,
    required String description,
    required this.likes,
    required this.views,
    required this.series,
    required this.tags,
    required this.works,
    required this.actors,
    required this.relatedComics,
    required this.liked,
    required this.favorite,
    required this.comments,
    required this.epNames,
  }) : _description = description;

  /// 由 series 映射构造可遍历的章节列表。
  List<JmChapter> get chapters {
    final entries = series.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final e in entries)
        JmChapter(
          order: e.key,
          chapterId: e.value,
          title: (e.key <= epNames.length && e.key >= 1)
              ? epNames[e.key - 1]
              : '第${e.key}话',
        ),
    ];
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

  @override
  List<String> get tags => tags;
}

/// 禁漫分类（一级分类 + 子分类）。
@immutable
class JmCategory {
  final String name;
  final String slug;
  final List<JmSubCategory> subCategories;

  JmCategory(this.name, this.slug, this.subCategories);
  // 注意：slug 为空时外层调用方应自行转 '0'，此处不移除 final 以保持不可变性
}

@immutable
class JmSubCategory {
  final String cid;
  final String name;
  final String slug;
  const JmSubCategory(this.cid, this.name, this.slug);
}
