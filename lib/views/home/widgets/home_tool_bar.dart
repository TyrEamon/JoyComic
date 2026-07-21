/// Home shortcut toolbar.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';

class HomeToolBar extends StatelessWidget {
  const HomeToolBar({super.key, required this.entries});

  final List<ToolEntry> entries;

  static List<ToolEntry> defaults(BuildContext context) => [
    ToolEntry(
      label: '排行榜',
      icon: Icons.leaderboard_outlined,
      onTap: () => context.push('/ranking'),
    ),
    ToolEntry(
      label: '影视',
      icon: Icons.movie_outlined,
      onTap: () => context.push('/video'),
    ),
    ToolEntry(
      label: '精品',
      icon: Icons.auto_awesome_outlined,
      onTap: () => context.push('/premium'),
    ),
    ToolEntry(
      label: '以图搜图',
      icon: Icons.image_search_outlined,
      onTap: () => context.push('/image-search'),
    ),
    ToolEntry(
      label: '收藏库',
      icon: Icons.favorite_border_rounded,
      onTap: () => context.push('/favorites'),
    ),
    ToolEntry(
      label: '下载',
      icon: Icons.download_outlined,
      onTap: () => context.push('/download'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        physics: const BouncingScrollPhysics(),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) => _ToolItem(entry: entries[i]),
      ),
    );
  }
}

class ToolEntry {
  const ToolEntry({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _ToolItem extends StatelessWidget {
  const _ToolItem({required this.entry});

  final ToolEntry entry;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: entry.onTap,
      borderRadius: AppRadius.brLg,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: Key('home-tool-icon-${entry.label}'),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: context.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
              ),
              child: Icon(
                entry.icon,
                size: 24,
                color: context.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: context.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
