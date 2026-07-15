import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/views/search/search_page.dart';

void main() {
  test('directJmComicId accepts JM prefix and bare numeric IDs', () {
    expect(directJmComicId('JM123'), '123');
    expect(directJmComicId('jm 123'), '123');
    expect(directJmComicId(' 123 '), '123');
    expect(directJmComicId('JM-123'), isNull);
    expect(directJmComicId('Alice123'), isNull);
  });

  testWidgets('JM search submits a direct ID to the detail route', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/search/jm',
      routes: <RouteBase>[
        GoRoute(
          path: '/search/:sourceKey',
          builder: (context, state) => SearchPage(
            sourceKey: state.pathParameters['sourceKey']!,
            initialQuery: state.uri.queryParameters['q'],
          ),
        ),
        GoRoute(
          path: '/detail/:sourceKey/:comicId',
          builder: (context, state) => Scaffold(
            body: Text(
              'detail ${state.pathParameters['sourceKey']} '
              '${state.pathParameters['comicId']}',
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.enterText(find.byType(TextField), 'JM123');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();

    expect(find.text('detail jm 123'), findsOneWidget);
  });
}
