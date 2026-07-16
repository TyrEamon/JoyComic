/// Centralized login-required prompt for a comic source.
library;

import 'package:flutter/material.dart';

import '../../../theme/app_spacing.dart';
import '../../common/source_content_models.dart';
import '../utils/source_login_guard.dart';

class SourceLoginPrompt extends StatelessWidget {
  const SourceLoginPrompt({
    super.key,
    required this.requirement,
    this.onLoggedIn,
    this.contentLabel = '首页内容',
  });

  final HomeLoginRequirement requirement;
  final VoidCallback? onLoggedIn;
  final String contentLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('登录 ${requirement.sourceName} 后加载$contentLabel'),
              ),
              FilledButton(
                onPressed: () async {
                  final loggedIn = await ensureSourceLoggedIn(
                    context,
                    requirement.sourceKey,
                  );
                  if (loggedIn) onLoggedIn?.call();
                },
                child: const Text('去登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
