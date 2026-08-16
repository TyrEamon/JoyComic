/// Reader bottom control overlay.
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_gradients.dart';
import '../providers/list_state_provider.dart';
import '../providers/reader_provider.dart' hide ReaderImage;
import '../state/read_mode.dart';
import '../utils/reader_utils.dart';

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
    final lockMenu = context.stateSelector((p) => p.lockMenu);
    final foreground = context.semanticColors.readerControlForeground;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      bottom: showToolbar ? 0 : -200,
      left: 0,
      right: 0,
      child: Container(
        key: const Key('reader-bottom-scrim'),
        padding: EdgeInsets.fromLTRB(16, 8, 16, context.bottom + 8),
        decoration: BoxDecoration(
          gradient: AppGradients.readerScrimBottom(context.semanticColors),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  '${pageNo + 1}',
                  style: TextStyle(color: foreground, fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: pageNo.toDouble(),
                    min: 0,
                    max: (pageCount - 1).clamp(0, double.infinity).toDouble(),
                    divisions: pageCount > 1 ? pageCount - 1 : null,
                    activeColor: foreground,
                    inactiveColor: foreground.withValues(alpha: 0.3),
                    onChanged: (value) =>
                        context.reader.onSliderChanged(value.round()),
                  ),
                ),
                Text(
                  '$pageCount',
                  style: TextStyle(color: foreground, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
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
                  onTap: () => isPageTurning
                      ? context.reader.stopPageTurn()
                      : context.reader.startPageTurn(),
                ),
                _ActionButton(
                  icon: Icons.menu,
                  tooltip: '章节列表',
                  onTap: () => Scaffold.of(context).openDrawer(),
                ),
                _ActionButton(
                  icon: lockMenu ? Icons.lock : Icons.lock_open,
                  tooltip: lockMenu ? '解锁工具栏' : '锁定工具栏',
                  onTap: () => context.stateReader.toggleLockMenu(),
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
      builder: (sheetContext) => SafeArea(
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
                Navigator.pop(sheetContext);
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
      icon: Icon(icon, color: context.semanticColors.readerControlForeground),
      tooltip: tooltip,
      onPressed: onTap,
    );
  }
}
