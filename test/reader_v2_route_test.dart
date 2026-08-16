import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/database/read_record_helper.dart';
import 'package:joycomic/views/reader/widgets/app_bar.dart';
import 'package:joycomic/views/reader/widgets/bottom.dart';
import 'package:joycomic/views/reader/state/comic_state.dart';
import 'package:joycomic/views/reader_v2/reader_v2.dart';
import 'package:joycomic/views/reader_v2/viewports/reader_v2_vertical.dart';
import 'package:joycomic/views/reader_v2/widgets/reader_v2_page_image.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  const chapter = ReaderChapter(id: 'ep', order: 1, name: 'Episode');
  const comic = ComicState(
    id: 'comic',
    title: 'Comic',
    chapters: [chapter],
    chapter: chapter,
    pageNo: 0,
    sourceKey: 'local',
    type: ReaderType.local,
    localPagePaths: [],
  );

  test('ReaderV2 is an independent shell that preserves route input', () {
    const reader = ReaderV2(comicState: comic);
    expect(reader.comicState, same(comic));

    final source = File(
      'lib/views/reader_v2/reader_v2.dart',
    ).readAsStringSync();
    expect(source, isNot(contains("import '../reader/reader.dart'")));
    expect(source, isNot(contains('extends Reader')));
  });

  test('/reader production route returns ReaderV2', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    expect(mainSource, contains("import 'views/reader_v2/reader_v2.dart';"));
    expect(mainSource, contains('return ReaderV2('));
  });

  testWidgets('ReaderV2 shell owns the viewport and keeps reader controls', (
    tester,
  ) async {
    final image = File('assets/app.jpg').absolute;
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    JoyDatabase.migrateCore(database);
    final localState = ComicState(
      id: 'local-comic',
      title: 'Local Comic',
      chapters: const <ReaderChapter>[chapter],
      chapter: chapter,
      pageNo: 0,
      sourceKey: 'local',
      type: ReaderType.local,
      localPagePaths: <String>[image.path],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderV2(
          comicState: localState,
          readRecordHelper: ReadRecordHelper(database),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(find.byType(ReaderV2Vertical), findsOneWidget);
    expect(find.byType(ReaderV2PageImage), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('reader-v2-stack'))),
      const Size(800, 600),
    );
    expect(find.byType(ReaderAppBar), findsOneWidget);
    expect(find.byType(ReaderBottom), findsOneWidget);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).drawer, isNotNull);

    final unlocked = find.byTooltip('锁定工具栏');
    final locked = find.byTooltip('解锁工具栏');
    final wasUnlocked = unlocked.evaluate().isNotEmpty;
    final lockControl = wasUnlocked ? unlocked : locked;
    expect(lockControl, findsOneWidget);
    expect(
      tester.getRect(find.byType(Slider)).overlaps(tester.getRect(lockControl)),
      isFalse,
    );
    await tester.tap(lockControl);
    await tester.pump();
    expect(wasUnlocked ? locked : unlocked, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
}
