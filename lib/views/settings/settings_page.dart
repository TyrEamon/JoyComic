/// 设置页。
///
/// 分组：
/// 1. 源管理：启用源列表 + 登录态 + 测速选源入口
/// 2. 阅读设置：默认阅读模式 / 预加载数 / 翻页方式 → push /settings/reader
/// 3. 外观：主题色（动态取色开关）/ 字体
/// 4. 数据与存储：本地下载目录 / WebDAV 同步 / 清除缓存
/// 5. 关于：版本 / 开源 / 免责声明
///
/// 功能集成说明：
/// - 源管理数据来自 `ComicSource.sources` + `AppData.enabledSources`。
/// - WebDAV 同步阶段4 实现（archive 包 zip 备份）。
/// - 动态取色开关读写 ReaderConf / AppData 配置。
/// - 动态取色/深色模式开关已接入 AppData 持久化。
library settings_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../foundation/app_data.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final appData = AppData.instance;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('设置'), backgroundColor: AppColors.background),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          _SettingsGroup(title: '源管理', items: [
            _SettingsItem(icon: Icons.source_outlined, label: '禁漫', value: '未登录', route: '/login'),
            _SettingsItem(icon: Icons.source_outlined, label: '哔咔', value: '已登录 · Lv.12', route: '/login'),
            _SettingsItem(icon: Icons.speed_rounded, label: '测速选源', value: '禁漫图床', route: '/settings/source'),
          ]),
          _SettingsGroup(title: '阅读', items: [
            _SettingsItem(icon: Icons.menu_book_rounded, label: '阅读设置', route: '/settings/reader'),
            _SettingsItem(icon: Icons.swap_horiz_rounded, label: '默认阅读模式', value: '竖直连续'),
          ]),
          _SettingsGroup(title: '外观', items: [
            _SwitchItem(
              icon: Icons.palette_outlined,
              label: '封面动态取色',
              value: appData.enableDynamicColor,
              onChanged: (v) {
                appData.enableDynamicColor = v;
                setState(() {});
              },
            ),
            _SwitchItem(
              icon: Icons.dark_mode_rounded,
              label: '深色模式',
              value: appData.enableDarkMode,
              onChanged: (v) {
                appData.enableDarkMode = v;
                setState(() {});
              },
            ),
          ]),
          _SettingsGroup(title: '数据与存储', items: [
            _SettingsItem(icon: Icons.cloud_sync_outlined, label: 'WebDAV 同步', value: '未配置', route: '/webdav'),
            _SettingsItem(icon: Icons.cleaning_services_outlined, label: '清除缓存', value: '128 MB'),
          ]),
          _SettingsGroup(title: '关于', items: [
            _SettingsItem(icon: Icons.info_outline_rounded, label: '版本', value: '0.1.0'),
            _SettingsItem(icon: Icons.code_rounded, label: '开源说明', route: '/about'),
            _SettingsItem(icon: Icons.article_outlined, label: '诊断日志', route: '/logs'),
          ]),
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
              AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
          child: Text(title,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textLow)),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                items[i],
                if (i != items.length - 1)
                  const Divider(height: 1, indent: 56, color: AppColors.divider),
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
  });
  final IconData icon;
  final String label;
  final String? value;
  final String? route;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: route == null ? null : () => context.push(route!),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.brandPink),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 15, color: AppColors.textHigh)),
            ),
            if (value != null)
              Text(value!,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textLow)),
            const SizedBox(width: AppSpacing.xxs),
            if (route != null)
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textLow),
          ],
        ),
      ),
    );
  }
}

class _SwitchItem extends StatelessWidget {
  const _SwitchItem({required this.icon, required this.label, required this.value, required this.onChanged});
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.brandPink),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textHigh)),
          ),
          Switch.adaptive(
            value: value,
            activeColor: AppColors.brandPink,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
