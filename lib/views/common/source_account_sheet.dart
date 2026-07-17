import 'package:flutter/material.dart';

import '../../comic_source/comic_source.dart';
import '../../theme/app_spacing.dart';
import 'source_account_profile.dart';

Future<bool> showSourceAccountSheet(
  BuildContext context,
  ComicSource source,
) async {
  final profile = SourceAccountProfile.fromSource(source);
  final avatarConfig = profile.avatarUrl == null
      ? null
      : source.getThumbnailLoadingConfig?.call(profile.avatarUrl!);
  final avatarUrl = avatarConfig?['url'] is String
      ? avatarConfig!['url'] as String
      : profile.avatarUrl;
  final avatarHeaders = _sourceImageHeaders(avatarConfig);
  final shouldLogout = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircleAvatar(
              radius: 34,
              child: avatarUrl == null
                  ? const Icon(Icons.person_rounded, size: 34)
                  : ClipOval(
                      child: Image.network(
                        avatarUrl,
                        headers: avatarHeaders,
                        width: 68,
                        height: 68,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.person_rounded, size: 34),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              profile.displayName,
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(profile.settingsStatus),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.logout_rounded),
                label: Text('退出${profile.sourceName}登录'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (shouldLogout != true || !context.mounted) return false;

  try {
    await source.account?.logout?.call();
    if (!context.mounted) return true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已退出${source.name}登录')));
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('退出登录失败：$error')));
    }
    return false;
  }
}

Map<String, String>? _sourceImageHeaders(Map<String, dynamic>? config) {
  if (config == null) return null;
  final value = config['headers'] is Map ? config['headers'] : config;
  if (value is! Map) return null;
  final headers = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is String && entry.value != null) {
      if (entry.key == 'url' ||
          entry.key == 'cacheKey' ||
          entry.key == 'method') {
        continue;
      }
      headers[entry.key as String] = entry.value.toString();
    }
  }
  return headers.isEmpty ? null : headers;
}
