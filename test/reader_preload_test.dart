import 'dart:async';

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
}
