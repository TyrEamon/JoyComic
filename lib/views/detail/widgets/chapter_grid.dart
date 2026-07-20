/// Typed chapter grid with lazy first-page thumbnails.
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../comic_source/detail_models.dart';
import '../../../theme/app_gradients.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import 'chapter_thumbnail.dart';

class ChapterGrid extends StatelessWidget {
  const ChapterGrid({
    super.key,
    required this.chapters,
    required this.onSelect,
    required this.loadThumbnail,
    required this.onDownload,
    this.onDownloadAll,
    this.coverHeaders,
  });

  final List<ComicChapter> chapters;
  final ValueChanged<ComicChapter> onSelect;
  final Future<String?> Function(ComicChapter chapter) loadThumbnail;
  final ValueChanged<ComicChapter> onDownload;
  final VoidCallback? onDownloadAll;
  final Map<String, dynamic>? coverHeaders;

  @override
  Widget build(BuildContext context) {
    final latest = chapters.isEmpty ? null : chapters.last.title;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('章节列表', style: AppTypography.section(context)),
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
              if (onDownloadAll != null)
                TextButton.icon(
                  onPressed: onDownloadAll,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('下载'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (chapters.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Text(
                  '暂无可阅读章节',
                  style: TextStyle(color: context.tertiaryTextColor),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final maxExtent = constraints.maxWidth >= 720
                    ? 200.0
                    : constraints.maxWidth >= 480
                    ? 220.0
                    : constraints.maxWidth;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: chapters.length,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: maxExtent,
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 16 / 11,
                  ),
                  itemBuilder: (context, index) {
                    final chapter = chapters[index];
                    return _ChapterCard(
                      chapter: chapter,
                      isNew: index == chapters.length - 1,
                      thumbnail: loadThumbnail(chapter),
                      coverHeaders: coverHeaders,
                      onTap: () => onSelect(chapter),
                      onDownload: () => onDownload(chapter),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.chapter,
    required this.isNew,
    required this.thumbnail,
    required this.coverHeaders,
    required this.onTap,
    required this.onDownload,
  });

  final ComicChapter chapter;
  final bool isNew;
  final Future<String?> thumbnail;
  final Map<String, dynamic>? coverHeaders;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brMd,
        side: BorderSide(color: context.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned.fill(
              child: ChapterThumbnail(
                load: () => thumbnail,
                headers: coverHeaders,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 44,
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
              right: 42,
              bottom: 8,
              child: Text(
                chapter.title.trim().isEmpty
                    ? '第${chapter.order}话'
                    : chapter.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.onImageColor,
                ),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 2,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: IconButton(
                  tooltip: '下载本章',
                  onPressed: onDownload,
                  icon: Icon(
                    Icons.download_rounded,
                    size: 18,
                    color: context.onImageColor,
                  ),
                ),
              ),
            ),
            if (isNew)
              Positioned(
                top: 8,
                right: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colorScheme.primaryContainer,
                    borderRadius: AppRadius.brSm,
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
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
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
