/// 阅读设置页，所有可用项均从 ReaderConf 初始化并即时持久化。
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../foundation/reader_config.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../reader/state/read_mode.dart';

class ReaderSettingsPage extends StatefulWidget {
  const ReaderSettingsPage({super.key});

  @override
  State<ReaderSettingsPage> createState() => _ReaderSettingsPageState();
}

class _ReaderSettingsPageState extends State<ReaderSettingsPage> {
  late ReadMode _mode;
  late int _preload;
  late bool _enableGesture;
  late bool _enablePageAnimation;
  late bool _showPageNumbers;
  late bool _autoHideToolbar;

  static const _modes = [
    (ReadMode.vertical, '竖直连续', '从上到下连续滚动'),
    (ReadMode.leftToRight, '单页 左→右', '逐页左右翻'),
    (ReadMode.rightToLeft, '单页 右→左', '日漫反向翻'),
    (ReadMode.doubleLeftToRight, '双页 左→右', '并排双页'),
    (ReadMode.doubleRightToLeft, '双页 右→左', '并排双页反向'),
  ];
  static const _preloadOptions = ['2', '4', '6', '8'];

  ReaderConf get _conf => ReaderConf.instance;

  @override
  void initState() {
    super.initState();
    _mode = _conf.readMode;
    _preload = _conf.preloadImageCount;
    _enableGesture = _conf.enableGesture;
    _enablePageAnimation = _conf.enablePageAnimation;
    _showPageNumbers = _conf.showPageNumbers;
    _autoHideToolbar = _conf.autoHideToolbar;
  }

  Future<void> _persist(VoidCallback write, VoidCallback update) async {
    write();
    final persisted = await _conf.flushPendingWrites();
    if (!mounted || !persisted) return;
    setState(update);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text('阅读设置'),
        backgroundColor: context.pageBackground,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          _Group(
            title: '默认阅读模式',
            children: [
              for (final item in _modes)
                _RadioRow(
                  title: item.$2,
                  subtitle: item.$3,
                  selected: _mode == item.$1,
                  iconKey: Key('reader-mode-${item.$1.name}'),
                  onTap: () async {
                    await _persist(
                      () => _conf.readMode = item.$1,
                      () => _mode = item.$1,
                    );
                  },
                ),
            ],
          ),
          _Group(
            title: '翻页',
            children: [
              _SwitchRow(
                switchKey: const Key('reader-enable-gesture'),
                icon: Icons.swipe_rounded,
                title: '手势翻页',
                value: _enableGesture,
                onChanged: (value) async {
                  await _persist(
                    () => _conf.enableGesture = value,
                    () => _enableGesture = value,
                  );
                },
              ),
              _SwitchRow(
                switchKey: const Key('reader-page-animation'),
                icon: Icons.animation_rounded,
                title: '翻页动画',
                value: _enablePageAnimation,
                onChanged: (value) async {
                  await _persist(
                    () => _conf.enablePageAnimation = value,
                    () => _enablePageAnimation = value,
                  );
                },
              ),
            ],
          ),
          _Group(
            title: '预加载',
            children: [
              _SegmentRow(
                label: '图片数',
                options: _preloadOptions,
                selected: _preloadOptions.indexOf('$_preload'),
                keyPrefix: 'reader-preload',
                onChanged: (index) async {
                  final value = int.parse(_preloadOptions[index]);
                  await _persist(
                    () => _conf.preloadImageCount = value,
                    () => _preload = value,
                  );
                },
              ),
            ],
          ),
          _Group(
            title: '显示',
            children: [
              _SwitchRow(
                switchKey: const Key('reader-show-page-numbers'),
                icon: Icons.looks_rounded,
                title: '页码角标',
                value: _showPageNumbers,
                onChanged: (value) async {
                  await _persist(
                    () => _conf.showPageNumbers = value,
                    () => _showPageNumbers = value,
                  );
                },
              ),
              _SwitchRow(
                switchKey: const Key('reader-auto-hide-toolbar'),
                icon: Icons.visibility_off_outlined,
                title: '工具栏自动隐藏',
                value: _autoHideToolbar,
                onChanged: (value) async {
                  await _persist(
                    () => _conf.autoHideToolbar = value,
                    () => _autoHideToolbar = value,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

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
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.iconKey,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final Key iconKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
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
                      fontWeight: FontWeight.w500,
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
            Icon(
              key: iconKey,
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
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
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.switchKey,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.colorScheme.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 15, color: context.primaryTextColor),
            ),
          ),
          Switch.adaptive(
            key: switchKey,
            value: value,
            activeTrackColor: context.colorScheme.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.keyPrefix,
    required this.onChanged,
  });

  final String label;
  final List<String> options;
  final int selected;
  final String keyPrefix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 15, color: context.primaryTextColor),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: context.elevatedSurfaceColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < options.length; i++)
                  InkWell(
                    key: Key('$keyPrefix-${options[i]}'),
                    onTap: () => onChanged(i),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      key: Key('$keyPrefix-container-${options[i]}'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: i == selected
                            ? context.colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        options[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: i == selected
                              ? context.colorScheme.onPrimaryContainer
                              : context.secondaryTextColor,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
