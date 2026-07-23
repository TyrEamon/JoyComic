import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/detail/detail_page.dart';

void main() {
  test('share waits until the detail action sheet has closed', () async {
    final sheet = Completer<DetailMoreAction?>();
    final dismissal = Completer<void>();
    var shareCalls = 0;

    final future = handleDetailMoreAction(
      sheet.future,
      waitForDismissal: () => dismissal.future,
      onShare: () async => shareCalls++,
    );
    await Future<void>.delayed(Duration.zero);
    expect(shareCalls, 0);

    sheet.complete(DetailMoreAction.share);
    await Future<void>.delayed(Duration.zero);
    expect(shareCalls, 0);

    dismissal.complete();
    await future;
    expect(shareCalls, 1);
  });

  testWidgets('detail share origin is non-empty and inside the page', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    );

    final context = tester.element(find.byType(SizedBox).last);
    final origin = detailShareOrigin(context);
    expect(origin, isNotNull);
    if (origin == null) return;
    expect(origin.isEmpty, isFalse);
    expect(origin.left, greaterThanOrEqualTo(0));
    expect(origin.top, greaterThanOrEqualTo(0));
  });
}
