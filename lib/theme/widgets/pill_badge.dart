/// Flat semantic pill badge.
library;

import 'package:flutter/material.dart';

import '../app_radius.dart';
import '../app_spacing.dart';
import '../app_theme_context.dart';

class PillBadge extends StatelessWidget {
  const PillBadge({
    super.key,
    required this.label,
    this.leadingDotColor,
    this.backgroundColor,
    this.foregroundColor,
    this.style,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  });

  final String label;
  final Color? leadingDotColor;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final background = backgroundColor ?? context.colorScheme.primaryContainer;
    final foreground =
        foregroundColor ?? context.colorScheme.onPrimaryContainer;
    final textStyle =
        (style ??
                const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ))
            .copyWith(color: style?.color ?? foreground);

    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        key: const Key('pill-badge-decoration'),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.pill(padding.vertical + 14),
          border: Border.all(color: context.borderColor),
        ),
        child: Padding(
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingDotColor != null) ...[
                _Dot(color: leadingDotColor!),
                const SizedBox(width: AppSpacing.xxs),
              ],
              Text(label, style: textStyle),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
