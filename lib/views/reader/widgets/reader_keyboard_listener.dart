/// 键盘快捷键监听（桌面端翻页支持）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 监听键盘事件并映射到对应的操作回调。
class ReaderKeyboardListener extends StatelessWidget {
  const ReaderKeyboardListener({
    super.key,
    required this.handlers,
    required this.child,
  });

  /// 键位 -> 回调映射。按下匹配键位时触发对应回调。
  final Map<LogicalKeyboardKey, VoidCallback> handlers;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: handlers.map(
        (key, callback) => MapEntry<ShortcutActivator, VoidCallback>(
          SingleActivator(key),
          callback,
        ),
      ),
      child: Focus(autofocus: true, child: child),
    );
  }
}
