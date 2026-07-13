/// 阅读器底部工具栏。
library bottom;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../providers/reader_provider.dart' hide ReaderImage;
import '../providers/list_state_provider.dart';
import '../state/read_mode.dart';
import '../utils/reader_utils.dart';

/// 阅读器底部工具栏：页码滑块、阅读模式切换、设置入口、自动翻页开关。
class ReaderBottom extends StatefulWidget {
  const ReaderBottom({super.key});

  @override
  State<ReaderBottom> createState() => _ReaderBottomState();
}

class _ReaderBottomState extends State<ReaderBottom> {
  @override
  Widget build(BuildContext context) {
    final showToolbar = context.selector((p) => p.showToolbar);
    final pageNo = context.selector((p) => p.pageNo);
    final pageCount = context.selector((p) => p.pageCount);
    final readMode = context.selector((p) => p.readMode);
    final isPageTurning = context.selector((p) => p.isPageTurning);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      bottom: showToolbar ? 0 : -200,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          context.bottom + 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 页码滑块区域
            Row(
              children: [
                Text(
                  '${pageNo + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: pageNo.toDouble(),
                    min: 0,
                    max: (pageCount - 1).clamp(0, double.infinity),
                    divisions: pageCount > 1 ? pageCount - 1 : null,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                    onChanged: (value) {
                      context.reader.onSliderChanged(value.round());
                    },
                  ),
                ),
                Text(
                  '$pageCount',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 操作按钮行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  icon: Icons.grid_view_rounded,
                  tooltip: '阅读模式',
                  onTap: () => _showReadModePicker(context, readMode),
                ),
                _ActionButton(
                  icon: isPageTurning ? Icons.pause : Icons.play_arrow,
                  tooltip: isPageTurning ? '停止自动翻页' : '自动翻页',
                  onTap: () {
                    if (isPageTurning) {
                      context.reader.stopPageTurn();
                    } else {
                      context.reader.startPageTurn();
                    }
                  },
                ),
                _ActionButton(
                  icon: Icons.menu,
                  tooltip: '章节列表',
                  onTap: () => Scaffold.of(context).openDrawer(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showReadModePicker(BuildContext context, ReadMode current) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ReadMode.values.map((mode) {
            return ListTile(
              leading: Icon(
                mode.isVertical
                    ? Icons.vertical_align_bottom
                    : mode.isDoublePage
                        ? Icons.view_column
                        : Icons.chevron_right,
              ),
              title: Text(mode.displayName),
              trailing: mode == current ? const Icon(Icons.check) : null,
              onTap: () {
                context.reader.readMode = mode;
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: Colors.white),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}
