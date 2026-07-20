/// 简介组件（Synopsis Block）。
///
/// - 顶部小标题"简介"
/// - 多行文本框，默认折叠到 [maxLinesWhenCollapsed]
/// - 右下角"展开/收起"文字切换按钮
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
        return Stack(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: Text(
                text,
                style: AppTypography.body(context),
                maxLines: _expanded ? null : widget.maxLinesWhenCollapsed,
                overflow: _expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
            ),
            if (_overflows == true)
              Positioned(
                right: 0,
                bottom: 0,
                child: _ToggleLink(
                  expanded: _expanded,
                  accent: accent,
                  onTap: () => setState(() => _expanded = !_expanded),
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
    final tp = TextPainter(
      text: TextSpan(text: text, style: AppTypography.body(context)),
      textDirection: TextDirection.ltr,
      maxLines: widget.maxLinesWhenCollapsed,
    )..layout(maxWidth: constraints.maxWidth);
    final overflow = tp.didExceedMaxLines;
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
    return Container(
      padding: const EdgeInsets.only(left: 24),
      color: context.pageBackground,
      child: Semantics(
        button: true,
        label: expanded ? '收起简介' : '展开简介',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
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
    );
  }
}
