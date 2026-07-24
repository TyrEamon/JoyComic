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
/// - WebDAV、缓存与诊断入口均连接到真实页面或操作。
/// - 主题模式由 AppData 持久化并即时通知应用。
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/app_data.dart';
import '../../foundation/app_package_info.dart';
import '../../foundation/cache_manager.dart';
import '../../foundation/download_manager.dart';
import '../../foundation/reader_config.dart';
import '../../foundation/webdav_config_store.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_safe_area.dart';
import '../common/source_account_profile.dart';
import '../common/source_account_sheet.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    this.cacheManager,
    this.webDavConfigStore,
    this.packageInfoLoader = loadAppPackageInfo,
  });

  final CacheManager? cacheManager;
  final WebDavConfigStore? webDavConfigStore;
  final AppPackageInfoLoader packageInfoLoader;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<CacheManager> _cacheManager;
  late Future<WebDavConfigStore> _webDavConfigStore;
  late Future<AppPackageInfo> _packageInfo;
  CacheSize? _cacheSize;
  String _webDavStatus = '读取中…';
  bool _loadingCache = false;

  @override
  void initState() {
    super.initState();
    _cacheManager = widget.cacheManager == null
        ? CacheManager.create(
            onClearCompletedDownloads: () =>
                DownloadManager.instance.clearCompletedSafely(),
          )
        : Future.value(widget.cacheManager!);
    _webDavConfigStore = widget.webDavConfigStore == null
        ? WebDavConfigStore.create()
        : Future<WebDavConfigStore>.value(widget.webDavConfigStore!);
    _packageInfo = widget.packageInfoLoader();
    _refreshCacheSize();
    _refreshWebDavStatus();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageInfoLoader != widget.packageInfoLoader) {
      _packageInfo = widget.packageInfoLoader();
    }
  }

  Future<void> _refreshWebDavStatus() async {
    final store = await _webDavConfigStore;
    if (!mounted) return;
    setState(() => _webDavStatus = store.statusLabel);
  }

  Future<void> _openWebDavSettings() async {
    await context.push('/webdav');
    if (mounted) await _refreshWebDavStatus();
  }

  Future<void> _refreshCacheSize() async {
    try {
      final manager = await _cacheManager;
      final size = await manager.calculateSize();
      if (!mounted) return;
      setState(() => _cacheSize = size);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _cacheSize = const CacheSize(diskBytes: 0, imageCacheBytes: 0),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('读取缓存大小失败：$error')));
    }
  }

  Future<void> _clearCaches() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存？'),
        content: const Text(
          '只会删除网络图片缓存、临时文件、日志和未完成下载临时文件，不会删除数据库、账号、收藏、历史或已完成下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loadingCache = true);
    try {
      final manager = await _cacheManager;
      await manager.clearSafeCaches();
      await _refreshCacheSize();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缓存已清除')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清除缓存失败：$error')));
    } finally {
      if (mounted) setState(() => _loadingCache = false);
    }
  }

  Future<void> _clearCompletedDownloads() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除已完成下载？'),
        content: const Text('这是危险操作，将删除所有已完成的离线章节及其下载记录，且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除已完成下载'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loadingCache = true);
    try {
      final manager = await _cacheManager;
      await manager.clearCompletedDownloads();
      await _refreshCacheSize();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已完成下载已删除')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除已完成下载失败：$error')));
    } finally {
      if (mounted) setState(() => _loadingCache = false);
    }
  }

  Future<void> _openReaderSettings() async {
    await context.push('/settings/reader');
    if (mounted) setState(() {});
  }

  Future<void> _openSourceManager() async {
    await context.push('/settings/sources');
    if (mounted) setState(() {});
  }

  Future<void> _openAccount(
    ComicSource source,
    SourceAccountProfile profile,
  ) async {
    if (!profile.isLoggedIn) {
      await context.push(
        '/login?source=${Uri.encodeQueryComponent(source.key)}',
      );
      if (mounted) setState(() {});
      return;
    }
    final changed = await showSourceAccountSheet(context, source);
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accountSources = ComicSource.sources
        .where((source) => source.account != null)
        .toList(growable: false);
    final enabledSourceCount = ComicSource.sources.length;
    final jmSource = ComicSource.find('jm');
    final picaSource = ComicSource.find('picacg');
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: context.pageBackground,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: bottomContentInset(context),
        ),
        child: Column(
          children: [
            _SettingsGroup(
              title: '漫画源',
              items: [
                _SettingsItem(
                  icon: Icons.source_outlined,
                  label: '源管理',
                  value: '$enabledSourceCount 个已启用',
                  onTap: _openSourceManager,
                ),
              ],
            ),
            _SettingsGroup(
              title: '账号',
              items: [
                if (accountSources.isEmpty)
                  const _SettingsItem(
                    icon: Icons.person_off_outlined,
                    label: '暂无可登录源',
                    value: '请先启用漫画源',
                  )
                else
                  for (final source in accountSources)
                    Builder(
                      builder: (context) {
                        final profile = SourceAccountProfile.fromSource(source);
                        return _SettingsItem(
                          icon: Icons.account_circle_outlined,
                          label: '${profile.sourceName}账号',
                          value: profile.settingsStatus,
                          onTap: () => _openAccount(source, profile),
                        );
                      },
                    ),
              ],
            ),
            _SettingsGroup(
              title: '线路与域名',
              items: [
                if (jmSource != null)
                  const _SettingsItem(
                    icon: Icons.speed_rounded,
                    label: '禁漫线路与图床测速',
                    value: '分流、图床、API 域名',
                    route: '/settings/source?source=jm',
                  ),
                if (picaSource != null)
                  const _SettingsItem(
                    icon: Icons.dns_outlined,
                    label: '哔咔接入域名',
                    value: '直连与中转',
                    route: '/settings/source?source=picacg',
                  ),
              ],
            ),
            const _SettingsGroup(title: '外观', items: [_ThemeModeItem()]),
            _SettingsGroup(
              title: '数据与存储',
              items: [
                _SettingsItem(
                  icon: Icons.cloud_sync_outlined,
                  label: 'WebDAV 同步',
                  value: _webDavStatus,
                  onTap: _openWebDavSettings,
                ),
                _SettingsItem(
                  icon: Icons.cleaning_services_outlined,
                  label: '清除缓存',
                  value: _loadingCache
                      ? '处理中…'
                      : _cacheSize == null
                      ? '读取中…'
                      : formatCacheBytes(_cacheSize!.totalBytes),
                  onTap: _loadingCache ? null : _clearCaches,
                  loading: _loadingCache,
                ),
                _SettingsItem(
                  icon: Icons.delete_sweep_outlined,
                  label: '删除已完成下载',
                  value: '危险操作',
                  onTap: _loadingCache ? null : _clearCompletedDownloads,
                  iconColor: context.colorScheme.error,
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
            _SettingsGroup(
              title: '关于',
              items: [
                FutureBuilder<AppPackageInfo>(
                  future: _packageInfo,
                  builder: (context, snapshot) {
                    final info = snapshot.data ?? AppPackageInfo.fallback;
                    return _SettingsItem(
                      icon: Icons.info_outline_rounded,
                      label: '版本',
                      value: snapshot.connectionState == ConnectionState.done
                          ? info.version
                          : '读取中…',
                    );
                  },
                ),
                const _SettingsItem(
                  icon: Icons.code_rounded,
                  label: '开源说明',
                  route: '/about',
                ),
                const _SettingsItem(
                  icon: Icons.article_outlined,
                  label: '诊断日志',
                  route: '/logs',
                ),
              ],
            ),
          ],
        ),
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
    this.loading = false,
    this.iconColor,
  });
  final IconData icon;
  final String label;
  final String? value;
  final String? route;
  final VoidCallback? onTap;
  final bool loading;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final action = onTap ?? (route == null ? null : () => context.push(route!));
    return InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: iconColor ?? context.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 15, color: context.primaryTextColor),
              ),
            ),
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (value != null)
              Text(
                value!,
                style: TextStyle(
                  fontSize: 13,
                  color: context.tertiaryTextColor,
                ),
              ),
            const SizedBox(width: AppSpacing.xxs),
            if (action != null && !loading)
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
