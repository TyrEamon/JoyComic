import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_theme_context.dart';
import 'detail_view_model.dart';
import 'widgets/comment_composer.dart';
import 'widgets/comment_section.dart';

/// Loads comic detail, then activates comments on success.
///
/// Shared by the initial open path and the error-state retry button so a
/// failed first detail load still fetches comment page 1 after recovery.
Future<void> loadDetailAndActivateComments(DetailViewModel viewModel) async {
  // `load()` accepts idle/error; after a previous success prefer `reload()` so
  // comment activation flags and caches are cleared cleanly.
  if (viewModel.state == DetailLoadState.success) {
    await viewModel.reload();
  } else {
    await viewModel.load();
  }
  if (viewModel.state == DetailLoadState.success) {
    await viewModel.activateComments();
  }
}

class DetailCommentsPage extends StatelessWidget {
  const DetailCommentsPage({
    super.key,
    required this.sourceKey,
    required this.comicId,
  });

  final String sourceKey;
  final String comicId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final vm = DetailViewModel(sourceKey: sourceKey, comicId: comicId);
        unawaited(loadDetailAndActivateComments(vm));
        return vm;
      },
      child: const _DetailCommentsScaffold(),
    );
  }
}

class _DetailCommentsScaffold extends StatelessWidget {
  const _DetailCommentsScaffold();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DetailViewModel>();
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(title: const Text('全部评论')),
      body: switch (vm.state) {
        DetailLoadState.loading || DetailLoadState.idle => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        DetailLoadState.error => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  vm.error ?? '评论加载失败',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.secondaryTextColor),
                ),
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () => unawaited(loadDetailAndActivateComments(vm)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        DetailLoadState.success =>
          !vm.canLoadComments
              ? Center(
                  child: Text(
                    '当前漫画源不支持评论',
                    style: TextStyle(color: context.tertiaryTextColor),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  children: [
                    CommentSection(
                      comments: vm.comments,
                      loading: vm.commentsLoading,
                      hasMore: vm.hasMoreComments,
                      onReply: vm.beginReply,
                      onLoadMore: vm.loadMoreComments,
                    ),
                    CommentComposer(
                      replyTarget: vm.replyTarget,
                      sending: vm.commentSending,
                      error: vm.commentSendError,
                      onCancelReply: vm.cancelReply,
                      onSend: vm.sendComment,
                    ),
                  ],
                ),
      },
    );
  }
}
