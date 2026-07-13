/// 哔咔数据模型。
///
/// 与哔咔 API 响应对齐：用户档案、漫画列表项、漫画详情、评论等。
/// 列表项 [ComicItemBrief] 与详情 [ComicItem] 均实现 [BaseComic]，
/// 使 UI 与历史/收藏系统能以统一方式访问其标题、封面、作者等。
library picacg_models;

import '../base_comic.dart';
import 'package:flutter/foundation.dart';

/// 哔咔用户档案。
@immutable
class Profile {
  final String id;
  final String title;
  final String email;
  final String name;
  final int level;
  final int exp;
  final String avatarUrl;
  final String? frameUrl;
  final bool? isPunched;
  final String? slogan;

  const Profile({
    required this.id,
    required this.title,
    required this.email,
    required this.name,
    required this.level,
    required this.exp,
    required this.avatarUrl,
    this.frameUrl,
    this.isPunched,
    this.slogan,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        email: json['email'] ?? '',
        name: json['name'] ?? '',
        level: json['level'] ?? 0,
        exp: json['exp'] ?? 0,
        avatarUrl: json['avatarUrl'] ?? '',
        frameUrl: json['frameUrl'],
        isPunched: json['isPunched'],
        slogan: json['slogan'],
      );
}

/// 哔咔分类（首页分类标签）。
@immutable
class CategoryItem {
  final String title;
  final String path;
  const CategoryItem(this.title, this.path);
}

/// 哔咔漫画列表项（搜索/分类/收藏/排行榜共用）。
@immutable
class ComicItemBrief extends BaseComic {
  @override
  final String title;
  final String author;
  final int likes;
  final String coverPath;
  @override
  final String id;
  @override
  final List<String> tags;
  final int? pages;

  const ComicItemBrief({
    required this.title,
    required this.author,
    required this.likes,
    required this.coverPath,
    required this.id,
    this.tags = const [],
    this.pages,
  });

  factory ComicItemBrief.fromJson(Map<String, dynamic> json) => ComicItemBrief(
        title: json['title'] ?? '',
        author: (json['author'] as String?) ?? '',
        likes: json['totalLikes'] ?? json['likes'] ?? 0,
        coverPath: (json['thumb']?['fileServer'] ?? '') +
            '/static/' +
            (json['thumb']?['path'] ?? ''),
        id: json['_id'] ?? '',
        tags: List<String>.from(json['categories'] ?? []),
        pages: json['pages'],
      );

  @override
  String get cover => coverPath;

  @override
  String get subTitle => author;

  @override
  String get description => '$likes 人喜欢';

  @override
  bool get enableTagsTranslation => false; // 哔咔分类即标签，已是中文
}

/// 单段漫画分章信息（章节名 + epsId）。
@immutable
class PicacgEpisode {
  final String title;
  final int order;
  const PicacgEpisode({required this.title, required this.order});
}

/// 哔咔漫画详情。
class ComicItem extends BaseComic {
  final String id;
  @override
  final String title;
  final String author;
  final String _description;
  final String thumbUrl;
  final String chineseTeam;
  final List<String> categories;
  final List<String> tagList;
  final int likes;
  final int comments;
  final bool isLiked;
  final bool isFavourite;
  final int epsCount;
  final int pagesCount;
  final String time;
  final List<PicacgEpisode> episodes;
  final List<ComicItemBrief> recommendation;

  ComicItem({
    required this.id,
    required this.title,
    required this.author,
    required String description,
    required this.thumbUrl,
    required this.chineseTeam,
    required this.categories,
    required List<String> tags,
    required this.likes,
    required this.comments,
    required this.isLiked,
    required this.isFavourite,
    required this.epsCount,
    required this.pagesCount,
    required this.time,
    required this.episodes,
    required this.recommendation,
  })  : _description = description,
        tagList = tags;

  ComicItemBrief toBrief() => ComicItemBrief(
        title: title,
        author: author,
        likes: likes,
        coverPath: thumbUrl,
        id: id,
      );

  @override
  String get cover => thumbUrl;

  @override
  String get subTitle => author;

  @override
  String get description => _description;

  @override
  List<String> get tags => categories;

  @override
  bool get enableTagsTranslation => false;
}
