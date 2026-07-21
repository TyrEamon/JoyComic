/// 简介组件（Synopsis Block）。
///
/// - 顶部小标题"简介"
/// - 默认折叠到 [maxLinesWhenCollapsed]
/// - 折叠态"展开"贴在正文末行右侧，正文占满整行宽度，不单独占宽列
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

  /// Visual width of the expand label (gradient fade covers a bit more).
  static const double toggleVisualWidth = 36;

  /// Hit-target size for accessibility (does not reserve a full side column).
  static const double toggleHitSize = 44;

  @override
  State<SynopsisBlock> createState() => _SynopsisBlockState();
}

class _SynopsisBlockState extends State<SynopsisBlock> {
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
    if (text.isEmpty) {
      return Text('暂无简介', style: AppTypography.body(context));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _measureOverflowIfNeeded(context, constraints, text);
        final showToggle = _overflows == true;
        final surface = context.pageBackground;

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

        // Full-width body; expand sits on the last line's trailing edge with a
        // short fade so prose uses almost the entire row.
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Text(
              text,
              style: AppTypography.body(context),
              maxLines: widget.maxLinesWhenCollapsed,
              overflow: TextOverflow.ellipsis,
            ),
            if (showToggle)
              Positioned(
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: <Color>[
                        surface.withValues(alpha: 0),
                        surface.withValues(alpha: 0.92),
                        surface,
                      ],
                      stops: const <double>[0, 0.35, 0.55],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: _ToggleLink(
                      expanded: false,
                      accent: accent,
                      onTap: () => setState(() => _expanded = true),
                    ),
                  ),
                ),
              ),
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
    final style = AppTypography.body(context);
    // Full width: toggle overlays the trailing edge and does not carve a column.
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: widget.maxLinesWhenCollapsed,
    )..layout(maxWidth: constraints.maxWidth);
    final overflow = painter.didExceedMaxLines;
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
            constraints: const BoxConstraints(
              minWidth: SynopsisBlock.toggleHitSize,
              minHeight: SynopsisBlock.toggleHitSize,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                expanded ? '收起' : '展开',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accent,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
