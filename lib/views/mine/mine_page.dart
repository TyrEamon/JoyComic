/// Mine page backed by enabled sources and persisted local statistics.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../comic_source/comic_source.dart';
import '../../database/favorites_helper.dart';
import '../../database/read_record_helper.dart';
import '../../foundation/download_manager.dart';
import '../../foundation/download_task.dart';
import '../../foundation/log.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../common/source_account_profile.dart';

typedef MineStatsLoader = MineStats Function();

class MinePage extends StatefulWidget {
  const MinePage({super.key, this.statsLoader});

  final MineStatsLoader? statsLoader;

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  MineStats _stats = const MineStats();

  @override
  void initState() {
    super.initState();
    _stats = _readStats();
    FavoriteNotifier.instance.addListener(_refreshStats);
    ReadRecordNotifier.instance.addListener(_refreshStats);
    DownloadManager.instance.addListener(_refreshStats);
  }

  @override
  void dispose() {
    FavoriteNotifier.instance.removeListener(_refreshStats);
    ReadRecordNotifier.instance.removeListener(_refreshStats);
    DownloadManager.instance.removeListener(_refreshStats);
    super.dispose();
  }

  MineStats _readStats() {
    final loader = widget.statsLoader;
    if (loader != null) return loader();
    try {
      return MineStats(
        favorites: FavoritesHelper().count(),
        history: ReadRecordHelper().count(),
        downloads: DownloadManager.instance.tasks
            .where((task) => task.status == DownloadStatus.completed)
            .length,
      );
    } catch (error, stackTrace) {
      Log.e(
        'Failed to load Mine statistics',
        error: error,
        stackTrace: stackTrace,
      );
      return const MineStats();
    }
  }

  void _refreshStats() {
    if (!mounted) return;
    setState(() => _stats = _readStats());
  }

  Future<void> _open(String route) async {
    await context.push(route);
    _refreshStats();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ComicSource.sources
        .map(SourceAccountProfile.fromSource)
        .toList(growable: false);
    return Scaffold(
      backgroundColor: context.pageBackground,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          children: [
            if (accounts.isEmpty)
              _NoSourceCard(onTap: () => _open('/login'))
            else
              for (final account in accounts)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _UserCard(
                    profile: account,
                    onTap: () => _open(
                      '/login?source=${Uri.encodeQueryComponent(account.sourceKey)}',
                    ),
                  ),
                ),
            const SizedBox(height: AppSpacing.xs),
            _StatsRow(stats: _stats),
            const SizedBox(height: AppSpacing.lg),
            _MenuGroup(
              title: '内容管理',
              items: [
                _MenuItem(
                  icon: Icons.history_rounded,
                  label: '历史记录',
                  onTap: () => _open('/history'),
                ),
                _MenuItem(
                  icon: Icons.download_rounded,
                  label: '下载管理',
                  onTap: () => _open('/download'),
                ),
                _MenuItem(
                  icon: Icons.favorite_rounded,
                  label: '我的收藏',
                  onTap: () => _open('/favorites'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _MenuGroup(
              title: '设置',
              items: [
                _MenuItem(
                  icon: Icons.source_outlined,
                  label: '源管理 / 登录',
                  onTap: () => _open('/login'),
                ),
                _MenuItem(
                  icon: Icons.menu_book_rounded,
                  label: '阅读设置',
                  onTap: () => _open('/settings/reader'),
                ),
                _MenuItem(
                  icon: Icons.tune_rounded,
                  label: '应用设置',
                  onTap: () => _open('/settings'),
                ),
                _MenuItem(
                  icon: Icons.info_outline_rounded,
                  label: '关于',
                  onTap: () => _open('/about'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Center(
                child: Text(
                  'JoyComic 0.1.0',
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

class MineStats {
  const MineStats({this.favorites = 0, this.history = 0, this.downloads = 0});

  final int favorites;
  final int history;
  final int downloads;
}

class _NoSourceCard extends StatelessWidget {
  const _NoSourceCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _AccountContainer(
    onTap: onTap,
    avatar: Icon(
      Icons.person_add_alt_1,
      color: context.colorScheme.primary,
      size: 28,
    ),
    title: '选择漫画源登录',
    subtitle: '启用漫画源后同步账号、收藏与阅读进度',
  );
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.profile, required this.onTap});
  final SourceAccountProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = profile.isLoggedIn
        ? profile.level == null
              ? profile.sourceName
              : '${profile.sourceName} · Lv.${profile.level}'
        : profile.sourceStatus;
    return _AccountContainer(
      key: ValueKey('mine-account-${profile.sourceKey}'),
      onTap: onTap,
      avatar: _Avatar(url: profile.avatarUrl),
      title: profile.isLoggedIn ? profile.displayName : '点击登录',
      subtitle: subtitle,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return Icon(Icons.person, color: context.colorScheme.primary, size: 28);
    }
    return ClipOval(
      child: Image.network(
        url!,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.person, color: context.colorScheme.primary, size: 28),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
      ),
    );
  }
}

class _AccountContainer extends StatelessWidget {
  const _AccountContainer({
    super.key,
    required this.onTap,
    required this.avatar,
    required this.title,
    required this.subtitle,
  });
  final VoidCallback onTap;
  final Widget avatar;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.surfaceColor,
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
              color: context.colorScheme.primaryContainer,
              border: Border.all(color: context.borderColor, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: avatar,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.primaryTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});
  final MineStats stats;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: Row(
      children: [
        _StatCell(
          textKey: const Key('mine-stat-favorites'),
          count: stats.favorites,
          label: '收藏',
        ),
        _StatCell(
          textKey: const Key('mine-stat-history'),
          count: stats.history,
          label: '历史',
        ),
        _StatCell(
          textKey: const Key('mine-stat-downloads'),
          count: stats.downloads,
          label: '下载',
        ),
      ],
    ),
  );
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.textKey,
    required this.count,
    required this.label,
  });
  final Key textKey;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
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
            '$count',
            key: textKey,
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

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.title, required this.items});
  final String title;
  final List<_MenuItem> items;

  @override
  Widget build(BuildContext context) => Column(
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

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
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
