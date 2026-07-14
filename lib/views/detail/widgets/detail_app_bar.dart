/// 详情页导航栏（常驻最顶层，完全透明）。
///
/// 左：返回 Icon；右：分享 + 更多操作 Icon 组合。
/// 滚动时顶部叠加一层渐变（深色从透明到微实），保证白图标在亮封面上可读。
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

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
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: scrolledUnder
              ? [
                  context.pageBackground,
                  context.pageBackground.withValues(alpha: 0.0),
                ]
              : [const Color(0x66000000), const Color(0x00000000)],
        ),
      ),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _IconBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack),
          const Spacer(),
          _IconBtn(icon: Icons.ios_share_rounded, onTap: onShare),
          _IconBtn(icon: Icons.more_horiz_rounded, onTap: onMore),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: Color(0x33000000),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}
