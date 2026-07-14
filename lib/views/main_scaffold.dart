/// 全局底部 Tab 框架。
///
/// 4 个主 Tab：首页 / 分类 / 收藏 / 我的。每个 Tab 是独立页，状态独立保留。
/// 搜索做 AppBar 右上角图标入口（push 独立搜索页），不占 Tab 位。
///
/// 视觉：底部 Tab 栏半透明毛玻璃 + 品牌色选中态，沉浸式贴合深色基调。
library main_scaffold;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../theme/app_radius.dart';
import 'category/category_page.dart';
import 'favorites/favorites_page.dart';
import 'home/home_page.dart';
import 'mine/mine_page.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _index = 0;

  late final List<_Tab> _tabs = [
    _Tab(
      label: '首页',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      page: HomePage(),
    ),
    _Tab(
      label: '分类',
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
      page: CategoryPage(),
    ),
    _Tab(
      label: '收藏',
      icon: Icons.favorite_border_rounded,
      activeIcon: Icons.favorite_rounded,
      page: FavoritesPage(),
    ),
    _Tab(
      label: '我的',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      page: MinePage(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [for (final t in _tabs) t.page],
      ),
      extendBody: true,
      bottomNavigationBar: _BottomBar(
        tabs: _tabs,
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _Tab {
  const _Tab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.page,
  });
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget page;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.tabs,
    required this.index,
    required this.onTap,
  });

  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: context.pageBackground.withValues(alpha: 0.92),
            border: Border(top: BorderSide(color: context.borderColor)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _NavItem(
                        tab: tabs[i],
                        active: i == index,
                        onTap: () => onTap(i),
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });
  final _Tab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? context.colorScheme.primary
        : context.tertiaryTextColor;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(active ? tab.activeIcon : tab.icon, size: 24, color: color),
          const SizedBox(height: 2),
          Text(
            tab.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// BackdropFilter 的 ImageFilter 由顶层 `import 'dart:ui';` 提供。
