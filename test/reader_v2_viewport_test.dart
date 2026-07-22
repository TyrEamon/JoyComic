import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/database/read_record_helper.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/views/reader/providers/reader_provider.dart';
import 'package:joycomic/views/reader/state/comic_state.dart';
import 'package:joycomic/views/reader/state/read_mode.dart';
import 'package:joycomic/views/reader_v2/reader_v2_controller.dart';
import 'package:joycomic/views/reader_v2/viewports/reader_v2_paged.dart';
import 'package:joycomic/views/reader_v2/viewports/reader_v2_vertical.dart';
import 'package:joycomic/views/reader_v2/widgets/reader_v2_page_image.dart';
import 'package:sqlite3/sqlite3.dart';

const _png = <int>[
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xd7,
  0x63,
  0xf8,
  0xcf,
  0xc0,
  0xf0,
  0x1f,
  0x00,
  0x05,
  0x00,
  0x01,
  0xff,
  0x89,
  0x99,
  0x3d,
  0x1d,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({ReaderProvider reader, ReaderV2Controller controller})> harness({
    int count = 45,
    int preloadCount = 2,
    List<int>? loads,
  }) async {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    JoyDatabase.migrateCore(database);
    const chapter = ReaderChapter(id: 'ep', order: 1, name: 'Episode');
    final reader = ReaderProvider(
      state: const ComicState(
        id: 'comic',
        title: 'Comic',
        chapters: <ReaderChapter>[chapter],
        chapter: chapter,
        pageNo: 0,
        sourceKey: 'test',
      ),
      readRecordHelper: ReadRecordHelper(database),
      imageLoader: (_, __) async => Res<List<String>>(
        List<String>.generate(
          count,
          (index) => 'https://example.test/$index.png',
        ),
      ),
    );
    addTearDown(reader.dispose);
    while (reader.loadingState == ReaderLoadState.loading ||
        reader.loadingState == ReaderLoadState.idle) {
      await Future<void>.delayed(Duration.zero);
    }
    final controller = ReaderV2Controller(
      reader: reader,
      preloadCount: preloadCount,
      bytesLoader: (page, _) async {
        loads?.add(page.index);
        return Uint8List.fromList(_png);
      },
    );
    addTearDown(controller.dispose);
    return (reader: reader, controller: controller);
  }

  testWidgets('vertical viewport starts only page zero and nearby pages', (
    tester,
  ) async {
    final loads = <int>[];
    final state = (await tester.runAsync(() => harness(loads: loads)))!;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 440,
          height: 956,
          child: ReaderV2Vertical(
            controller: state.controller,
            reader: state.reader,
            widthRatio: 1,
            physics: const BouncingScrollPhysics(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ReaderV2PageImage), findsWidgets);
    expect(
      find.byType(ReaderV2PageImage).evaluate().length,
      lessThanOrEqualTo(3),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(loads, isNotEmpty);
    expect(loads.first, 0);
    expect(loads.every((index) => index <= 2), isTrue);
    expect(state.controller.scheduler.maxObservedActive, lessThanOrEqualTo(3));
  });

  testWidgets('paged viewport uses the shared page renderer in every mode', (
    tester,
  ) async {
    for (final mode in ReadMode.values.where((mode) => !mode.isVertical)) {
      final state = (await tester.runAsync(() => harness(count: 6)))!;
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderV2Paged(
            key: ValueKey<ReadMode>(mode),
            controller: state.controller,
            reader: state.reader,
            mode: mode,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ReaderV2PageImage), findsWidgets, reason: mode.name);
    }
  });
}
