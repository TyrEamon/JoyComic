/// 详情页导航栏（常驻最顶层，完全透明）。
///
/// 左：返回 Icon；右：分享 + 更多操作 Icon 组合。
/// 滚动时顶部叠加一层渐变（深色从透明到微实），保证白图标在亮封面上可读。
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_gradients.dart';

class DetailAppBar extends StatelessWidget {
  const DetailAppBar({
    super.key,
    this.scrolledUnder = false,
    this.onBack,
    this.onShare,
    this.onMore,
  });

  /// 是否处于"滚动到内容区"状态，影响底色。
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
    required this.scrolledUnder,
    required this.onBack,
    required this.onShare,
    required this.onMore,
  });
  final bool scrolledUnder;
  final VoidCallback? onBack;
  final VoidCallback? onShare;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: scrolledUnder ? context.pageBackground : Colors.transparent,
        gradient: scrolledUnder
            ? null
            : AppGradients.imageScrimTop(context.semanticColors),
      ),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _IconBtn(
            icon: Icons.arrow_back_ios_new_rounded,
            tooltip: '返回',
            onTap: onBack,
          ),
          const Spacer(),
          _IconBtn(
            icon: Icons.ios_share_rounded,
            tooltip: '分享',
            onTap: onShare,
          ),
          _IconBtn(
            icon: Icons.more_horiz_rounded,
            tooltip: '更多',
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
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
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
          backgroundColor: context.semanticColors.imageScrimSoft,
          foregroundColor: context.onImageColor,
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }
}
