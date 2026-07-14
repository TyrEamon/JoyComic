/// 源设置页（测速选源）。
///
/// 禁漫：
/// - 接口域名轮询池（9 兜底域名 + 用户首选）→ 点测速 → 选最快持久化
/// - 图床分流（app_shunts 动态项 + express 快速通道）→ 6 项测速 → 选最快
///
/// 哔咔：
/// - API 接入域名 go2778 / picacomic 二选一切换
///
/// 功能集成说明：
/// - 禁漫图床测速：`JmNetwork.testAllShunts(state.shunts)` →
///   `JmShuntSpeed` 列表（含 latency/imgHost）→ `pickFastest` →
///   `selectShunt(key)` 持久化。
/// - 哔咔双源切换：`PicacgStateImpl.setApiBaseUrl(url)` 持久化。
/// - 当前全 mock，测速进度条动画。
library source_settings_page;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../comic_source/comic_source.dart';
import '../../network/jm/jm_network.dart';
import '../../network/picacg/picacg_network.dart';
import '../../network/source_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class SourceSettingsPage extends StatefulWidget {
  const SourceSettingsPage({super.key, this.sourceKey = 'jm'});

  final String sourceKey;

  @override
  State<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends State<SourceSettingsPage> {
  bool _testing = false;
  int? _selectedShunt;
  String? _picaDomain; // 'go2778' 或 'picacomic'

  @override
  void initState() {
    super.initState();
    if (widget.sourceKey == 'picacg') {
      final source = ComicSource.find('picacg');
      final state = source != null ? PicacgNetwork().state : null;
      _picaDomain = state?.apiBaseUrl.contains('picacomic') == true ? 'picacomic' : 'go2778';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isJm = widget.sourceKey == 'jm';
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: Text(isJm ? '禁漫图床测速' : '哔咔接入域名'),
        backgroundColor: context.pageBackground,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (isJm) ...[
            const _SectionLabel(label: '图床分流（6 项）'),
            ..._jmShunts.map((s) => _ShuntTile(
                  title: s.title,
                  subtitle: s.host,
                  latency: s.latency,
                  selected: _selectedShunt == s.key,
                  testing: _testing,
                  onTap: () => setState(() => _selectedShunt = s.key),
                )),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.speed_rounded, size: 18),
              label: Text(_testing ? '测速中…' : '开始测速'),
              style: FilledButton.styleFrom(
                backgroundColor: context.colorScheme.primary,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SectionLabel(label: 'API 兜底域名（9 个）'),
            ..._jmDomains.map((d) => _DomainTile(title: d, latency: _domainLatency(d))),
          ] else ...[
            const _SectionLabel(label: 'API 接入域名'),
            _RadioTile(
              title: 'go2778 中转（默认）',
              subtitle: 'picaapi.go2778.com',
              selected: _picaDomain == 'go2778',
              onTap: () => _setPicaDomain('go2778'),
            ),
            _RadioTile(
              title: 'picacomic 直连',
              subtitle: 'picaapi.picacomic.com',
              selected: _picaDomain == 'picacomic',
              onTap: () => _setPicaDomain('picacomic'),
            ),
          ],
        ],
      ),
    );
  }

  void _setPicaDomain(String domain) {
    final source = ComicSource.find('picacg');
    if (source == null) return;
    final state = PicacgNetwork().state;
    if (state == null) return;
    final url = domain == 'picacomic'
        ? 'https://picaapi.picacomic.com'
        : 'https://picaapi.go2778.com';
    state.setApiBaseUrl(url);
    setState(() => _picaDomain = domain);
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      final net = JmNetwork();
      final state = net.state;
      if (state == null || state.shunts.isEmpty) {
        // 用预设 shunt 列表测试
        final results = await net.testAllShunts([
          JmShunt(key: 0, title: '快速通道(express)'),
          JmShunt(key: 1, title: '分流1'),
          JmShunt(key: 2, title: '分流2'),
          JmShunt(key: 3, title: '分流3'),
          JmShunt(key: 4, title: '分流4'),
          JmShunt(key: 5, title: '分流5'),
        ]);
        final fastest = net.pickFastest(results);
        if (fastest != null && fastest.key >= 0) {
          await net.selectShunt(fastest.key);
          if (mounted) setState(() => _selectedShunt = fastest.key);
        }
      } else {
        final results = await net.testAllShunts(state.shunts);
        final fastest = net.pickFastest(results);
        if (fastest != null) {
          await net.selectShunt(fastest.key);
          if (mounted) setState(() => _selectedShunt = fastest.key);
        }
      }
    } catch (_) {
      // 测速失败保持 mock 状态
    }
    if (!mounted) return;
    setState(() => _testing = false);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
          top: AppSpacing.sm, bottom: AppSpacing.xs, left: AppSpacing.xxs),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.tertiaryTextColor)),
    );
  }
}

class _ShuntTile extends StatelessWidget {
  const _ShuntTile({
    required this.title,
    required this.subtitle,
    required this.latency,
    required this.selected,
    required this.testing,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final int? latency;
  final bool selected;
  final bool testing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: AppRadius.brMd,
          border: Border.all(
            color: selected ? context.colorScheme.primary : context.borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.primaryTextColor)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: context.tertiaryTextColor)),
                ],
              ),
            ),
            if (testing)
              const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else if (latency != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: latency! < 300
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.hotAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  latency! < 0 ? '失败' : '${latency}ms',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: latency! < 300 ? AppColors.success : AppColors.hotAccent,
                  ),
                ),
              ),
            if (selected)
              Padding(
                padding: EdgeInsets.only(left: AppSpacing.xs),
                child: Icon(Icons.check_circle_rounded,
                    color: context.colorScheme.primary, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

class _DomainTile extends StatelessWidget {
  const _DomainTile({required this.title, required this.latency});
  final String title;
  final int? latency;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: AppRadius.brSm,
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 13, color: context.secondaryTextColor)),
          ),
          if (latency != null)
            Text(latency! < 0 ? '失败' : '${latency}ms',
                style: TextStyle(
                    fontSize: 12,
                    color: latency! < 300 ? AppColors.success : AppColors.hotAccent,
                    fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RadioTile extends StatelessWidget {
  const _RadioTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: AppRadius.brMd,
          border: Border.all(
            color: selected ? context.colorScheme.primary : context.borderColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.primaryTextColor)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: context.tertiaryTextColor)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? context.colorScheme.primary : context.tertiaryTextColor,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _JmShunt {
  const _JmShunt({required this.key, required this.title, required this.host, this.latency});
  final int key;
  final String title;
  final String host;
  final int? latency;
}

final _jmShunts = [
  _JmShunt(key: 0, title: '快速通道 (express)', host: 'cdn-msp.18comic.vip', latency: 180),
  _JmShunt(key: 1, title: '线路一', host: 'cdn-msp3.jmapiproxy1.cc', latency: 320),
  _JmShunt(key: 2, title: '线路二', host: 'cdn-msp.jmapiproxy3.cc', latency: 450),
  _JmShunt(key: 3, title: '线路三', host: 'cdn-msp2.jmapiproxy2.cc', latency: null),
  _JmShunt(key: 4, title: '线路四', host: 'cdn-msp3.jmapiproxy3.cc', latency: 580),
  _JmShunt(key: 5, title: '线路五', host: 'cdn-msp.18comic.vip', latency: null),
];

final _jmDomains = [
  'www.cdnhjk.net',
  'www.cdngwc.cc',
  'www.cdngwc.net',
  'www.cdngwc.club',
  'www.cdnutc.me',
  'jmcomic1.cc',
  'jmcomic2.me',
  'jmcomic3.pw',
  'jmcomic4.win',
];

int? _domainLatency(String d) {
  final h = d.hashCode.abs();
  if (h % 7 == 0) return -1;
  return 100 + h % 500;
}
