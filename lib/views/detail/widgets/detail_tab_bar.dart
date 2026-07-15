import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';
import '../../../theme/app_theme_context.dart';
import '../../../theme/app_typography.dart';

enum DetailTab { chapters, comments }

class DetailTabBar extends StatelessWidget {
  const DetailTabBar({
    super.key,
    required this.selected,
    required this.commentTotal,
    required this.onChanged,
  });

  final DetailTab selected;
  final int commentTotal;
  final ValueChanged<DetailTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.pageBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: _TabButton(
                label: '章节',
                selected: selected == DetailTab.chapters,
                onTap: () => onChanged(DetailTab.chapters),
              ),
            ),
            Expanded(
              child: _TabButton(
                label: '评论 $commentTotal',
                selected: selected == DetailTab.comments,
                onTap: () => onChanged(DetailTab.comments),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DetailTabBarDelegate extends SliverPersistentHeaderDelegate {
  DetailTabBarDelegate({
    required this.selected,
    required this.commentTotal,
    required this.onChanged,
  });

  final DetailTab selected;
  final int commentTotal;
  final ValueChanged<DetailTab> onChanged;

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => DetailTabBar(
    selected: selected,
    commentTotal: commentTotal,
    onChanged: onChanged,
  );

  @override
  bool shouldRebuild(covariant DetailTabBarDelegate oldDelegate) =>
      selected != oldDelegate.selected ||
      commentTotal != oldDelegate.commentTotal ||
      onChanged != oldDelegate.onChanged;
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: AppTypography.sectionAction(context).copyWith(
                      color: selected
                          ? context.colorScheme.primary
                          : context.secondaryTextColor,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 2,
                width: selected ? 44 : 0,
                color: context.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
