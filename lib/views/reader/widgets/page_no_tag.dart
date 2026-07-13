/// 页码角标（横向模式下覆盖在图片上的页码指示）。
library page_no_tag;

import 'package:flutter/material.dart';

import '../utils/reader_utils.dart';
import '../providers/reader_provider.dart' hide ReaderImage;

/// 显示在左上角的页码标签。
class ReaderPageNoTag extends StatelessWidget {
  const ReaderPageNoTag({super.key});

  @override
  Widget build(BuildContext context) {
    final pageNo = context.selector((p) => p.pageNo);
    final pageCount = context.selector((p) => p.pageCount);

    return Positioned(
      left: context.left + 8,
      top: context.top + 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${pageNo + 1} / $pageCount',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}
