/// 下一章浮动按钮（页码接近末尾时淡入）。
library next_chapter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/reader_provider.dart';
import '../utils/reader_utils.dart';

/// 当前页接近最后一页时显示"下一章" FAB。
class ReaderNextChapter extends StatelessWidget {
  const ReaderNextChapter({super.key});

  static bool _shouldShow(ReaderProvider provider) {
    final images = provider.images;
    final pageNo = provider.pageNo;
    final total = provider.pageCount;

    return !provider.isLastChapter &&
        images.isNotEmpty &&
        pageNo >= total - 2;
  }

  @override
  Widget build(BuildContext context) {
    return Selector<ReaderProvider, bool>(
      selector: (_, provider) => _shouldShow(provider),
      builder: (context, isShow, _) {
        return Positioned(
          right: context.right + 16,
          bottom: context.bottom + 16,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isShow ? 1.0 : 0.0,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: isShow ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !isShow,
                child: FloatingActionButton(
                  onPressed: context.reader.goNext,
                  child: const Icon(Icons.skip_next),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
