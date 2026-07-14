/// About and project information page.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

const String joyComicAppName = 'JoyComic';
const String joyComicVersion = '0.1.0';
const String joyComicBuildNumber = '1';
const String joyComicGithubUrl = 'https://github.com/xiaoqi419/JoyComic';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, this.launchUrl = _launchExternal});

  final Future<bool> Function(Uri) launchUrl;

  static Future<bool> _launchExternal(Uri uri) =>
      launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);

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
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF7BA9), Color(0xFFB967FF)],
                    ),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    size: 42,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  joyComicAppName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '版本 $joyComicVersion ($joyComicBuildNumber)',
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
                    applicationName: joyComicAppName,
                    applicationVersion: '$joyComicVersion+$joyComicBuildNumber',
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
