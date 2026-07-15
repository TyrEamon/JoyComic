/// Theme-aware five-star rating widget.
library;

import 'dart:math' show cos, pi, sin;

import 'package:flutter/material.dart';

import '../../../theme/app_theme_context.dart';

class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.size = 14,
    this.color,
    this.spacing = 2,
    this.maxStars = 5,
  });

  final double rating;
  final double size;
  final Color? color;
  final double spacing;
  final int maxStars;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? context.ratingColor;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxStars, (i) {
        final value = rating - i;
        final fill = value >= 1 ? 1.0 : (value > 0 ? value : 0.0);
        return Padding(
          padding: EdgeInsets.only(right: i == maxStars - 1 ? 0 : spacing),
          child: _Star(size: size, color: resolvedColor, fill: fill),
        );
      }),
    );
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.size, required this.color, required this.fill});

  final double size;
  final Color color;
  final double fill;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StarPainter(color: color, fill: fill),
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter({required this.color, required this.fill});

  final Color color;
  final double fill;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _starPath(size);
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
    if (fill <= 0) return;
    canvas
      ..save()
      ..clipPath(path)
      ..drawRect(
        Rect.fromLTWH(0, 0, size.width * fill, size.height),
        Paint()..color = color,
      )
      ..restore();
  }

  Path _starPath(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2;
    final inner = outer * 0.42;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -pi / 2 + i * pi / 5;
      final point = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.fill != fill;
}
