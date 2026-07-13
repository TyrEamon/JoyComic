/// 菜单锁定按钮（浮动锁图标）。
library menu_lock;

import 'package:flutter/material.dart';

import '../providers/reader_provider.dart' hide ReaderImage;
import '../utils/reader_utils.dart';

/// 工具栏显示时出现的浮动锁按钮。
///
/// 锁定后滚动/翻页不会隐藏工具栏。有收起（图标）和展开（图标 + 说明文字）两种状态。
class MenuLock extends StatelessWidget {
  const MenuLock({super.key});

  @override
  Widget build(BuildContext context) {
    final showMenuLock = context.selector((p) => p.showMenuLock);
    final menuLockExpanded = context.selector((p) => p.menuLockExpanded);

    if (!showMenuLock) return const SizedBox.shrink();

    return Positioned(
      left: context.left + 16,
      bottom: context.bottom + 80,
      child: GestureDetector(
        onTap: () => context.reader.expandMenuLock(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => context.stateReader.toggleLockMenu(),
                child: Icon(
                  context.stateReader.lockMenu
                      ? Icons.lock
                      : Icons.lock_open,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              if (menuLockExpanded) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => context.reader.collapseMenuLock(),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
