import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/views/settings/about_page.dart';

void main() {
  testWidgets(
    'about page shows identity, version, disclaimer, licenses, and GitHub',
    (tester) async {
      Uri? launched;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: AboutPage(
            launchUrl: (uri) async {
              launched = uri;
              return true;
            },
          ),
        ),
      );

      expect(find.text('JoyComic'), findsWidgets);
      expect(find.text('版本 0.1.0 (1)'), findsOneWidget);
      expect(find.text('用途与免责声明'), findsOneWidget);
      expect(find.text('查看开源许可'), findsOneWidget);
      expect(find.text('GitHub 项目主页'), findsOneWidget);

      await tester.tap(find.text('GitHub 项目主页'));
      await tester.pump();
      expect(launched?.host, 'github.com');
    },
  );

  testWidgets('about route is real and diagnostics action navigates', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/about',
      routes: [
        GoRoute(path: '/about', builder: (context, state) => const AboutPage()),
        GoRoute(
          path: '/logs',
          builder: (context, state) => const Scaffold(body: Text('诊断日志页')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('关于 JoyComic'), findsOneWidget);

    await tester.tap(find.text('诊断日志'));
    await tester.pumpAndSettle();
    expect(find.text('诊断日志页'), findsOneWidget);

    router.dispose();
  });
}
