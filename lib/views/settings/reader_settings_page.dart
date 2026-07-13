/// 阅读设置页。
///
/// 分组：
/// 1. 默认阅读模式（5 模式单选）：竖直连续 / 单页左→右 / 单页右→左 / 双页左→右 / 双页右→左
/// 2. 翻页方式：点击 / 滑动 / 音量键（iOS 不实现音量键，保留占位注释）
/// 3. 预加载：图片数（2/4/6/8）
/// 4. 显示：页码角标 / 工具栏自动隐藏
/// 5. 图片：质量（低/中/高/原图）
///
/// 功能集成说明：
/// - 全部读写 `ReaderConf.instance`（阶段2 已建，shared_preferences 持久化）。
/// - 5 阅读模式对应 read_mode.dart 的 ReadMode 枚举。
/// - 预加载数对齐 ImagePreloadController.maxPreloadCount（2~8）。
/// - 当前 mock，改动不落盘。
library reader_settings_page;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';

class ReaderSettingsPage extends StatefulWidget {
  const ReaderSettingsPage({super.key});

  @override
  State<ReaderSettingsPage> createState() => _ReaderSettingsPageState();
}

class _ReaderSettingsPageState extends State<ReaderSettingsPage> {
  int _mode = 0;
  int _preload = 4;
  bool _showPageNo = true;
  bool _autoHide = true;
  int _quality = 3;

  static const _modes = [
    ('竖直连续', '从上到下连续滚动'),
    ('单页 左→右', '逐页左右翻'),
    ('单页 右→左', '日漫反向翻'),
    ('双页 左→右', '并排双页'),
    ('双页 右→左', '并排双页反向'),
  ];

  static const _qualities = ['低', '中', '高', '原图'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('阅读设置'), backgroundColor: AppColors.background),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          _Group(title: '默认阅读模式', children: [
            for (var i = 0; i < _modes.length; i++)
              _RadioRow(
                title: _modes[i].$1,
                subtitle: _modes[i].$2,
                selected: _mode == i,
                onTap: () => setState(() => _mode = i),
              ),
          ]),
          _Group(title: '预加载', children: [
            _SegmentRow(
              label: '图片数',
              options: const ['2', '4', '6', '8'],
              selected: const ['2', '4', '6', '8'].indexOf('$_preload'),
              onChanged: (i) => setState(() => _preload = int.parse(const ['2', '4', '6', '8'][i])),
            ),
          ]),
          _Group(title: '显示', children: [
            _SwitchRow(
              icon: Icons.looks_rounded,
              title: '页码角标',
              value: _showPageNo,
              onChanged: (v) => setState(() => _showPageNo = v),
            ),
            _SwitchRow(
              icon: Icons.visibility_off_outlined,
              title: '工具栏自动隐藏',
              value: _autoHide,
              onChanged: (v) => setState(() => _autoHide = v),
            ),
          ]),
          _Group(title: '图片质量', children: [
            _SegmentRow(
              label: '清晰度',
              options: _qualities,
              selected: _quality,
              onChanged: (i) => setState(() => _quality = i),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              '提示：音量键翻页在 iOS 上不实现（无拦截能力）。',
              style: const TextStyle(fontSize: 11, color: AppColors.textLow),
            ),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textHigh)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textLow)),
                ],
              ),
            ),
            Icon(
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
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.brandPink),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(title,
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

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  final String label;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 15, color: AppColors.textHigh)),
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
                    onTap: () => onChanged(i),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: i == selected
                            ? const LinearGradient(
                                colors: [AppColors.brandPink, AppColors.brandViolet])
                            : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(options[i],
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: i == selected ? Colors.white : AppColors.textMedium)),
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
