/// 通用：五星评分图形组件。
///
/// 支持 0~5 任意分值（含半星），[color] 默认品牌金星色，
/// 详情页可注入封面取色 accent 用作星级强调。
library;

import 'dart:math' show pi, cos, sin;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.size = 14,
    this.color = AppColors.ratingStar,
    this.spacing = 2,
    this.maxStars = 5,
  });

  /// 0~5 之间的评分值。
  final double rating;

  final double size;
  final Color color;
  final double spacing;
  final int maxStars;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(maxStars, (i) {
        final v = rating - i;
        final filled = v >= 1;
        final half = v > 0 && v < 1;
        return Padding(
          padding: EdgeInsets.only(right: i == maxStars - 1 ? 0 : spacing),
          child: _Star(
            size: size,
            color: color,
            fill: filled ? 1.0 : (half ? v : 0.0),
          ),
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
  final double fill; // 0~1

  @override
  void paint(Canvas canvas, Size size) {
    final path = _starPath(size);

    // 背景（空星）。
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));

    // 前景（按 fill 比例裁剪）。
    if (fill > 0) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * fill, size.height),
        Paint()..color = color,
      );
      canvas.restore();
    }
  }

  Path _starPath(Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final outer = w / 2;
    final inner = outer * 0.42;
    const points = 5;
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final r = i.isEven ? outer : inner;
      final angle = -pi / 2 + i * pi / points;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_StarPainter old) =>
      old.color != color || old.fill != fill;
}
