/// Single inline favorite/read action row for the detail page.
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';

class DetailActions extends StatelessWidget {
  const DetailActions({
    super.key,
    required this.isFavorite,
    required this.canRead,
    required this.readLabel,
    required this.onFavorite,
    required this.onRead,
    this.onDownload,
  });

  final bool isFavorite;
  final bool canRead;
  final String readLabel;
  final VoidCallback onFavorite;
  final VoidCallback onRead;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    key: const ValueKey('detail-favorite-button'),
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
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    key: const ValueKey('detail-read-button'),
                    onPressed: canRead ? onRead : null,
                    style: FilledButton.styleFrom(
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.brLg,
                      ),
                    ),
                    icon: const Icon(Icons.menu_book_rounded, size: 20),
                    label: Text(readLabel),
                  ),
                ),
              ),
            ],
          ),
          if (onDownload != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                key: const ValueKey('detail-download-button'),
                onPressed: onDownload,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colorScheme.primary,
                  backgroundColor: context.surfaceColor,
                  side: BorderSide(color: context.borderColor),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.brLg,
                  ),
                ),
                icon: const Icon(Icons.download_for_offline_rounded, size: 20),
                label: const Text('下载章节'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
