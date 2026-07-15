/// 章节目录组件（Chapter Section）。
///
/// - 头部栏：左"章节"标题，右"更新至XX话 >"整行动态跳转入口
/// - 内容网格：2 列 Grid 卡片，16:9 章节封面 + 最新章节 NEW 角标 + 单行名
///
/// 章节列表由外部传入 [chapters]（id->name 的有序映射），[onSelect]
/// 回调打开阅读器，选中与 NEW 状态由当前主题强调。
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_gradients.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';

class ChapterGrid extends StatelessWidget {
  const ChapterGrid({
    super.key,
    required this.chapters,
    required this.latestChapterName,
    required this.onSelect,
    this.onShowAll,
    this.coverHeaders,
  });

  /// 章节列表（按显示顺序）。
  final List<ChapterEntry> chapters;

  /// "更新至 XX" 显示文本。
  final String? latestChapterName;

  final void Function(ChapterEntry entry) onSelect;
  final VoidCallback? onShowAll;

  final Map<String, dynamic>? coverHeaders;

  @override
  Widget build(BuildContext context) {
    final accent = context.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            latest: latestChapterName,
            onShowAll: onShowAll,
            accent: accent,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (chapters.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Text(
                  '暂无章节',
                  style: TextStyle(color: context.tertiaryTextColor),
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: chapters.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm,
                childAspectRatio: 16 / 11,
              ),
              itemBuilder: (context, i) => _ChapterCard(
                entry: chapters[i],
                isNew: i == chapters.length - 1, // 末项视作最新
                accent: accent,
                coverHeaders: coverHeaders,
                onTap: () => onSelect(chapters[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class ChapterEntry {
  const ChapterEntry({required this.id, required this.name, this.cover});
  final String id;
  final String name;
  final String? cover;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.latest,
    required this.onShowAll,
    required this.accent,
  });
  final String? latest;
  final VoidCallback? onShowAll;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('章节', style: AppTypography.section(context)),
        const SizedBox(width: AppSpacing.xs),
        if (latest != null)
          Expanded(
            child: Text(
              '更新至 $latest',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.subtitle(context),
            ),
          )
        else
          const Spacer(),
        if (onShowAll != null)
          InkWell(
            onTap: onShowAll,
            borderRadius: AppRadius.brSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '全部',
                    style: AppTypography.sectionAction(
                      context,
                    ).copyWith(color: accent),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: accent),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.entry,
    required this.isNew,
    required this.accent,
    required this.coverHeaders,
    required this.onTap,
  });

  final ChapterEntry entry;
  final bool isNew;
  final Color accent;
  final Map<String, dynamic>? coverHeaders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: context.borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: entry.cover != null
                  ? CachedNetworkImage(
                      imageUrl: entry.cover!,
                      httpHeaders: coverHeaders?.cast<String, String>(),
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _ChapterPlaceholder(),
                      errorBuilder: (_, __, ___) => _ChapterPlaceholder(),
                    )
                  : _ChapterPlaceholder(),
            ),
            // 16:9 封面之上的底部渐变，确保章节名可读。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 42,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppGradients.imageScrimBottom(
                      context.semanticColors,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 7,
              child: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.onImageColor,
                ),
              ),
            ),
            if (isNew) const Positioned(top: 8, right: 8, child: _NewBadge()),
          ],
        ),
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: context.borderColor),
      ),
      child: Text(
        'NEW',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: context.colorScheme.onPrimaryContainer,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _ChapterPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.elevatedSurfaceColor,
    child: Center(
      child: Icon(
        Icons.book_rounded,
        size: 22,
        color: context.disabledTextColor,
      ),
    ),
  );
}
