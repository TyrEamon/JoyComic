import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/main.dart' show appRouter;

void main() {
  testWidgets('application registers a real /about route', (tester) async {
    appRouter.go('/about');
    await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
    await tester.pumpAndSettle();

    expect(find.text('关于 JoyComic'), findsOneWidget);
  });
}
