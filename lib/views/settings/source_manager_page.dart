import 'package:flutter/material.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/app_data.dart';
import '../../foundation/source_session_notifier.dart';
import '../../theme/app_safe_area.dart';
import '../../theme/app_spacing.dart';

class SourceManagerPage extends StatefulWidget {
  const SourceManagerPage({super.key});

  @override
  State<SourceManagerPage> createState() => _SourceManagerPageState();
}

class _SourceManagerPageState extends State<SourceManagerPage> {
  late Set<String> _enabled = AppData.instance.enabledSources;
  late List<String> _order = AppData.instance.sourceOrder;
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
      final persisted = await AppData.instance.setEnabledSources(next);
      if (!persisted) throw StateError('源设置保存失败');
      await ComicSource.reload(_orderedEnabled(next));
      if (!mounted) return;
      setState(() => _enabled = next);
      SourceSessionNotifier.instance.notifyConfigurationChanged();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新漫画源失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<String> _orderedEnabled(Set<String> enabled) => _order
      .where(enabled.contains)
      .toList(growable: false);

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (_saving) return;
    if (oldIndex == newIndex) return;

    final previous = List<String>.of(_order);
    final next = List<String>.of(_order);
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    setState(() {
      _order = next;
      _saving = true;
    });
    try {
      final persisted = await AppData.instance.setSourceOrder(next);
      if (!persisted) throw StateError('源顺序保存失败');
      ComicSource.reorder(_orderedEnabled(_enabled));
      SourceSessionNotifier.instance.notifyConfigurationChanged();
    } catch (error) {
      if (!mounted) return;
      setState(() => _order = previous);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('调整源顺序失败：$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? firstEnabled;
    for (final key in _order) {
      if (_enabled.contains(key)) {
        firstEnabled = key;
        break;
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('源管理')),
      body: Column(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Text('拖动左侧图标可调整顺序。排在最前的已启用源会优先显示在首页；源开关与登录状态相互独立。'),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: EdgeInsets.only(bottom: bottomContentInset(context)),
              buildDefaultDragHandles: false,
              itemCount: _order.length,
              onReorderItem: _reorder,
              itemBuilder: (context, index) {
                final key = _order[index];
                final name = _sourceNames[key] ?? key;
                final enabled = _enabled.contains(key);
                return SwitchListTile(
                  key: ValueKey<String>('source-manager-$key'),
                  secondary: ReorderableDragStartListener(
                    index: index,
                    enabled: !_saving,
                    child: const SizedBox.square(
                      dimension: 48,
                      child: Icon(Icons.drag_handle_rounded),
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text(
                    enabled
                        ? key == firstEnabled
                              ? '已启用 · 首页优先'
                              : '已启用'
                        : '未启用',
                  ),
                  value: enabled,
                  onChanged: _saving ? null : (value) => _toggle(key, value),
                );
              },
            ),
          ),
          if (_saving)
            const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}
