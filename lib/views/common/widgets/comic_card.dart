/// 通用漫画卡片组件，双形态复用：
/// - [ComicCard.poster]：竖版海报 3:4，列表页网格 + 详情页相关推荐横滑用
/// - [ComicCard.horizontal]：横向卡片（封面 + 标题 + 元数据），首页/探索横滑用
///
/// 文字统一用 [AppTypography]，卡片用 [AppColors.surface] 暖紫黑面 +
/// [AppShadows.card] 下沉暗影，整体深色基调一致。
library comic_card;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_shadows.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import 'comic_cover.dart';

class ComicCard extends StatelessWidget {
  const ComicCard.poster({
    super.key,
    required this.title,
    required this.coverUrl,
    this.subtitle,
    this.rating,
    this.width = _kPosterWidth,
    this.headers,
    this.onTap,
    this.sourceKey,
  })  : _layout = _Layout.poster,
        badge = null,
        tags = null;

  const ComicCard.horizontal({
    super.key,
    required this.title,
    required this.coverUrl,
    this.subtitle,
    this.tags,
    this.rating,
    this.width = _kHorzWidth,
    this.headers,
    this.onTap,
    this.sourceKey,
  })  : _layout = _Layout.horizontal,
        badge = null;

  /// 带角标的网格卡（章节卡 / 收藏卡等扩展用）。
  const ComicCard.grid({
    super.key,
    required this.title,
    required this.coverUrl,
    this.subtitle,
    this.rating,
    this.badge,
    this.width = _kPosterWidth,
    this.headers,
    this.onTap,
    this.sourceKey,
  })  : _layout = _Layout.grid,
        tags = null;

  final String title;
  final String? coverUrl;
  final String? subtitle;
  final List<String>? tags;
  final double? rating;
  final Widget? badge; // 右上角角标（NEW / 收藏星 等）
  final double width;
  final Map<String, dynamic>? headers;
  final VoidCallback? onTap;
  final String? sourceKey;
  final _Layout _layout;

  static const double _kPosterWidth = 132;
  static const double _kHorzWidth = 260;

  @override
  Widget build(BuildContext context) {
    switch (_layout) {
      case _Layout.poster:
        return _Poster(
          title: title,
          coverUrl: coverUrl,
          subtitle: subtitle,
          rating: rating,
          width: width,
          headers: headers,
          onTap: onTap,
          sourceKey: sourceKey,
        );
      case _Layout.horizontal:
        return _Horizontal(
          title: title,
          coverUrl: coverUrl,
          subtitle: subtitle,
          tags: tags,
          rating: rating,
          width: width,
          headers: headers,
          onTap: onTap,
          sourceKey: sourceKey,
        );
      case _Layout.grid:
        return _Grid(
          title: title,
          coverUrl: coverUrl,
          subtitle: subtitle,
          rating: rating,
          badge: badge,
          width: width,
          headers: headers,
          onTap: onTap,
          sourceKey: sourceKey,
        );
    }
  }
}

enum _Layout { poster, horizontal, grid }

// ============================ 竖版海报 ============================

class _Poster extends StatelessWidget {
  const _Poster({
    required this.title,
    required this.coverUrl,
    required this.subtitle,
    required this.rating,
    required this.width,
    required this.headers,
    required this.onTap,
    required this.sourceKey,
  });

  final String title;
  final String? coverUrl;
  final String? subtitle;
  final double? rating;
  final double width;
  final Map<String, dynamic>? headers;
  final VoidCallback? onTap;
  final String? sourceKey;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ComicCover(url: coverUrl, width: width, headers: headers),
                if (sourceKey != null)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _SourceBadge(sourceKey: sourceKey!),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.cardTitle(context),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.cardMeta(context),
              ),
            ] else if (rating != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.star_rounded, size: 13, color: AppColors.ratingStar),
                  const SizedBox(width: 2),
                  Text(
                    rating!.toStringAsFixed(1),
                    style: AppTypography.cardMeta(context).copyWith(
                      color: AppColors.ratingStar,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================ 横向卡 ============================

class _Horizontal extends StatelessWidget {
  const _Horizontal({
    required this.title,
    required this.coverUrl,
    required this.subtitle,
    required this.tags,
    required this.rating,
    required this.width,
    required this.headers,
    required this.onTap,
    required this.sourceKey,
  });

  final String title;
  final String? coverUrl;
  final String? subtitle;
  final List<String>? tags;
  final double? rating;
  final double width;
  final Map<String, dynamic>? headers;
  final VoidCallback? onTap;
  final String? sourceKey;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Stack(
              children: [
                ComicCover(
                  url: coverUrl,
                  width: 92,
                  aspectRatio: 3 / 4,
                  radius: 0,
                  elevation: false,
                  border: false,
                  headers: headers,
                ),
                if (sourceKey != null)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: _SourceBadge(sourceKey: sourceKey!),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.cardTitle(context),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardMeta(context),
                      ),
                    ],
                    if (tags?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: tags!.take(3).map(_miniTag).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniTag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.brandPink.withValues(alpha: 0.12),
          borderRadius: AppRadius.brSm,
        ),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.brandPink,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

// ============================ 网格卡（带角标） ============================

class _Grid extends StatelessWidget {
  const _Grid({
    required this.title,
    required this.coverUrl,
    required this.subtitle,
    required this.rating,
    required this.badge,
    required this.width,
    required this.headers,
    required this.onTap,
    required this.sourceKey,
  });

  final String title;
  final String? coverUrl;
  final String? subtitle;
  final double? rating;
  final Widget? badge;
  final double width;
  final Map<String, dynamic>? headers;
  final VoidCallback? onTap;
  final String? sourceKey;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ComicCover(url: coverUrl, width: width, headers: headers),
              if (sourceKey != null)
                Positioned(
                  left: 6,
                  top: 6,
                  child: _SourceBadge(sourceKey: sourceKey!),
                ),
              if (badge != null)
                Positioned(top: 8, right: 8, child: badge!),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.chapterName(context),
          ),
        ],
      ),
    );
  }
}

/// 源标识徽标（左上角小标签）。
class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.sourceKey});
  final String sourceKey;

  @override
  Widget build(BuildContext context) {
    final isJm = sourceKey == 'jm';
    final isPicacg = sourceKey == 'picacg';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: isJm
            ? const Color(0xFF6E56CF).withValues(alpha: 0.85)
            : const Color(0xFFFF7BA9).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isJm ? 'JM' : (isPicacg ? 'Pica' : sourceKey.toUpperCase()),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
