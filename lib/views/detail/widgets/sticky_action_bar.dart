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

  static const double buttonHeight = 52;
  static const double verticalPadding = 8;
  static const double contentHeight = buttonHeight + verticalPadding * 2;

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
          color: context.pageBackground.withValues(alpha: 0.96),
          border: Border(top: BorderSide(color: context.borderColor)),
          boxShadow: AppShadows.actionBar,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: verticalPadding,
            ),
            child: Row(
              children: [
                SizedBox(
                  key: const ValueKey<String>('sticky-favorite-button'),
                  width: 112,
                  height: buttonHeight,
                  child: OutlinedButton.icon(
                    onPressed: onFavorite,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isFavorite
                          ? context.colorScheme.primary
                          : context.secondaryTextColor,
                      backgroundColor: isFavorite
                          ? context.colorScheme.primaryContainer
                          : context.surfaceColor,
                      side: BorderSide(color: context.borderColor),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.brLg,
                      ),
                    ),
                    icon: Icon(
                      isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 20,
                    ),
                    label: Text(
                      isFavorite ? '已收藏' : '收藏',
                      style: AppTypography.buttonSecondary(context),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SizedBox(
                    key: const ValueKey<String>('sticky-read-button'),
                    height: buttonHeight,
                    child: FilledButton(
                      onPressed: onRead,
                      style: FilledButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadius.brLg,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.menu_book_rounded, size: 20),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '开始阅读',
                                  style: AppTypography.buttonMainTitle.copyWith(
                                    color: context.colorScheme.onPrimary,
                                  ),
                                ),
                                if (readHint.isNotEmpty)
                                  Text(
                                    readHint,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.buttonMainHint
                                        .copyWith(
                                          color: context.colorScheme.onPrimary
                                              .withValues(alpha: 0.82),
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
