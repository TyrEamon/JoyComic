/// Real source endpoint and image-host selection.
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../network/jm/jm_network.dart';
import '../../network/picacg/picacg_network.dart';
import '../../network/source_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

typedef JmShuntTester =
    Future<List<JmShuntSpeed>> Function(List<JmShunt> shunts);
typedef JmShuntSelector = Future<bool> Function(int key);
typedef JmDomainTester = Future<int> Function(String domain);

class SourceSettingsPage extends StatefulWidget {
  const SourceSettingsPage({
    super.key,
    this.sourceKey = 'jm',
    this.jmState,
    this.picacgState,
    this.testShunts,
    this.selectShunt,
    this.testDomain,
  });

  final String sourceKey;
  final JmState? jmState;
  final PicacgState? picacgState;
  final JmShuntTester? testShunts;
  final JmShuntSelector? selectShunt;
  final JmDomainTester? testDomain;

  @override
  State<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends State<SourceSettingsPage> {
  bool _testing = false;
  int? _selectingShunt;
  int? _selectedShunt;
  String? _preferredDomain;
  String? _picaDomain;
  List<JmShunt> _shunts = const <JmShunt>[];
  Map<int, JmShuntSpeed> _shuntSpeeds = const <int, JmShuntSpeed>{};
  Map<String, int> _domainSpeeds = const <String, int>{};

  JmState? get _jmState => widget.jmState ?? JmNetwork().state;
  PicacgState? get _picacgState => widget.picacgState ?? PicacgNetwork().state;

  List<String> get _domains {
    final domains = <String>[];
    void add(String value) {
      final clean = _cleanDomain(value);
      if (clean.isNotEmpty && !domains.contains(clean)) domains.add(clean);
    }

    add(_preferredDomain ?? '');
    for (final domain in jmBuiltInDomains) {
      add(domain);
    }
    return domains;
  }

  @override
  void initState() {
    super.initState();
    if (widget.sourceKey == 'jm') {
      final state = _jmState;
      _selectedShunt = state?.selectedShuntKey;
      final preferred = _cleanDomain(state?.preferredDomain ?? '');
      _preferredDomain = preferred.isEmpty ? null : preferred;
      final configured = state?.shunts ?? const <JmShunt>[];
      _shunts = <JmShunt>[
        if (!configured.any((shunt) => shunt.key == jmExpressShuntKey))
          const JmShunt(key: jmExpressShuntKey, title: '快速通道'),
        ...configured,
      ];
    } else {
      _picaDomain = _picacgState?.apiBaseUrl.contains('picacomic') == true
          ? 'picacomic'
          : 'go2778';
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
        children: isJm ? _buildJmSettings(context) : _buildPicacgSettings(),
      ),
    );
  }

  List<Widget> _buildJmSettings(BuildContext context) => <Widget>[
    _SectionLabel(label: '图床分流（${_shunts.length} 项）'),
    for (final shunt in _shunts)
      _ChoiceTile(
        key: ValueKey('jm-shunt-${shunt.key}'),
        title: shunt.title,
        subtitle: _shuntSubtitle(shunt),
        latency: _shuntSpeeds[shunt.key]?.latency,
        selected: _selectedShunt == shunt.key,
        selectedKey: _selectedShunt == shunt.key
            ? ValueKey('jm-shunt-selected-${shunt.key}')
            : null,
        busy: _selectingShunt == shunt.key,
        onTap: _testing || _selectingShunt != null
            ? null
            : () => _selectJmShunt(shunt.key),
      ),
    const SizedBox(height: AppSpacing.lg),
    FilledButton.icon(
      onPressed: _testing ? null : _testAll,
      icon: _testing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.speed_rounded, size: 18),
      label: Text(_testing ? '测速中…' : '开始测速'),
      style: FilledButton.styleFrom(
        backgroundColor: context.colorScheme.primary,
        minimumSize: const Size.fromHeight(48),
      ),
    ),
    const SizedBox(height: AppSpacing.lg),
    _SectionLabel(label: 'API 接入域名（${_domains.length} 个）'),
    for (final domain in _domains)
      _ChoiceTile(
        key: ValueKey('jm-domain-$domain'),
        title: domain,
        subtitle: _domainSubtitle(domain),
        latency: _domainSpeeds[domain],
        selected: _preferredDomain == domain,
        selectedKey: _preferredDomain == domain
            ? ValueKey('jm-domain-selected-$domain')
            : null,
        busy: false,
        onTap: _testing ? null : () => _selectDomain(domain),
      ),
  ];

  List<Widget> _buildPicacgSettings() => <Widget>[
    const _SectionLabel(label: 'API 接入域名'),
    _RadioTile(
      title: 'go2778 中转（默认）',
      subtitle: 'picaapi.go2778.com',
      selected: _picaDomain == 'go2778',
      selectedKey: _picaDomain == 'go2778'
          ? const Key('pica-domain-selected-go2778')
          : null,
      onTap: () => _setPicaDomain('go2778'),
    ),
    _RadioTile(
      title: 'picacomic 直连',
      subtitle: 'picaapi.picacomic.com',
      selected: _picaDomain == 'picacomic',
      selectedKey: _picaDomain == 'picacomic'
          ? const Key('pica-domain-selected-picacomic')
          : null,
      onTap: () => _setPicaDomain('picacomic'),
    ),
  ];

  String _shuntSubtitle(JmShunt shunt) {
    final host = _shuntSpeeds[shunt.key]?.imgHost ?? '';
    if (host.isNotEmpty) return host;
    if (_selectedShunt == shunt.key) {
      final current = _jmState?.imageBaseUrl ?? '';
      if (current.isNotEmpty) return _cleanDomain(current);
    }
    return '点击选择；测速后显示真实图床';
  }

  String _domainSubtitle(String domain) {
    if (_preferredDomain == domain) return '当前首选 API 域名';
    return _domainSpeeds.containsKey(domain) ? '最近测速结果' : '等待测速';
  }

  Future<void> _selectJmShunt(int key) async {
    setState(() => _selectingShunt = key);
    final selector = widget.selectShunt ?? JmNetwork().selectShunt;
    final success = await selector(key);
    if (!mounted) return;
    setState(() {
      _selectedShunt = _jmState?.selectedShuntKey ?? key;
      _selectingShunt = null;
    });
    if (!success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('线路已保存，但暂时无法获取图床地址')));
    }
  }

  Future<void> _testAll() async {
    setState(() => _testing = true);
    try {
      final shuntTester = widget.testShunts ?? JmNetwork().testAllShunts;
      final domainTester =
          widget.testDomain ?? JmNetwork().testApiDomainLatency;
      final results = await Future.wait<Object>(<Future<Object>>[
        shuntTester(_shunts),
        Future.wait<int>([for (final domain in _domains) domainTester(domain)]),
      ]);
      if (!mounted) return;
      final shuntResults = results[0] as List<JmShuntSpeed>;
      final domainResults = results[1] as List<int>;
      setState(() {
        _shuntSpeeds = <int, JmShuntSpeed>{
          for (final result in shuntResults) result.key: result,
        };
        _domainSpeeds = <String, int>{
          for (var index = 0; index < _domains.length; index++)
            _domains[index]: domainResults[index],
        };
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('测速失败：$error')));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _selectDomain(String domain) {
    final state = _jmState;
    if (state == null) return;
    state.setPreferredDomain(domain);
    state.setApiBaseUrl('https://$domain');
    setState(() => _preferredDomain = domain);
  }

  void _setPicaDomain(String domain) {
    final state = _picacgState;
    if (state == null) return;
    final url = domain == 'picacomic'
        ? 'https://picaapi.picacomic.com'
        : 'https://picaapi.go2778.com';
    state.setApiBaseUrl(url);
    setState(() => _picaDomain = domain);
  }
}

String _cleanDomain(String value) {
  final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  return uri?.host.isNotEmpty == true ? uri!.host : '';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: AppSpacing.sm,
      bottom: AppSpacing.xs,
      left: AppSpacing.xxs,
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.tertiaryTextColor,
      ),
    ),
  );
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.latency,
    required this.selected,
    required this.busy,
    required this.onTap,
    this.selectedKey,
  });

  final String title;
  final String subtitle;
  final int? latency;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;
  final Key? selectedKey;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: AppRadius.brMd,
    child: Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
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
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.primaryTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.tertiaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (latency != null)
            Text(
              latency! < 0 ? '失败' : '${latency}ms',
              style: TextStyle(
                fontSize: 12,
                color: latency! < 0
                    ? context.colorScheme.error
                    : latency! < 300
                    ? AppColors.success
                    : AppColors.hotAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            key: selectedKey,
            color: selected
                ? context.colorScheme.primary
                : context.tertiaryTextColor,
            size: 22,
          ),
        ],
      ),
    ),
  );
}

class _RadioTile extends StatelessWidget {
  const _RadioTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.selectedKey,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Key? selectedKey;

  @override
  Widget build(BuildContext context) => _ChoiceTile(
    title: title,
    subtitle: subtitle,
    latency: null,
    selected: selected,
    selectedKey: selectedKey,
    busy: false,
    onTap: onTap,
  );
}
