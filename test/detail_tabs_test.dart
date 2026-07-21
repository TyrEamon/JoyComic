import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/detail_models.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/views/detail/widgets/chapter_thumbnail.dart';
import 'package:joycomic/views/detail/widgets/comment_composer.dart';
import 'package:joycomic/views/detail/widgets/detail_app_bar.dart';
import 'package:joycomic/views/reader/utils/source_aware_image.dart';

void main() {
  test(
    'detail source orders synopsis before recent chapters and inline actions',
    () {
      final source = File(
        'lib/views/detail/detail_page.dart',
      ).readAsStringSync();
      expect(
        source.indexOf('SynopsisBlock('),
        lessThan(source.indexOf('RecentChapterStrip(')),
      );
      expect(
        source.indexOf('RecentChapterStrip('),
        lessThan(source.indexOf('DetailActions(')),
      );
      expect(source, contains('CommentPreview('));
      expect(source, isNot(contains('DetailTabBar')));
      expect(source, isNot(contains('StickyActionBar')));
      expect(source, isNot(contains('onShare:')));
      expect(source, contains('onMore: ready ?'));
    },
  );

  testWidgets(
    'comment composer keeps reply state and clears text after success',
    (tester) async {
      var cancelled = false;
      final sent = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: CommentComposer(
              replyTarget: const CommentReplyTarget(
                id: 'comment-1',
                userName: 'Alice',
              ),
              sending: false,
              error: '上次发送失败',
              onCancelReply: () => cancelled = true,
              onSend: (value) async {
                sent.add(value);
                return true;
              },
            ),
          ),
        ),
      );

      expect(find.text('回复 Alice'), findsOneWidget);
      expect(find.text('上次发送失败'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(
        find.byKey(const ValueKey<String>('comment-send-button')),
      );
      await tester.pumpAndSettle();
      expect(sent, <String>['hello']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '',
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('comment-cancel-reply')),
      );
      expect(cancelled, isTrue);
    },
  );

  testWidgets('chapter thumbnail consumes its cached future once', (
    tester,
  ) async {
    var calls = 0;
    final completer = Completer<SourceAwareImageDescriptor?>();
    Future<SourceAwareImageDescriptor?> loader() {
      calls++;
      return completer.future;
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ChapterThumbnail(load: loader)),
      ),
    );
    await tester.pump();
    expect(calls, 1);

    completer.complete(null);
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('toolbar exposes only back and more actions', (tester) async {
    var more = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Stack(
            children: [
              DetailAppBar(
                title: 'Comic',
                onMore: () => more++,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    expect(more, 1);
  });
}
