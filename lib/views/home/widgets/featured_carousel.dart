/// Featured home carousel with source-aware covers and navigation metadata.
library featured_carousel;

import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_spacing.dart';

class FeaturedCarousel extends StatelessWidget {
  const FeaturedCarousel({
    super.key,
    required this.items,
    this.onTap,
  });

  final List<FeaturedItem> items;
  final void Function(FeaturedItem item)? onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 200,
      child: PageView.builder(
        padEnds: false,
        controller: PageController(viewportFraction: 0.88),
        itemCount: items.length,
        itemBuilder: (_, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: _FeaturedCard(
              item: item,
              onTap: onTap == null ? null : () => onTap!(item),
            ),
          );
        },
      ),
    );
  }
}

class FeaturedItem {
  const FeaturedItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    this.tag,
    this.badge,
    this.sourceKey,
    this.headers,
  });

  final String id;
  final String title;
  final String coverUrl;
  final String? tag;
  final String? badge;
  final String? sourceKey;
  final Map<String, dynamic>? headers;
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.item, required this.onTap});

  final FeaturedItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: ClipRRect(
        borderRadius: AppRadius.brLg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              item.coverUrl,
              fit: BoxFit.cover,
              headers: item.headers?.cast<String, String>(),
              colorBlendMode: BlendMode.dstATop,
              color: AppColors.surface,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.brandGradient,
                ),
              ),
            ),
            const Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                      stops: [0.0, 0.5, 1.0],
                      colors: [
                        Color(0xE60E0B14),
                        Color(0x800E0B14),
                        Color(0x140E0B14),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (item.badge != null || item.sourceKey != null)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.brandPink, AppColors.brandViolet],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.badge ?? _sourceLabel(item.sourceKey!),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.tag?.isNotEmpty == true)
                    Text(
                      item.tag!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.brandPink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.25,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sourceLabel(String sourceKey) => switch (sourceKey) {
        'jm' => 'JM',
        'picacg' => 'Pica',
        _ => sourceKey,
      };
}
