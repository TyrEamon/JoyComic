/// Horizontal recent-chapter strip for the detail page (max 6).
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../comic_source/detail_models.dart';
import '../../../theme/app_gradients.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import 'chapter_thumbnail.dart';

class RecentChapterStrip extends StatelessWidget {
  const RecentChapterStrip({
    super.key,
    required this.chapters,
    required this.loadThumbnail,
    required this.onSelect,
    required this.onShowAll,
    this.coverHeaders,
  });

  /// Keep only a little extra beyond the visible cards so off-screen
  /// thumbnails are not fetched immediately on a narrow phone.
  static const double listCacheExtent = 96;

  final List<ComicChapter> chapters;
  final Future<String?> Function(ComicChapter chapter) loadThumbnail;
  final ValueChanged<ComicChapter> onSelect;
  final VoidCallback onShowAll;
  final Map<String, dynamic>? coverHeaders;

  @override
  Widget build(BuildContext context) {
    final recent = chapters.reversed.take(6).toList(growable: false);
    final latest = chapters.isEmpty ? null : chapters.last.title;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('最近章节', style: AppTypography.section(context)),
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
              Semantics(
                button: true,
                label: '全部章节',
                child: TextButton(
                  onPressed: onShowAll,
                  child: const Text('全部章节'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                '暂无可阅读章节',
                style: TextStyle(color: context.tertiaryTextColor),
              ),
            )
          else
            SizedBox(
              key: const ValueKey('recent-chapter-strip'),
              height: 156,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                scrollCacheExtent: const ScrollCacheExtent.pixels(
                  listCacheExtent,
                ),
                itemCount: recent.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final chapter = recent[index];
                  return _RecentChapterCard(
                    chapter: chapter,
                    isLatest: chapter.id == chapters.last.id,
                    thumbnail: loadThumbnail(chapter),
                    coverHeaders: coverHeaders,
                    onTap: () => onSelect(chapter),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentChapterCard extends StatelessWidget {
  const _RecentChapterCard({
    required this.chapter,
    required this.isLatest,
    required this.thumbnail,
    required this.coverHeaders,
    required this.onTap,
  });

  final ComicChapter chapter;
  final bool isLatest;
  final Future<String?> thumbnail;
  final Map<String, dynamic>? coverHeaders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = chapter.title.trim().isEmpty
        ? '第${chapter.order}话'
        : chapter.title;
    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: context.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.brMd,
          side: BorderSide(color: context.borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 148,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ChapterThumbnail(
                        load: () => thumbnail,
                        headers: coverHeaders,
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 36,
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
                      if (isLatest)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.colorScheme.primaryContainer,
                              borderRadius: AppRadius.brSm,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              child: Text(
                                '最新',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: context.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 6,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardTitle(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
