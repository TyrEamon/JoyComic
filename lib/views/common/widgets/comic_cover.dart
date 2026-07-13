/// 通用封面图组件。
///
/// 统一封装封面加载的占位/错误/微阴影/细边框/圆角，详情页前景封面与
/// 列表卡片共用。网络图走 [cached_network_image_ce]（项目已锁 4.9.0），
/// 本地路径走 [FileImage]。来源判定同阅读器：靠 url scheme。
library comic_cover;

import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_radius.dart';
import '../../../theme/app_shadows.dart';

class ComicCover extends StatelessWidget {
  const ComicCover({
    super.key,
    required this.url,
    required this.width,
    this.aspectRatio = _kPortrait,
    this.radius = AppRadius.xl,
    this.elevation = true,
    this.border = true,
    this.fit = BoxFit.cover,
    this.headers,
    this.placeholder,
  });

  /// 竖版海报比例 3:4。
  static const double _kPortrait = 3 / 4;

  final String? url;
  final double width;
  final double aspectRatio;
  final double radius;
  final bool elevation;
  final bool border;
  final BoxFit fit;
  final Map<String, dynamic>? headers;
  final Widget? placeholder;

  bool get _isLocal => url != null && !url!.startsWith('http');

  @override
  Widget build(BuildContext context) {
    final height = width / aspectRatio;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(radius)),
        boxShadow: elevation ? AppShadows.coverElevation : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(radius)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            border: border
                ? Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.8)
                : null,
          ),
          child: _image(height),
        ),
      ),
    );
  }

  Widget _image(double height) {
    if (url == null || url!.isEmpty) {
      return placeholder ?? _Skeleton(height: height);
    }
    if (_isLocal) {
      return Image.file(
        File(url!),
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _Fallback(height),
      );
    }
    return CachedNetworkImage(
      imageUrl: url!,
      httpHeaders: headers?.cast<String, String>(),
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => _Skeleton(height: height),
      errorWidget: (_, __, ___) => _Fallback(height),
    );
  }
}

/// 加载占位骨架（品牌紫微光渐变扫过）。
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      color: AppColors.surfaceElevated,
      child: Center(
        child: Icon(Icons.broken_image_outlined,
            size: 24, color: AppColors.textDisabled),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback(this.height);
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      color: AppColors.surface,
      child: Center(
        child: Icon(Icons.image_not_supported_outlined,
            size: 24, color: AppColors.textDisabled),
      ),
    );
  }
}
