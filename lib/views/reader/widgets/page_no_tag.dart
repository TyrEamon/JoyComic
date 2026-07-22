/// 页码角标（右上角，避免与返回键重叠）。
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../providers/reader_provider.dart' hide ReaderImage;
import '../utils/reader_utils.dart';

/// 显示在右上角的页码标签。
class ReaderPageNoTag extends StatelessWidget {
  const ReaderPageNoTag({super.key});

  @override
  Widget build(BuildContext context) {
    final pageNo = context.selector((p) => p.pageNo);
    final pageCount = context.selector((p) => p.pageCount);
    final showToolbar = context.selector((p) => p.showToolbar);

    // 工具栏展开时顶栏已有信息，隐藏角标避免叠层杂乱。
    if (showToolbar) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: context.right + 10,
      top: context.top + 10,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${pageNo + 1} / $pageCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
