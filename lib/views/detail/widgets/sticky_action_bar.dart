/// 全局悬浮底栏（Sticky Bottom Action Bar）。
///
/// 页面底部常驻，不随滚动消失。双按钮：
/// - 次级（收藏）：较窄，心形 Icon + 状态文字，轻量化卡片
/// - 主行动（阅读）：较宽，高亮品牌色圆角长胶囊，主标题 + 提示副文本
///   主按钮渐变跟随封面取色 [palette]（取色失败即静态品牌色）。
library sticky_action_bar;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../foundation/palette_extractor.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_shadows.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';

class StickyActionBar extends StatelessWidget {
  const StickyActionBar({
    super.key,
    required this.isFavorite,
    required this.readHint,
    required this.palette,
    required this.onFavorite,
    required this.onRead,
  });

  final bool isFavorite;
  final String readHint;
  final ComicPalette palette;
  final VoidCallback onFavorite;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.pageBackground.withValues(alpha: 0.94),
          border: Border(top: BorderSide(color: context.borderColor)),
          boxShadow: AppShadows.actionBar,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                _FavoriteButton(isFavorite: isFavorite, onTap: onFavorite),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ReadButton(
                    hint: readHint,
                    palette: palette,
                    onTap: onRead,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.isFavorite, required this.onTap});
  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isFavorite ? AppColors.hotAccent : context.secondaryTextColor;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: context.elevatedSurfaceColor,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              size: 20,
              color: color,
            ),
            const SizedBox(height: 3),
            Text(
              isFavorite ? '已收藏' : '收藏',
              style: AppTypography.buttonSecondary(
                context,
              ).copyWith(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadButton extends StatelessWidget {
  const _ReadButton({
    required this.hint,
    required this.palette,
    required this.onTap,
  });
  final String hint;
  final ComicPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: palette.gradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: palette.accent.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.menu_book_rounded, size: 20, color: Colors.white),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('开始阅读', style: AppTypography.buttonMainTitle),
                if (hint.isNotEmpty)
                  Text(hint, style: AppTypography.buttonMainHint),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
