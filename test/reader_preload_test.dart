import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/database/read_record_helper.dart';
import 'package:joycomic/foundation/reader_config.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/views/reader/providers/list_state_provider.dart';
import 'package:joycomic/views/reader/providers/reader_provider.dart';
import 'package:joycomic/views/reader/state/comic_state.dart';
import 'package:joycomic/views/reader/utils/image_preload_controller.dart';
import 'package:joycomic/views/reader/utils/reader_image_provider.dart';
import 'package:joycomic/views/reader/widgets/horizontal_list/horizontal_list.dart';
import 'package:joycomic/views/reader/widgets/vertical_list/vertical_list.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final entry in <(String, Widget)>[
    ('horizontal', const HorizontalList()),
    ('vertical', const VerticalList()),
  ]) {
    testWidgets('${entry.$1} reader uses ReaderConf preload count', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'preloadImageCount': 7});
      ReaderConf.instance.inject(await SharedPreferences.getInstance());
      const chapter = ReaderChapter(id: 'chapter', order: 1, name: 'Chapter');
      final pendingImages = Completer<Res<List<String>>>();
      final database = sqlite3.openInMemory();
      JoyDatabase.migrateCore(database);
      addTearDown(database.dispose);
      final reader = ReaderProvider(
        state: const ComicState(
          id: 'comic',
          title: 'Comic',
          chapters: [chapter],
          chapter: chapter,
          pageNo: 0,
          sourceKey: 'test',
        ),
        imageLoader: (_, _) => pendingImages.future,
        readRecordHelper: ReadRecordHelper(database),
        readRecordDebounce: const Duration(milliseconds: 1),
      );
      addTearDown(reader.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ReaderProvider>.value(value: reader),
            ChangeNotifierProvider<ListStateProvider>(
              create: (_) => ListStateProvider(),
            ),
          ],
          child: MaterialApp(home: Scaffold(body: entry.$2)),
        ),
      );

      final controller = reader.preloadController as ImagePreloadController;
      expect(controller.maxPreloadCount, 7);
      await tester.pump(const Duration(milliseconds: 2));
    });
  }

  test(
    'horizontal single-page and double-page paths carry real trace and image indexes',
    () {
      final source = File(
        'lib/views/reader/widgets/horizontal_list/horizontal_list.dart',
      ).readAsStringSync();

      // Single-page PhotoView path must forward diagnostics context.
      expect(source, contains('_buildSinglePageOptions('));
      expect(source, contains('imageIndex: index'));
      expect(source, contains('traceId: traceId'));
      // Signature accepts gallery index + trace.
      expect(
        RegExp(
          r'_buildSinglePageOptions\([\s\S]*?required int imageIndex[\s\S]*?\)',
        ).hasMatch(source),
        isTrue,
      );
      expect(
        source.contains('readerImageProvider(') &&
            source.contains('imageIndex: imageIndex'),
        isTrue,
      );
      // Double-page must use absolute gallery indexes, not only 0/1 in-row.
      expect(source, contains('baseIndex: baseIndex'));
      expect(
        source.contains('imageIndex: ordered[visualSlot].\$1') ||
            source.contains('imageIndex: absoluteIndex') ||
            source.contains('imageIndex: baseIndex +'),
        isTrue,
      );
    },
  );

  test('preload failure message includes trace index and redacted cache summary', () {
    final message = ImagePreloadController.formatPreloadFailure(
      traceId: 'tr12ab34cd',
      imageIndex: 3,
      cacheKey: 'jm|comic-1|ep-1|00003',
      error: Exception(
        'DioException uri=https://cdn.example/a.webp?token=secret-token',
      ),
    );
    expect(message, contains('trace=tr12ab34cd'));
    expect(message, contains('idx=3'));
    expect(message, contains('cache='));
    expect(message, isNot(contains('secret-token')));
    expect(message, isNot(contains('token=secret')));
  });

  test('preload controller provider builder forwards trace and image index', () {
    final item = const ReaderImage(
      url: 'https://cdn.example/a.webp?token=secret',
      cacheKey: 'ck-1',
    );
    final provider = ImagePreloadController.buildNetworkProvider(
      item: item,
      cacheWidth: 1080,
      traceId: 'tracepreload',
      imageIndex: 4,
    );
    ImageProvider network = provider;
    if (provider is ResizeImage) {
      network = provider.imageProvider;
    }
    expect(network, isA<ReaderNetworkImageProvider>());
    final net = network as ReaderNetworkImageProvider;
    expect(net.traceId, 'tracepreload');
    expect(net.imageIndex, 4);
  });
}
