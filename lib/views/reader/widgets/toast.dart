import 'dart:async';
import 'package:flutter/material.dart';

import '../utils/reader_utils.dart';

/// 应用级 navigator key 持有者。
///
/// 由 main 在 MaterialApp 构造时传入并被这里登记，使 [Toast] 这类无
/// [BuildContext] 的全局提示可拿到 overlay。阶段3 主框架成型后由
/// `MaterialApp(navigatorKey: Toast.navKey, ...)` 注入。
final navKey = GlobalKey<NavigatorState>();

enum ToastPosition { top, center, bottom }

/// 轻量全局提示（不依赖 ScaffoldMessenger）。
///
/// 经 [navKey] 取 overlay 挂载，无需 BuildContext 即可弹出。用于章节边界、
/// 菜单锁定等瞬时提示。
class Toast {
  static OverlayEntry? _overlayEntry;
  static Timer? _timer;
  static bool _isVisible = false;

  static void show({
    required String message,
    Duration duration = const Duration(seconds: 2),
    ToastPosition position = ToastPosition.bottom,
    Color? backgroundColor,
    TextStyle? textStyle,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 8,
    ),
    BorderRadiusGeometry borderRadius = const BorderRadius.all(
      Radius.circular(8),
    ),
    bool dismissOther = true,
  }) {
    if (dismissOther) {
      _dismiss();
    }

    _overlayEntry = OverlayEntry(
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return _ToastWidget(
          message: message,
          position: position,
          backgroundColor: backgroundColor ?? scheme.inverseSurface,
          textStyle:
              textStyle ??
              TextStyle(color: scheme.onInverseSurface, fontSize: 14),
          padding: padding,
          borderRadius: borderRadius,
        );
      },
    );

    _insertOverlay();
    _startTimer(duration);
  }

  static void _insertOverlay() {
    if (_overlayEntry == null) return;

    final overlay = navKey.currentState?.overlay;
    if (overlay != null && !_isVisible) {
      overlay.insert(_overlayEntry!);
      _isVisible = true;
    }
  }

  static void _startTimer(Duration duration) {
    _timer?.cancel();
    _timer = Timer(duration, _dismiss);
  }

  static void _dismiss() {
    if (!_isVisible) return;

    _timer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isVisible = false;
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastPosition position;
  final Color backgroundColor;
  final TextStyle textStyle;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;

  const _ToastWidget({
    required this.message,
    required this.position,
    required this.backgroundColor,
    required this.textStyle,
    required this.padding,
    required this.borderRadius,
  });

  @override
  _ToastWidgetState createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _opacityAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _getPosition() {
    return switch (widget.position) {
      ToastPosition.top => 50,
      ToastPosition.center => context.height / 2,
      ToastPosition.bottom => context.height - 100,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: _getPosition(),
      width: context.width,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Opacity(
            opacity: _opacityAnimation.value,
            child: Material(
              color: Colors.transparent,
              child: Container(
                alignment: Alignment.center,
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.backgroundColor,
                    borderRadius: widget.borderRadius,
                  ),
                  padding: widget.padding,
                  child: Text(
                    widget.message,
                    style: widget.textStyle,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
