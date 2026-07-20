/// 简介组件（Synopsis Block）。
///
/// - 顶部小标题"简介"
/// - 多行文本框，默认折叠到 [maxLinesWhenCollapsed]
/// - 右侧独立"展开/收起"控件，不遮挡正文
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';

class SynopsisBlock extends StatefulWidget {
  const SynopsisBlock({
    super.key,
    required this.text,
    this.maxLinesWhenCollapsed = 3,
  });

  final String? text;
  final int maxLinesWhenCollapsed;

  /// Width reserved on the right for the expand/collapse control.
  static const double toggleLaneWidth = 56;

  @override
  State<SynopsisBlock> createState() => _SynopsisBlockState();
}

class _SynopsisBlockState extends State<SynopsisBlock>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  bool? _overflows; // null = 未测量

  @override
  Widget build(BuildContext context) {
    final text = (widget.text ?? '').trim();
    final accent = context.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('简介', style: AppTypography.section(context)),
          const SizedBox(height: AppSpacing.sm),
          _buildBody(context, text, accent),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, String text, Color accent) {
    final empty = text.isEmpty;
    if (empty) {
      return Text('暂无简介', style: AppTypography.body(context));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _measureOverflowIfNeeded(context, constraints, text);
        final showToggle = _overflows == true;
        final toggleLane = showToggle ? SynopsisBlock.toggleLaneWidth : 0.0;

        if (_expanded) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(text, style: AppTypography.body(context)),
              if (showToggle)
                Align(
                  alignment: Alignment.centerRight,
                  child: _ToggleLink(
                    expanded: true,
                    accent: accent,
                    onTap: () => setState(() => _expanded = false),
                  ),
                ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topLeft,
                child: Text(
                  text,
                  style: AppTypography.body(context),
                  maxLines: widget.maxLinesWhenCollapsed,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (showToggle) ...[
              SizedBox(width: toggleLane > 0 ? 4 : 0),
              _ToggleLink(
                expanded: false,
                accent: accent,
                onTap: () => setState(() => _expanded = true),
              ),
            ],
          ],
        );
      },
    );
  }

  void _measureOverflowIfNeeded(
    BuildContext context,
    BoxConstraints constraints,
    String text,
  ) {
    if (_overflows != null) return;
    // Measure against full width first; if it overflows three lines even
    // without the toggle lane, show the control. Re-measure with lane width
    // subtracted so short-but-wide text is not mis-flagged.
    final style = AppTypography.body(context);
    final full = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: widget.maxLinesWhenCollapsed,
    )..layout(maxWidth: constraints.maxWidth);
    final withLane = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: widget.maxLinesWhenCollapsed,
    )..layout(
      maxWidth: (constraints.maxWidth - SynopsisBlock.toggleLaneWidth)
          .clamp(0.0, constraints.maxWidth),
    );
    final overflow = full.didExceedMaxLines || withLane.didExceedMaxLines;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _overflows == overflow) return;
      setState(() => _overflows = overflow);
    });
  }
}

class _ToggleLink extends StatelessWidget {
  const _ToggleLink({
    required this.expanded,
    required this.accent,
    required this.onTap,
  });

  final bool expanded;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: expanded ? '收起简介' : '展开简介',
      child: Material(
        key: const ValueKey('synopsis-toggle'),
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  expanded ? '收起' : '展开',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
