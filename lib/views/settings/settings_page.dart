/// 设置页。
///
/// 分组：
/// 1. 源管理：启用源列表 + 登录态 + 测速选源入口
/// 2. 阅读设置：默认阅读模式 / 预加载数 / 翻页方式 → push /settings/reader
/// 3. 外观：跟随系统 / 浅色 / 深色主题
/// 4. 数据与存储：本地下载目录 / WebDAV 同步 / 清除缓存
/// 5. 关于：版本 / 开源 / 免责声明
///
/// 功能集成说明：
/// - 源管理数据来自 `ComicSource.sources` + `AppData.enabledSources`。
/// - WebDAV 同步阶段4 实现（archive 包 zip 备份）。
/// - 主题模式由 AppData 持久化并即时通知应用。
library settings_page;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:go_router/go_router.dart';

import '../../foundation/app_data.dart';
import '../../foundation/reader_config.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _openReaderSettings() async {
    await context.push('/settings/reader');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: context.pageBackground,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          _SettingsGroup(
            title: '源管理',
            items: [
              _SettingsItem(
                icon: Icons.source_outlined,
                label: '禁漫',
                value: '未登录',
                route: '/login',
              ),
              _SettingsItem(
                icon: Icons.source_outlined,
                label: '哔咔',
                value: '已登录 · Lv.12',
                route: '/login',
              ),
              _SettingsItem(
                icon: Icons.speed_rounded,
                label: '测速选源',
                value: '禁漫图床',
                route: '/settings/source',
              ),
            ],
          ),
          _SettingsGroup(
            title: '阅读',
            items: [
              _SettingsItem(
                icon: Icons.menu_book_rounded,
                label: '阅读设置',
                onTap: _openReaderSettings,
              ),
              _SettingsItem(
                icon: Icons.swap_horiz_rounded,
                label: '默认阅读模式',
                value: ReaderConf.instance.readMode.displayName,
              ),
            ],
          ),
          _SettingsGroup(title: '外观', items: const [_ThemeModeItem()]),
          _SettingsGroup(
            title: '数据与存储',
            items: [
              _SettingsItem(
                icon: Icons.cloud_sync_outlined,
                label: 'WebDAV 同步',
                value: '未配置',
                route: '/webdav',
              ),
              _SettingsItem(
                icon: Icons.cleaning_services_outlined,
                label: '清除缓存',
                value: '128 MB',
              ),
            ],
          ),
          _SettingsGroup(
            title: '关于',
            items: [
              _SettingsItem(
                icon: Icons.info_outline_rounded,
                label: '版本',
                value: '0.1.0',
              ),
              _SettingsItem(
                icon: Icons.code_rounded,
                label: '开源说明',
                route: '/about',
              ),
              _SettingsItem(
                icon: Icons.article_outlined,
                label: '诊断日志',
                route: '/logs',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.items});
  final String title;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.tertiaryTextColor,
            ),
          ),
        ),
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

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.label,
    this.value,
    this.route,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String? value;
  final String? route;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ?? (route == null ? null : () => context.push(route!)),
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
                style: TextStyle(fontSize: 15, color: context.primaryTextColor),
              ),
            ),
            if (value != null)
              Text(
                value!,
                style: TextStyle(
                  fontSize: 13,
                  color: context.tertiaryTextColor,
                ),
              ),
            const SizedBox(width: AppSpacing.xxs),
            if (route != null)
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

class _ThemeModeItem extends StatelessWidget {
  const _ThemeModeItem();

  static String _label(ThemeMode mode) => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };

  @override
  Widget build(BuildContext context) {
    final appData = AppData.instance;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appData.themeNotifier,
      builder: (context, mode, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.palette_outlined,
                    size: 22,
                    color: context.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      '主题模式',
                      style: TextStyle(
                        fontSize: 15,
                        color: context.primaryTextColor,
                      ),
                    ),
                  ),
                  Text(
                    '当前：${_label(mode)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.tertiaryTextColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                    ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (selection) async {
                    await appData.setThemeMode(selection.single);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
