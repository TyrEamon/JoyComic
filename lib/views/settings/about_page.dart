/// About and project information page.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

import '../../foundation/app_package_info.dart';
import '../../theme/app_safe_area.dart';
import '../../theme/app_spacing.dart';

const String joyComicGithubUrl = 'https://github.com/xiaoqi419/JoyComic';

class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    this.launchUrl = _launchExternal,
    this.packageInfoLoader = loadAppPackageInfo,
  });

  final Future<bool> Function(Uri) launchUrl;
  final AppPackageInfoLoader packageInfoLoader;

  static Future<bool> _launchExternal(Uri uri) =>
      launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late Future<AppPackageInfo> _packageInfo;

  @override
  void initState() {
    super.initState();
    _packageInfo = widget.packageInfoLoader();
  }

  @override
  void didUpdateWidget(covariant AboutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packageInfoLoader != widget.packageInfoLoader) {
      _packageInfo = widget.packageInfoLoader();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppPackageInfo>(
      future: _packageInfo,
      builder: (context, snapshot) {
        final info = snapshot.data ?? AppPackageInfo.fallback;
        return _AboutContent(
          info: info,
          loading: snapshot.connectionState != ConnectionState.done,
          launchUrl: widget.launchUrl,
        );
      },
    );
  }
}

class _AboutContent extends StatelessWidget {
  const _AboutContent({
    required this.info,
    required this.loading,
    required this.launchUrl,
  });

  final AppPackageInfo info;
  final bool loading;
  final Future<bool> Function(Uri) launchUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.6,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('关于 JoyComic')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          bottomContentInset(context),
        ),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    size: 42,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  info.appName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  loading ? '正在读取版本…' : info.versionLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _SectionCard(
            title: '用途与免责声明',
            child: Text(
              'JoyComic 是一个用于个人漫画阅读、收藏与离线管理的开源客户端。'
              '应用只提供内容展示和本地管理能力，内容、版权、可用性及来源服务均由对应服务方负责。'
              '请遵守所在地法律法规和内容服务条款，不要使用本应用侵犯他人权益。',
              style: bodyStyle,
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '项目',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.code_rounded, color: scheme.primary),
                  title: const Text('GitHub 项目主页'),
                  trailing: const Icon(Icons.open_in_new_rounded, size: 20),
                  onTap: () => launchUrl(Uri.parse(joyComicGithubUrl)),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.menu_book_rounded, color: scheme.primary),
                  title: const Text('查看开源许可'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: info.appName,
                    applicationVersion: info.licenseVersion,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.article_outlined, color: scheme.primary),
                  title: const Text('诊断日志'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/logs'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'JoyComic · 仅供学习与个人使用',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
