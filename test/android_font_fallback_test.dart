import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/theme/app_typography.dart';

void main() {
  test('Android does not force the bundled font', () {
    expect(appFontFamily(TargetPlatform.android), isNull);
  });

  test('Apple platforms keep the bundled font', () {
    expect(appFontFamily(TargetPlatform.iOS), kFontFamily);
    expect(appFontFamily(TargetPlatform.macOS), kFontFamily);
  });

  testWidgets('Android typography leaves font selection to the system', (
    tester,
  ) async {
    late TextStyle style;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Builder(
          builder: (context) {
            style = AppTypography.body(context);
            return Text('安卓文字', style: style);
          },
        ),
      ),
    );

    expect(find.text('安卓文字'), findsOneWidget);
    expect(style.fontFamily, isNull);
  });
}
