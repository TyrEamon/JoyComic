/// 我的页（= 底部 Tab 4）。
///
/// 结构：
/// 1. 用户信息卡：头像 + 昵称 + 等级 + 签名（未登录显示"点此登录"占位卡）
/// 2. 数据统计：收藏 / 历史 / 下载 三宫格
/// 3. 功能入口列表：源管理 / 阅读设置 / 下载管理 / 历史记录 / 关于
/// 4. 底部：主题色 / 关于版本
///
/// 功能集成说明：
/// - 登录态从 `ComicSource.find(key).isLogin` + `data['user']` 取。
///   哔咔 user 来自 getProfile，禁漫 user 来自 login account。
/// - 未登录时点用户卡 push /login。
/// - 历史记录阶段4 本地 DB 接入（ComicReadRecord）。
/// - 当前全 mock。
library mine_page;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBackground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          children: [
            const _UserCard(loggedIn: false),
            const SizedBox(height: AppSpacing.md),
            const _StatsRow(),
            const SizedBox(height: AppSpacing.lg),
            const _MenuGroup(
              title: '内容管理',
              items: [
                _MenuItem(
                  icon: Icons.history_rounded,
                  label: '历史记录',
                  route: '/history',
                ),
                _MenuItem(
                  icon: Icons.download_rounded,
                  label: '下载管理',
                  route: '/download',
                ),
                _MenuItem(
                  icon: Icons.favorite_rounded,
                  label: '我的收藏',
                  route: '/favorites',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const _MenuGroup(
              title: '设置',
              items: [
                _MenuItem(
                  icon: Icons.source_outlined,
                  label: '源管理 / 登录',
                  route: '/login',
                ),
                _MenuItem(
                  icon: Icons.menu_book_rounded,
                  label: '阅读设置',
                  route: '/settings/reader',
                ),
                _MenuItem(
                  icon: Icons.tune_rounded,
                  label: '应用设置',
                  route: '/settings',
                ),
                _MenuItem(
                  icon: Icons.info_outline_rounded,
                  label: '关于',
                  route: '/about',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: Text(
                  'JoyComic 0.1.0 · 阶段3 UI',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.tertiaryTextColor,
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

class _UserCard extends StatelessWidget {
  const _UserCard({required this.loggedIn});
  final bool loggedIn;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => loggedIn ? {} : context.push('/login'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x33FF7BA9), Color(0x33B967FF)],
          ),
          borderRadius: AppRadius.brLg,
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    context.colorScheme.primary,
                    context.colorScheme.secondary,
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 28),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loggedIn ? '用户昵称' : '点击登录',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: context.primaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loggedIn ? 'Lv.12 · 距下一级还需 320 经验' : '登录后同步收藏与阅读进度',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.tertiaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.tertiaryTextColor),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: const [
          _StatCell(count: '128', label: '收藏'),
          _StatCell(count: '56', label: '历史'),
          _StatCell(count: '12', label: '下载'),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.count, required this.label});
  final String count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          children: [
            Text(
              count,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: context.primaryTextColor,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: context.tertiaryTextColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.title, required this.items});
  final String title;
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.tertiaryTextColor,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                items[i],
                if (i != items.length - 1)
                  Divider(height: 1, indent: 56, color: context.dividerColor),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.route,
  });
  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(route),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: context.colorScheme.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: context.primaryTextColor,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.tertiaryTextColor,
            ),
          ],
        ),
      ),
    );
  }
}
