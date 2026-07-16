import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/built_in/jm.dart';
import 'package:joycomic/comic_source/built_in/picacg.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/network/base_comic.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/views/home/widgets/home_tool_bar.dart';
import 'package:joycomic/views/ranking/ranking_page.dart';

void main() {
  testWidgets('home toolbar exposes one ranking entry and five tools', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                HomeToolBar(entries: HomeToolBar.defaults(context)),
          ),
        ),
      ),
    );

    expect(
      HomeToolBar.defaults(
        tester.element(find.byType(HomeToolBar)),
      ).map((entry) => entry.label).toList(),
      <String>['排行榜', '影视', '以图搜图', '收藏库', '下载'],
    );
  });

  test('built-in sources expose source-specific ranking sort contracts', () {
    expect(
      buildJmSource().categoryComicsData!.rankingData!.options,
      <String, String>{'latest': 'mr', 'hot': 'mp', 'rating': 'mv'},
    );
    expect(
      buildPicacgSource().categoryComicsData!.rankingData!.options,
      <String, String>{'latest': 'dd', 'hot': 'ld', 'rating': 'da'},
    );
  });

  testWidgets('ranking sends source-specific sort codes', (tester) async {
    final requested = <String>[];
    final jm = _rankingSource(
      key: 'jm',
      options: const <String, String>{
        'latest': 'mr',
        'hot': 'mp',
        'rating': 'mv',
      },
      load: (option, page) async {
        requested.add('jm:$option');
        return Res<List<BaseComic>>(<BaseComic>[_Comic('jm-$option')]);
      },
    );
    final pica = _rankingSource(
      key: 'picacg',
      options: const <String, String>{
        'latest': 'dd',
        'hot': 'ld',
        'rating': 'da',
      },
      load: (option, page) async {
        requested.add('picacg:$option');
        return Res<List<BaseComic>>(<BaseComic>[_Comic('pica-$option')]);
      },
    )..data['token'] = 'token';

    await tester.pumpWidget(
      MaterialApp(home: RankingPage(sources: <ComicSource>[jm, pica])),
    );
    await tester.pumpAndSettle();
    expect(requested, containsAll(<String>['jm:mr', 'picacg:dd']));

    await tester.tap(find.text('热门'));
    await tester.pumpAndSettle();
    expect(requested, containsAll(<String>['jm:mp', 'picacg:ld']));

    await tester.tap(find.text('评分'));
    await tester.pumpAndSettle();
    expect(requested, containsAll(<String>['jm:mv', 'picacg:da']));
  });

  testWidgets('logged-out Pica shows one prompt while JM remains visible', (
    tester,
  ) async {
    var picaLoads = 0;
    final jm = _rankingSource(
      key: 'jm',
      load: (_, __) async =>
          const Res<List<BaseComic>>(<BaseComic>[_Comic('jm-visible')]),
    );
    final pica = _rankingSource(
      key: 'picacg',
      load: (_, __) async {
        picaLoads++;
        return const Res<List<BaseComic>>(<BaseComic>[_Comic('must-not-load')]);
      },
    );

    await tester.pumpWidget(
      MaterialApp(home: RankingPage(sources: <ComicSource>[jm, pica])),
    );
    await tester.pumpAndSettle();

    expect(find.text('jm-visible'), findsOneWidget);
    expect(find.textContaining('登录 哔咔'), findsOneWidget);
    expect(picaLoads, 0);
  });

  testWidgets('expired Pica session becomes a ranking login prompt', (
    tester,
  ) async {
    late final ComicSource pica;
    pica = _rankingSource(
      key: 'picacg',
      load: (_, __) async {
        pica.data.remove('token');
        pica.data.remove('authenticated');
        return const Res<List<BaseComic>>.error('登录失效且重新登录失败');
      },
    )..data['token'] = 'expired-token';

    await tester.pumpWidget(
      MaterialApp(home: RankingPage(sources: <ComicSource>[pica])),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录 哔咔 后加载排行榜内容'), findsOneWidget);
    expect(find.byKey(const Key('ranking-retry-picacg')), findsNothing);
  });

  testWidgets('retry reloads only the failed source and keeps successes', (
    tester,
  ) async {
    var jmLoads = 0;
    var picaLoads = 0;
    final jm = _rankingSource(
      key: 'jm',
      load: (_, __) async {
        jmLoads++;
        return const Res<List<BaseComic>>(<BaseComic>[
          _Comic('jm-still-visible'),
        ]);
      },
    );
    final pica = _rankingSource(
      key: 'picacg',
      load: (_, __) async {
        picaLoads++;
        if (picaLoads == 1) {
          return const Res<List<BaseComic>>.error('pica failed');
        }
        return const Res<List<BaseComic>>(<BaseComic>[
          _Comic('pica-recovered'),
        ]);
      },
    )..data['token'] = 'token';

    await tester.pumpWidget(
      MaterialApp(home: RankingPage(sources: <ComicSource>[jm, pica])),
    );
    await tester.pumpAndSettle();

    expect(find.text('jm-still-visible'), findsOneWidget);
    expect(find.byKey(const Key('ranking-retry-picacg')), findsOneWidget);
    expect(jmLoads, 1);
    expect(picaLoads, 1);

    await tester.tap(find.byKey(const Key('ranking-retry-picacg')));
    await tester.pumpAndSettle();

    expect(jmLoads, 1);
    expect(picaLoads, 2);
    expect(find.text('jm-still-visible'), findsOneWidget);
    expect(find.text('pica-recovered'), findsOneWidget);
  });
}

ComicSource _rankingSource({
  required String key,
  Map<String, String> options = const <String, String>{
    'latest': 'mr',
    'hot': 'mp',
    'rating': 'mv',
  },
  required Future<Res<List<BaseComic>>> Function(String option, int page) load,
}) => ComicSource.named(
  key: key,
  name: key == 'picacg' ? '哔咔' : '禁漫',
  filePath: 'test',
  categoryComicsData: CategoryComicsData.named(
    load: (_, __, ___, ____) async => const Res(<BaseComic>[]),
    rankingData: RankingData.named(options: options, load: load),
  ),
);

class _Comic extends BaseComic {
  const _Comic(this.title);

  @override
  final String title;
  @override
  String get id => title;
  @override
  String get cover => '';
  @override
  String get subTitle => '';
  @override
  List<String> get tags => const <String>[];
  @override
  String get description => '';
}
