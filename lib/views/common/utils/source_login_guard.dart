/// 源登录检测工具。
///
/// 当用户操作某个源的内容（如点开哔咔漫画）但该源未登录时，弹出提示。
library source_login_guard;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../theme/app_colors.dart';

/// 检查 [sourceKey] 对应的源是否已登录；若未登录则弹提示并返回 false。
/// 用户可选择跳转到登录页。
Future<bool> ensureSourceLoggedIn(
  BuildContext context,
  String sourceKey,
) async {
  final source = ComicSource.find(sourceKey);
  if (source == null) return false;
  if (source.isLogin) return true;

  final shouldLogin = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        '${source.name} 未登录',
        style: const TextStyle(color: AppColors.textHigh),
      ),
      content: Text(
        '浏览 ${source.name} 的内容需要先登录账号。',
        style: const TextStyle(color: AppColors.textMedium),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消', style: TextStyle(color: AppColors.textLow)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandPink,
          ),
          child: const Text('去登录'),
        ),
      ],
    ),
  );

  if (shouldLogin == true && context.mounted) {
    context.push('/login?source=$sourceKey');
  }
  return false;
}
