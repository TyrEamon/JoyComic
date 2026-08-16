import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/jm/jm_network.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/theme/app_theme.dart';
import 'package:joycomic/views/home/widgets/home_tool_bar.dart';
import 'package:joycomic/views/premium/jm_premium_page.dart';

void main() {
  test('getPromoteList uses 0-based page and parses total', () async {
    late String requestedUrl;
    final network = JmNetwork(
      getRequest: (url) async {
        requestedUrl = url;
        return const Res<dynamic>(<String, dynamic>{
          'total': '208',
          'list': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': '1454181',
              'author': '山含',
              'name': '兔寶寶公園 [禁漫去碼]',
              'description': '',
              'category': <String, dynamic>{'id': '1', 'title': '同人'},
            },
          ],
        });
      },
    );

    final result = await network.getPromoteList(jmPremiumPromoteId, 1);
    final uri = Uri.parse(requestedUrl);
    expect(uri.path, endsWith('/promote_list'));
    expect(uri.queryParameters['id'], jmPremiumPromoteId);
    expect(uri.queryParameters['page'], '0');
    expect(result.error, isFalse);
    expect(result.data.single.id, '1454181');
    expect(result.subData, 208);
  });

  test('getPromoteList page 2 maps to server page 1', () async {
    late String requestedUrl;
    final network = JmNetwork(
      getRequest: (url) async {
        requestedUrl = url;
        return const Res<dynamic>(<String, dynamic>{
          'total': '50',
          'list': <dynamic>[],
        });
      },
    );

    await network.getPromoteList('30', 2);
    expect(Uri.parse(requestedUrl).queryParameters['page'], '1');
  });

  test('premium promote id constant matches live JM section', () {
    expect(jmPremiumPromoteId, '30');
    expect(jmPremiumPromoteTitle, contains('去碼'));
  });

  testWidgets('home toolbar includes premium shortcut', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: HomeToolBar(entries: HomeToolBar.defaults(context)),
          ),
        ),
      ),
    );

    expect(find.text('精品'), findsOneWidget);
    expect(find.byKey(const Key('home-tool-icon-精品')), findsOneWidget);
  });

  test('main registers /premium route to JmPremiumPage', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains("path: '/premium'"), isTrue);
    expect(main.contains('JmPremiumPage'), isTrue);
  });

  testWidgets('premium page loads promote tab via loader', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: JmPremiumPage(
          loader: ({
            required JmPremiumTab tab,
            required int page,
            required String order,
          }) async {
            calls.add('${tab.name}:$page:$order');
            return const Res<List<JmComicBrief>>([
              JmComicBrief(
                id: '1',
                author: 'A',
                name: '去码作品',
                rawDescription: '',
              ),
            ], subData: 1);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, contains('promote:1:mr'));
    expect(find.text('去码作品'), findsOneWidget);
  });

  testWidgets('switching to demosaic tab requests search keyword', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: JmPremiumPage(
          loader: ({
            required JmPremiumTab tab,
            required int page,
            required String order,
          }) async {
            calls.add('${tab.name}:${tab.query}:$page');
            return Res<List<JmComicBrief>>([
              JmComicBrief(
                id: tab.name,
                author: 'A',
                name: '${tab.label}条目',
                rawDescription: '',
              ),
            ], subData: 1);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('去码'));
    await tester.pumpAndSettle();

    expect(calls.any((c) => c.startsWith('demosaic:禁漫去碼:')), isTrue);
    expect(find.text('去码条目'), findsOneWidget);
  });
}
