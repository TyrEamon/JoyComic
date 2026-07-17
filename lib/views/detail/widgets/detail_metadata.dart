import 'package:flutter/material.dart';

import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme_context.dart';
import '../../../theme/app_typography.dart';

class DetailMetadata extends StatelessWidget {
  const DetailMetadata({
    super.key,
    required this.authors,
    required this.categories,
    required this.labels,
    required this.rating,
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.chapterCount,
    required this.jmNumber,
    required this.onAuthorTap,
    required this.onCategoryTap,
    required this.onLabelTap,
    this.onJmNumberTap,
  });

  final List<String> authors;
  final List<String> categories;
  final List<String> labels;
  // Kept in the public constructor for compatibility; the score is displayed
  // beside the cover and intentionally not repeated in the metrics panel.
  final double? rating;
  final int? viewCount;
  final int? likeCount;
  final int? commentCount;
  final int chapterCount;
  final String? jmNumber;
  final ValueChanged<String> onAuthorTap;
  final ValueChanged<String> onCategoryTap;
  final ValueChanged<String> onLabelTap;
  final VoidCallback? onJmNumberTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricsPanel(
            viewCount: viewCount,
            likeCount: likeCount,
            commentCount: commentCount,
            chapterCount: chapterCount,
          ),
          if (jmNumber != null && jmNumber!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: _MetadataChip(
                key: ValueKey<String>('detail-metadata-jm-$jmNumber'),
                semanticsLabel: '复制车号 JM$jmNumber',
                label: 'JM$jmNumber',
                icon: Icons.copy_rounded,
                onTap: onJmNumberTap,
              ),
            ),
          ],
          if (authors.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _MetadataGroup(
              title: '作者',
              values: authors,
              keyPrefix: 'author',
              semanticsPrefix: '搜索作者',
              onTap: onAuthorTap,
            ),
          ],
          if (categories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _MetadataGroup(
              title: '分类',
              values: categories,
              keyPrefix: 'category',
              semanticsPrefix: '打开分类',
              onTap: onCategoryTap,
            ),
          ],
          if (labels.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _MetadataGroup(
              title: '标签',
              values: labels,
              keyPrefix: 'label',
              semanticsPrefix: '搜索标签',
              onTap: onLabelTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({
    required this.viewCount,
    required this.likeCount,
    required this.commentCount,
    required this.chapterCount,
  });

  final int? viewCount;
  final int? likeCount;
  final int? commentCount;
  final int chapterCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.semanticColors.surfaceMuted,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final metricWidth = (constraints.maxWidth - AppSpacing.sm) / 2;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _Metric(
                  width: metricWidth,
                  icon: Icons.visibility_outlined,
                  label: '阅读',
                  value: _formatCount(viewCount),
                ),
                _Metric(
                  width: metricWidth,
                  icon: Icons.favorite_border_rounded,
                  label: '喜欢',
                  value: _formatCount(likeCount),
                ),
                _Metric(
                  width: metricWidth,
                  icon: Icons.chat_bubble_outline_rounded,
                  label: '评论',
                  value: _formatCount(commentCount),
                ),
                _Metric(
                  width: metricWidth,
                  icon: Icons.menu_book_outlined,
                  label: '章节',
                  value: chapterCount.toString(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.secondaryTextColor),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '$value $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.meta(context).copyWith(
                color: context.primaryTextColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataGroup extends StatelessWidget {
  const _MetadataGroup({
    required this.title,
    required this.values,
    required this.keyPrefix,
    required this.semanticsPrefix,
    required this.onTap,
  });

  final String title;
  final List<String> values;
  final String keyPrefix;
  final String semanticsPrefix;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(title, style: AppTypography.cardMeta(context)),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final value in values)
                _MetadataChip(
                  key: ValueKey<String>('detail-metadata-$keyPrefix-$value'),
                  semanticsLabel: '$semanticsPrefix $value',
                  label: value,
                  onTap: () => onTap(value),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({
    super.key,
    required this.semanticsLabel,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String semanticsLabel;
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Material(
          color: context.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.pill(44),
            side: BorderSide(color: context.borderColor),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.pill(44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: context.secondaryTextColor),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.meta(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatCount(int? value) {
  if (value == null) return '—';
  if (value >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(1)}亿';
  }
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return value.toString();
}
