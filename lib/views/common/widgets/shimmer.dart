/// 骨架屏 Shimmer 动画组件。
///
/// 包裹在占位容器外层，从左到右扫过一道微光，形成"加载中"的视觉暗示。
/// 配合 [LoadingGrid] 使用，覆盖列表/首页/搜索结果/收藏等页的首屏加载。
library shimmer;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// 带 shimmer 微光扫动效果的骨架块。
///
/// 用法：用 [Shimmer] 包裹加载中的占位 widget，
/// 子 widget 内部用 [AppColors.surfaceElevated] 等纯色块占位。
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1500),
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration duration;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(); // 无限循环扫动
    _animation = Tween<double>(begin: -1, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseColor ?? AppColors.surfaceElevated;
    final highlight = widget.highlightColor ??
        base.withValues(alpha: 0.3);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                base,
                base,
                highlight,
                base,
                base,
              ],
              stops: [
                0.0,
                _animation.value - 0.3,
                _animation.value,
                _animation.value + 0.3,
                1.0,
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
