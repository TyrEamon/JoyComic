import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/theme/app_safe_area.dart';
import 'package:joycomic/theme/app_spacing.dart';

void main() {
  testWidgets('bottomContentInset combines view padding and design spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 34)),
          child: Builder(
            builder: (context) => Text('${bottomContentInset(context)}'),
          ),
        ),
      ),
    );

    expect(find.text('${34 + AppSpacing.xl}'), findsOneWidget);
  });

  testWidgets('bottomContentInset supports compact page spacing', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 20)),
          child: Builder(
            builder: (context) =>
                Text('${bottomContentInset(context, spacing: AppSpacing.sm)}'),
          ),
        ),
      ),
    );

    expect(find.text('${20 + AppSpacing.sm}'), findsOneWidget);
  });
}
