/// 阅读设置页，所有可用项均从 ReaderConf 初始化并即时持久化。
library reader_settings_page;

import 'package:flutter/material.dart';

import '../../foundation/reader_config.dart';
import '../../theme/app_colors.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('阅读设置'),
        backgroundColor: AppColors.background,
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
                  onTap: () {
                    _conf.readMode = item.$1;
                    setState(() => _mode = item.$1);
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
                onChanged: (value) {
                  _conf.enableGesture = value;
                  setState(() => _enableGesture = value);
                },
              ),
              _SwitchRow(
                switchKey: const Key('reader-page-animation'),
                icon: Icons.animation_rounded,
                title: '翻页动画',
                value: _enablePageAnimation,
                onChanged: (value) {
                  _conf.enablePageAnimation = value;
                  setState(() => _enablePageAnimation = value);
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
                onChanged: (index) {
                  final value = int.parse(_preloadOptions[index]);
                  _conf.preloadImageCount = value;
                  setState(() => _preload = value);
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
                onChanged: (value) {
                  _conf.showPageNumbers = value;
                  setState(() => _showPageNumbers = value);
                },
              ),
              _SwitchRow(
                switchKey: const Key('reader-auto-hide-toolbar'),
                icon: Icons.visibility_off_outlined,
                title: '工具栏自动隐藏',
                value: _autoHideToolbar,
                onChanged: (value) {
                  _conf.autoHideToolbar = value;
                  setState(() => _autoHideToolbar = value);
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
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textLow,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: AppColors.border),
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
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textHigh,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textLow,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              key: iconKey,
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.brandPink : AppColors.textLow,
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
          Icon(icon, size: 20, color: AppColors.brandPink),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, color: AppColors.textHigh),
            ),
          ),
          Switch.adaptive(
            key: switchKey,
            value: value,
            activeTrackColor: AppColors.brandPink,
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
            style: const TextStyle(fontSize: 15, color: AppColors.textHigh),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: i == selected
                            ? const LinearGradient(
                                colors: [
                                  AppColors.brandPink,
                                  AppColors.brandViolet,
                                ],
                              )
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        options[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: i == selected
                              ? Colors.white
                              : AppColors.textMedium,
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
