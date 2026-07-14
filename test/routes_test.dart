import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/main.dart' show appRouter;
import 'package:joycomic/views/common/source_content_page.dart';

void main() {
  testWidgets('application registers a real /about route', (tester) async {
    appRouter.go('/about');
    await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
    await tester.pumpAndSettle();

    expect(find.text('关于 JoyComic'), findsOneWidget);
  });

  testWidgets('encoded category deep link maps to SourceContentPage', (
    tester,
  ) async {
    const category = '校园/恋爱 中文';
    appRouter.go('/category/jm/${Uri.encodeComponent(category)}');
    await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
    await tester.pump();

    final page = tester.widget<SourceContentPage>(
      find.byType(SourceContentPage),
    );
    expect(page.sourceKey, 'jm');
    expect(page.kind, 'category');
    expect(page.category, category);
  });

  testWidgets('legacy /content route remains available', (tester) async {
    appRouter.go('/content/picacg?category=legacy&sort=dd');
    await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
    await tester.pump();

    final page = tester.widget<SourceContentPage>(
      find.byType(SourceContentPage),
    );
    expect(page.sourceKey, 'picacg');
    expect(page.category, 'legacy');
    expect(page.sort, 'dd');
  });

  testWidgets('reader rejects a non-ComicState extra with an explicit 404', (
    tester,
  ) async {
    appRouter.go('/reader', extra: <String, Object?>{'bad': true});
    await tester.pumpWidget(MaterialApp.router(routerConfig: appRouter));
    await tester.pumpAndSettle();

    expect(find.text('404'), findsOneWidget);
    expect(find.text('阅读器参数无效'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
