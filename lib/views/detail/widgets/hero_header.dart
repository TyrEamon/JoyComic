/// Immersive cover header with centralized readability scrims.
library;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_gradients.dart';
import '../../../theme/app_spacing.dart';
import 'info_overlay.dart';

class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.title,
    required this.subTitle,
    required this.backgroundCover,
    required this.frontCover,
    required this.rating,
    this.coverHeaders,
  });

  final String title;
  final String? subTitle;
  final String? backgroundCover;
  final String? frontCover;
  final double? rating;
  final Map<String, dynamic>? coverHeaders;

  static const double _height = 440;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: backgroundCover ?? frontCover ?? '',
                httpHeaders: coverHeaders?.cast<String, String>(),
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    _SolidBackground(color: context.elevatedSurfaceColor),
                errorBuilder: (_, __, ___) =>
                    _SolidBackground(color: context.elevatedSurfaceColor),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppGradients.imageScrimTop(
                      context.semanticColors,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _height * 0.72,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppGradients.imageScrimBottom(
                      context.semanticColors,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSpacing.lg,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: InfoOverlay(
                  title: title,
                  subTitle: subTitle,
                  frontCover: frontCover,
                  rating: rating,
                  coverHeaders: coverHeaders,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SolidBackground extends StatelessWidget {
  const _SolidBackground({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: color, child: const SizedBox.expand());
}
