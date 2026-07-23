import 'package:flutter/material.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/app_data.dart';
import '../../theme/app_safe_area.dart';
import '../../theme/app_spacing.dart';

class SourceManagerPage extends StatefulWidget {
  const SourceManagerPage({super.key});

  @override
  State<SourceManagerPage> createState() => _SourceManagerPageState();
}

class _SourceManagerPageState extends State<SourceManagerPage> {
  late Set<String> _enabled = AppData.instance.enabledSources;
  bool _saving = false;

  static const _sourceNames = <String, String>{'jm': '禁漫', 'picacg': '哔咔'};

  Future<void> _toggle(String key, bool enabled) async {
    if (_saving) return;
    final next = Set<String>.of(_enabled);
    enabled ? next.add(key) : next.remove(key);
    if (next.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('至少保留一个漫画源')));
      return;
    }

    setState(() => _saving = true);
    try {
      final persisted = await AppData.instance.prefs.setStringList(
        'enabledSources',
        next.toList(growable: false),
      );
      if (!persisted) throw StateError('源设置保存失败');
      await ComicSource.reload(next);
      if (!mounted) return;
      setState(() => _enabled = next);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新漫画源失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = ComicSource.builtInMap.keys.toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: const Text('源管理')),
      body: ListView(
        padding: EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: bottomContentInset(context),
        ),
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Text('选择要在首页、分类、搜索和账号区域中启用的漫画源。源选择与登录状态相互独立。'),
          ),
          for (final key in keys)
            SwitchListTile(
              key: ValueKey<String>('source-manager-$key'),
              title: Text(_sourceNames[key] ?? key),
              subtitle: Text(_enabled.contains(key) ? '已启用' : '未启用'),
              value: _enabled.contains(key),
              onChanged: _saving ? null : (value) => _toggle(key, value),
            ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
