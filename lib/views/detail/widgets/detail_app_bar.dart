/// Detail page navigation bar with collapse title and share action.
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_gradients.dart';
import '../../../theme/app_typography.dart';

class DetailAppBar extends StatelessWidget {
  const DetailAppBar({
    super.key,
    this.title,
    this.scrolledUnder = false,
    this.onBack,
    this.onShare,
    this.onMore,
  });

  final String? title;
  final bool scrolledUnder;
  final VoidCallback? onBack;
  final VoidCallback? onShare;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: _Bar(
          title: title,
          scrolledUnder: scrolledUnder,
          onBack: onBack,
          onShare: onShare,
          onMore: onMore,
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.title,
    required this.scrolledUnder,
    required this.onBack,
    required this.onShare,
    required this.onMore,
  });

  final String? title;
  final bool scrolledUnder;
  final VoidCallback? onBack;
  final VoidCallback? onShare;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final foreground = scrolledUnder
        ? context.primaryTextColor
        : context.onImageColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: scrolledUnder ? context.pageBackground : Colors.transparent,
        gradient: scrolledUnder
            ? null
            : AppGradients.imageScrimTop(context.semanticColors),
        border: scrolledUnder
            ? Border(bottom: BorderSide(color: context.borderColor))
            : null,
      ),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _IconBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: '返回',
            foreground: foreground,
            softBackground: !scrolledUnder,
            onTap: onBack,
          ),
          if (scrolledUnder)
            Expanded(
              child: Text(
                title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.section(
                  context,
                ).copyWith(color: foreground, fontSize: 16),
              ),
            )
          else
            const Spacer(),
          _IconBtn(
            icon: Icons.ios_share_rounded,
            tooltip: '分享',
            foreground: foreground,
            softBackground: !scrolledUnder,
            onTap: onShare,
          ),
          _IconBtn(
            icon: Icons.more_horiz_rounded,
            tooltip: '更多',
            foreground: foreground,
            softBackground: !scrolledUnder,
            onTap: onMore,
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.foreground,
    required this.softBackground,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color foreground;
  final bool softBackground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: softBackground
              ? context.semanticColors.imageScrimSoft
              : Colors.transparent,
          foregroundColor: foreground,
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }
}
