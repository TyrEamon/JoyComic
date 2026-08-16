import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/views/detail/widgets/detail_actions.dart';

void main() {
  testWidgets('detail page exposes a full-width chapter download action', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: DetailActions(
            isFavorite: false,
            canRead: true,
            readLabel: '开始阅读',
            onFavorite: () {},
            onRead: () {},
            onDownload: () => tapped = true,
          ),
        ),
      ),
    );

    final button = find.byKey(const ValueKey('detail-download-button'));
    expect(button, findsOneWidget);
    expect(find.text('下载章节'), findsOneWidget);
    expect(tester.getSize(button).height, 48);

    await tester.tap(button);
    expect(tapped, isTrue);
  });
}
