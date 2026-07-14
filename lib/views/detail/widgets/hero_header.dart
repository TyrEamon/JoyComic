/// 沉浸式高清双封面顶部通栏（Hero Header）。
///
/// 结构（自底向上四层）：
/// 1. 后层背景：封面作全屏通栏背景，BoxFit.cover 超大比例截取（非模糊），
///    顶部与状态栏融合。
/// 2. 渐变蒙版：[AppColors.heroTopMask]（顶部暗化提升导航可读性）+
///    [AppColors.heroBottomMask]（底部大面积渐变深色，无缝融入页面主体）。
/// 3. 前层主体封面：左侧完整无裁剪矩形封面，带微阴影立体实体感
///    （[AppShadows.coverElevation]）。
/// 4. 信息叠加层 [InfoOverlay]：围绕前景封面展开。
///
/// [palette] 注入封面取色，用于顶部暗化蒙版的品牌色微染（取色失败即品牌色）。
library;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../foundation/palette_extractor.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import 'info_overlay.dart';

class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.title,
    required this.subTitle,
    required this.backgroundCover,
    required this.frontCover,
    required this.author,
    required this.tags,
    required this.hotValue,
    required this.favoriteCount,
    required this.rating,
    required this.ratingCount,
    required this.palette,
    this.coverHeaders,
  });

  final String title;
  final String? subTitle;
  final String? backgroundCover;
  final String? frontCover;
  final String? author;
  final List<String> tags;
  final String? hotValue;
  final String? favoriteCount;
  final double rating;
  final String ratingCount;
  final ComicPalette palette;
  final Map<String, dynamic>? coverHeaders;

  static const double _height = 440;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            // 1. 后层背景通栏（超大截取，非模糊）。
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: backgroundCover ?? frontCover ?? '',
                httpHeaders: coverHeaders?.cast<String, String>(),
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    const _SolidBG(color: AppColors.heroBase),
                errorBuilder: (_, __, ___) =>
                    const _SolidBG(color: AppColors.heroBase),
              ),
            ),
            // 2a. 顶部暗化蒙版（导航可读性）。
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: AppColors.heroTopMask),
                ),
              ),
            ),
            // 2b. 取色染色的氛围光（顶部一抹封面主色，增强沉浸）。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 220,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        palette.accent.withValues(alpha: 0.22),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 2c. 底部大面积渐变深色蒙版（融入页面主体）。
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: _height * 0.72,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: AppColors.heroBottomMask),
                ),
              ),
            ),
            // 3 + 4. 前景封面 + 信息叠加层。
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
                  author: author,
                  tags: tags,
                  hotValue: hotValue,
                  favoriteCount: favoriteCount,
                  rating: rating,
                  ratingCount: ratingCount,
                  palette: palette,
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

class _SolidBG extends StatelessWidget {
  const _SolidBG({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: color, child: const SizedBox.expand());
}
