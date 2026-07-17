import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/foundation/sauce_nao_config_store.dart';
import 'package:joycomic/foundation/sauce_nao_search.dart';
import 'package:joycomic/foundation/source_credential_store.dart';
import 'package:joycomic/network/base_comic.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/views/common/widgets/comic_grid.dart';
import 'package:joycomic/views/image_search/image_search_page.dart';

void main() {
  late Directory tempDirectory;
  late String imagePath;
  late _MemorySecretStore backend;
  late SauceNaoConfigStore configStore;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('image-search-test-');
    imagePath = (await File(
      '${tempDirectory.path}/picked.jpg',
    ).writeAsBytes(<int>[1, 2, 3])).path;
    backend = _MemorySecretStore();
    configStore = SauceNaoConfigStore(store: backend, environmentApiKey: '');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  testWidgets('secure-store read failure remains recoverable', (tester) async {
    final failingStore = SauceNaoConfigStore(
      store: _FailingSecretStore(failRead: true),
      environmentApiKey: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImageSearchPage(
          configStore: failingStore,
          pickImage: (_) async => XFile(imagePath),
          sauceSearch: (_, __) async => const <SauceResult>[],
          internalMatcher: (_) async => const <ComicGridItem>[],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('无法读取 SauceNAO API Key，请重新设置'), findsOneWidget);
    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();
    expect(find.text('设置 SauceNAO API Key'), findsOneWidget);
  });

  testWidgets('secure-store write failure keeps key dialog open', (
    tester,
  ) async {
    final failingStore = SauceNaoConfigStore(
      store: _FailingSecretStore(failWrite: true),
      environmentApiKey: '',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ImageSearchPage(
          configStore: failingStore,
          pickImage: (_) async => null,
          sauceSearch: (_, __) async => const <SauceResult>[],
          internalMatcher: (_) async => const <ComicGridItem>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('设置 Key'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('saucenao-key-field')),
      'new-key',
    );
    await tester.tap(find.text('保存 Key'));
    await tester.pump();

    expect(find.text('无法保存 SauceNAO API Key，请稍后重试'), findsOneWidget);
    expect(find.text('设置 SauceNAO API Key'), findsOneWidget);
  });

  test('internal matching continues after one source fails', () async {
    final matches = await searchInternalImageMatches(
      'title',
      sources: <ComicSource>[
        _source('jm', (_, __, ___) async => throw StateError('offline')),
        _source(
          'picacg',
          (_, __, ___) async => const Res<List<BaseComic>>(<BaseComic>[
            _FakeComic(id: 'comic-1', title: 'Matched'),
          ]),
        ),
      ],
    );

    expect(matches.single.id, 'comic-1');
    expect(matches.single.sourceKey, 'picacg');
  });

  test('internal matching reports failure when every source fails', () async {
    await expectLater(
      searchInternalImageMatches(
        'title',
        sources: <ComicSource>[
          _source(
            'jm',
            (_, __, ___) async => const Res<List<BaseComic>>.error('offline'),
          ),
          _source('picacg', (_, __, ___) async => throw StateError('offline')),
        ],
      ),
      throwsA(isA<StateError>()),
    );
  });

  testWidgets('retains original SauceNAO results without internal matches', (
    tester,
  ) async {
    await configStore.saveApiKey('secure-key');
    Uri? launched;
    String? searchedKey;
    await tester.pumpWidget(
      MaterialApp(
        home: ImageSearchPage(
          configStore: configStore,
          pickImage: (_) async => XFile(imagePath),
          sauceSearch: (_, key) async {
            searchedKey = key;
            return const <SauceResult>[
              SauceResult(
                similarity: 91.5,
                thumbnail: '',
                source: 'Pixiv',
                title: 'Original title',
                author: 'Author',
                extUrls: <String>['https://example.com/work'],
              ),
            ];
          },
          internalMatcher: (_) async => const <ComicGridItem>[],
          externalLauncher: (uri) async {
            launched = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('从相册选择'));
    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();

    expect(searchedKey, 'secure-key');
    expect(find.text('SauceNAO 原始结果'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Original title'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Original title'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('内部漫画匹配'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('内部漫画匹配'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('暂无站内匹配'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('暂无站内匹配'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('查看来源'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('查看来源'));
    await tester.pump();
    expect(launched, Uri.parse('https://example.com/work'));
  });

  testWidgets('missing key opens setup and persists a custom key', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ImageSearchPage(
          configStore: configStore,
          pickImage: (_) async => XFile(imagePath),
          sauceSearch: (_, __) async => const <SauceResult>[],
          internalMatcher: (_) async => const <ComicGridItem>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();
    expect(find.text('请先设置 SauceNAO API Key'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('saucenao-key-field')),
      'new-key',
    );
    await tester.tap(find.text('保存 Key'));
    await tester.pumpAndSettle();
    expect(await configStore.readApiKey(), 'new-key');
  });

  testWidgets('shows a distinct empty state when SauceNAO finds no result', (
    tester,
  ) async {
    await configStore.saveApiKey('secure-key');
    await tester.pumpWidget(
      MaterialApp(
        home: ImageSearchPage(
          configStore: configStore,
          pickImage: (_) async => XFile(imagePath),
          sauceSearch: (_, __) async => const <SauceResult>[],
          internalMatcher: (_) async => const <ComicGridItem>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('SauceNAO 未找到相似结果'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('SauceNAO 未找到相似结果'), findsOneWidget);
  });

  testWidgets('picker permission errors have source-specific messages', (
    tester,
  ) async {
    await configStore.saveApiKey('secure-key');
    await tester.pumpWidget(
      MaterialApp(
        home: ImageSearchPage(
          configStore: configStore,
          pickImage: (source) async => throw PlatformException(
            code: source == ImageSource.camera
                ? 'camera_access_denied'
                : 'photo_access_denied',
          ),
          sauceSearch: (_, __) async => const <SauceResult>[],
          internalMatcher: (_) async => const <ComicGridItem>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('从相册选择'));
    await tester.pump();
    expect(find.text('请允许访问相册后重试'), findsOneWidget);

    await tester.tap(find.text('拍摄'));
    await tester.pump();
    expect(find.text('请允许使用相机后重试'), findsOneWidget);
  });

  testWidgets('camera unavailable is distinct from permission denial', (
    tester,
  ) async {
    await configStore.saveApiKey('secure-key');
    await tester.pumpWidget(
      MaterialApp(
        home: ImageSearchPage(
          configStore: configStore,
          pickImage: (_) async =>
              throw PlatformException(code: 'no_available_camera'),
          sauceSearch: (_, __) async => const <SauceResult>[],
          internalMatcher: (_) async => const <ComicGridItem>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('拍摄'));
    await tester.pump();

    expect(find.text('相机不可用，请改用相册选择'), findsOneWidget);
    expect(find.text('请允许使用相机后重试'), findsNothing);
  });

  testWidgets('typed SauceNAO errors map to distinct messages', (tester) async {
    await configStore.saveApiKey('secure-key');
    await tester.pumpWidget(
      MaterialApp(
        home: ImageSearchPage(
          configStore: configStore,
          pickImage: (_) async => XFile(imagePath),
          sauceSearch: (_, __) async =>
              throw const SauceNaoException(SauceNaoErrorKind.rateLimited),
          internalMatcher: (_) async => const <ComicGridItem>[],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('从相册选择'));
    await tester.pumpAndSettle();

    expect(find.text('SauceNAO 请求过于频繁，请稍后重试'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pump();
    expect(find.text('SauceNAO 原始结果'), findsNothing);
    expect(find.text('SauceNAO 未找到相似结果'), findsNothing);
  });

  testWidgets('soutubot action opens the external service', (tester) async {
    await configStore.saveApiKey('secure-key');
    Uri? launched;
    await tester.pumpWidget(
      MaterialApp(
        home: ImageSearchPage(
          configStore: configStore,
          pickImage: (_) async => null,
          sauceSearch: (_, __) async => const <SauceResult>[],
          internalMatcher: (_) async => const <ComicGridItem>[],
          externalLauncher: (uri) async {
            launched = uri;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('soutubot'));
    await tester.pump();

    expect(launched, Uri.parse('https://soutubot.moe/'));
  });
}

class _MemorySecretStore implements SecretKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FailingSecretStore implements SecretKeyValueStore {
  _FailingSecretStore({this.failRead = false, this.failWrite = false});

  final bool failRead;
  final bool failWrite;

  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async {
    if (failRead) throw PlatformException(code: 'secure_store_unavailable');
    return null;
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw PlatformException(code: 'secure_store_unavailable');
  }
}

ComicSource _source(String key, SearchFunction loader) => ComicSource.named(
  name: key,
  key: key,
  filePath: 'test',
  searchPageData: SearchPageData.named(loadPage: loader),
);

class _FakeComic extends BaseComic {
  const _FakeComic({required this.id, required this.title});

  @override
  final String id;
  @override
  final String title;
  @override
  String get cover => '';
  @override
  String get description => '';
  @override
  String get subTitle => '';
  @override
  List<String> get tags => const <String>[];
}
