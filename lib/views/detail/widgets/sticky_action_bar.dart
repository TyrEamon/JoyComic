/// Persistent flat detail action bar.
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_radius.dart';
import '../../../theme/app_shadows.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';

class StickyActionBar extends StatelessWidget {
  const StickyActionBar({
    super.key,
    required this.isFavorite,
    required this.readHint,
    required this.onFavorite,
    required this.onRead,
  });

  final bool isFavorite;
  final String readHint;
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
                  child: _ReadButton(hint: readHint, onTap: onRead),
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
    final color = isFavorite
        ? context.colorScheme.primary
        : context.secondaryTextColor;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isFavorite
              ? context.colorScheme.primaryContainer
              : context.elevatedSurfaceColor,
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
  const _ReadButton({required this.hint, required this.onTap});

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = context.colorScheme.onPrimary;
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(shape: const StadiumBorder()),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_rounded, size: 20, color: foreground),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '开始阅读',
                  style: AppTypography.buttonMainTitle.copyWith(
                    color: foreground,
                  ),
                ),
                if (hint.isNotEmpty)
                  Text(
                    hint,
                    style: AppTypography.buttonMainHint.copyWith(
                      color: foreground.withValues(alpha: 0.82),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
