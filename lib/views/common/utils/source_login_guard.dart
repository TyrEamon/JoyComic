/// Source login guard.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../comic_source/comic_source.dart';
import '../../../theme/app_theme_context.dart';

Future<bool> ensureSourceLoggedIn(
  BuildContext context,
  String sourceKey, {
  bool requireAuthentication = false,
}) async {
  final source = ComicSource.find(sourceKey);
  if (source == null) return false;
  if (!requireAuthentication && !source.requiresLoginForBrowsing) return true;
  if (source.isLogin) return true;

  final shouldLogin = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final scheme = dialogContext.colorScheme;
      return AlertDialog(
        backgroundColor: dialogContext.surfaceColor,
        title: Text(
          '${source.name} 未登录',
          style: TextStyle(color: scheme.onSurface),
        ),
        content: Text(
          '浏览 ${source.name} 的内容需要先登录账号。',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('去登录'),
          ),
        ],
      );
    },
  );

  if (shouldLogin != true || !context.mounted) return false;
  final loggedIn = await context.push<bool>(
    '/login?source=${Uri.encodeQueryComponent(sourceKey)}',
  );
  return loggedIn == true;
}
