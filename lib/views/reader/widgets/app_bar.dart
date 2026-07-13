/// 阅读器顶部工具栏。
library app_bar;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../providers/reader_provider.dart';
import '../utils/reader_utils.dart';

/// 阅读器顶部工具栏：返回按钮 + 漫画标题 + 章节名。
class ReaderAppBar extends StatelessWidget {
  const ReaderAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final showToolbar = context.selector((p) => p.showToolbar);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      top: showToolbar ? 0 : -100,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          0,
          context.top + 4,
          0,
          4,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                context.reader.stopPageTurn();
                context.pop();
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.reader.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    getTextBeforeNewLine(context.reader.chapter.name),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
