import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/detail_models.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/views/detail/widgets/chapter_thumbnail.dart';
import 'package:joycomic/views/detail/widgets/comment_composer.dart';
import 'package:joycomic/views/detail/widgets/detail_app_bar.dart';
import 'package:joycomic/views/detail/widgets/detail_tab_bar.dart';
import 'package:joycomic/views/detail/widgets/sticky_action_bar.dart';

void main() {
  test(
    'detail source orders synopsis before tabs and uses dynamic bottom padding',
    () {
      final source = File(
        'lib/views/detail/detail_page.dart',
      ).readAsStringSync();
      expect(
        source.indexOf('SynopsisBlock('),
        lessThan(source.indexOf('DetailTabBarDelegate(')),
      );
      expect(source, contains('StickyActionBar.contentHeight +'));
      expect(source, contains('MediaQuery.viewPaddingOf(context).bottom'));
      expect(source, isNot(contains('SizedBox(height: 96)')));
      expect(source, contains('onShare: ready ?'));
      expect(source, contains('onMore: ready ?'));
    },
  );

  testWidgets(
    'chapter tab is selected by default and comments show the true total',
    (tester) async {
      var selected = DetailTab.chapters;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: DetailTabBar(
                selected: selected,
                commentTotal: 37,
                onChanged: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      );

      expect(find.text('章节'), findsOneWidget);
      expect(find.text('评论 37'), findsOneWidget);
      expect(selected, DetailTab.chapters);

      await tester.tap(find.text('评论 37'));
      await tester.pump();
      expect(selected, DetailTab.comments);
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
    final completer = Completer<String?>();
    Future<String?> loader() {
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

  testWidgets('toolbar share and more actions are wired', (tester) async {
    var shares = 0;
    var more = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Stack(
            children: [
              DetailAppBar(onShare: () => shares++, onMore: () => more++),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.ios_share_rounded));
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    expect(shares, 1);
    expect(more, 1);
  });

  testWidgets('favorite and read actions are both exactly 52px high', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: StickyActionBar(
            isFavorite: false,
            readHint: '第一章',
            onFavorite: () {},
            onRead: () {},
          ),
        ),
      ),
    );

    expect(StickyActionBar.buttonHeight, 52);
    expect(StickyActionBar.contentHeight, 68);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('sticky-favorite-button')))
          .height,
      52,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('sticky-read-button')))
          .height,
      52,
    );
    expect(find.byType(SafeArea), findsOneWidget);
  });
}
