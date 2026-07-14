/// 首页工具栏（横向功能入口）。
///
/// 主人钦定的 6 个入口，横向滚动排列，每项 = 图标 + 文字 + 渐变光晕圆背景：
/// - 最新       → /ranking?tab=latest   （最新更新漫画流）
/// - 热门排行   → /ranking?tab=hot      （热度榜）
/// - 影视       → /video               （影视化作品聚合）
/// - 以图搜图   → /image-search        （上传图片找相似漫画）
/// - 收藏库     → /favorites           （=收藏 Tab，这里做快捷入口）
/// - 下载       → /download           （已下载与队列）
///
/// 每项直接注入已注册生产路由的导航动作。
library home_tool_bar;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';

class HomeToolBar extends StatelessWidget {
  const HomeToolBar({super.key, required this.entries});

  final List<ToolEntry> entries;

  /// 默认入口配置。
  static List<ToolEntry> defaults(BuildContext context) => [
    ToolEntry(
      label: '最新',
      icon: Icons.new_releases_outlined,
      gradientStart: context.colorScheme.primary,
      gradientEnd: context.colorScheme.secondary,
      onTap: () => context.push('/ranking?tab=latest'),
    ),
    ToolEntry(
      label: '热门排行',
      icon: Icons.local_fire_department_outlined,
      gradientStart: const Color(0xFFFF8A65),
      gradientEnd: const Color(0xFFFF6FA5),
      onTap: () => context.push('/ranking?tab=hot'),
    ),
    ToolEntry(
      label: '影视',
      icon: Icons.movie_outlined,
      gradientStart: const Color(0xFF7B9EFF),
      gradientEnd: const Color(0xFF9D7BFF),
      onTap: () => context.push('/video'),
    ),
    ToolEntry(
      label: '以图搜图',
      icon: Icons.image_search_outlined,
      gradientStart: const Color(0xFF6FE0A8),
      gradientEnd: const Color(0xFFB967FF),
      onTap: () => context.push('/image-search'),
    ),
    ToolEntry(
      label: '收藏库',
      icon: Icons.favorite_border_rounded,
      gradientStart: const Color(0xFFFF7BA9),
      gradientEnd: const Color(0xFFFF6B6B),
      onTap: () => context.push('/favorites'),
    ),
    ToolEntry(
      label: '下载',
      icon: Icons.download_outlined,
      gradientStart: const Color(0xFF9D7BFF),
      gradientEnd: const Color(0xFF7B9EFF),
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
    required this.gradientStart,
    required this.gradientEnd,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color gradientStart;
  final Color gradientEnd;
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
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [entry.gradientStart, entry.gradientEnd],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: entry.gradientStart.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(entry.icon, size: 24, color: Colors.white),
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
