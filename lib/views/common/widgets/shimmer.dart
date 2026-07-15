/// Theme-aware neutral shimmer animation.
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_gradients.dart';
import 'package:joycomic/theme/app_theme_context.dart';

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

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
    _animation = Tween<double>(begin: -1, end: 1).animate(
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
    final colors = context.semanticColors.copyWith(
      shimmerBase: widget.baseColor,
      shimmerHighlight: widget.highlightColor,
    );
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => ShaderMask(
        shaderCallback: (bounds) => AppGradients.shimmer(
          colors,
          begin: Alignment(_animation.value - 1, 0),
          end: Alignment(_animation.value + 1, 0),
        ).createShader(bounds),
        blendMode: BlendMode.srcATop,
        child: child,
      ),
      child: widget.child,
    );
  }
}
