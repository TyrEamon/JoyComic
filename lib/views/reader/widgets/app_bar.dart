/// Reader top control overlay.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../../theme/app_gradients.dart';
import '../providers/reader_provider.dart' hide ReaderImage;
import '../utils/reader_utils.dart';

class ReaderAppBar extends StatelessWidget {
  const ReaderAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final showToolbar = context.selector((p) => p.showToolbar);
    final foreground = context.semanticColors.readerControlForeground;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      top: showToolbar ? 0 : -100,
      left: 0,
      right: 0,
      child: Container(
        key: const Key('reader-top-scrim'),
        padding: EdgeInsets.fromLTRB(0, context.top + 4, 0, 4),
        decoration: BoxDecoration(
          gradient: AppGradients.readerScrimTop(context.semanticColors),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                key: const Key('reader-back-icon'),
                color: foreground,
              ),
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
                    style: TextStyle(
                      color: foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    getTextBeforeNewLine(context.reader.chapter.name),
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.72),
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
