/// 通用区块标题组件。
///
/// 用于首页/分类/详情各区块的标题行：左标题 + 可选副标题 + 右动作入口。
/// 动作入口点击回调 [onAction]，文字取 [actionLabel]（如"更多 >""换一换"）。
///
/// 与详情页内 SynopsisBlock/ChapterGrid 的内联标题区分：
/// - 详情页区块标题在各自 widget 内联，因有展开/网格等强耦合布局；
/// - 列表/首页的区块标题用本组件，跨页统一。
library section_header;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          padding ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(title, style: AppTypography.section(context)),
          if (subtitle != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Text(subtitle!, style: AppTypography.subtitle(context)),
          ],
          const Spacer(),
          if (actionLabel != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxs,
                  vertical: AppSpacing.xxs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      actionLabel!,
                      style: AppTypography.sectionAction(context),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: context.tertiaryTextColor,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
