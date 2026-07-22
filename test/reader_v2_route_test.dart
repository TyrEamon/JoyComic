import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/reader/reader.dart';
import 'package:joycomic/views/reader/state/comic_state.dart';
import 'package:joycomic/views/reader_v2/reader_v2.dart';

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

  test('ReaderV2 compatibility shell preserves Reader contracts', () {
    const reader = ReaderV2(comicState: comic);
    expect(reader, isA<Reader>());
    expect(reader.comicState, same(comic));
  });

  test('/reader production route returns ReaderV2', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    expect(mainSource, contains("import 'views/reader_v2/reader_v2.dart';"));
    expect(mainSource, contains('return ReaderV2('));
  });
}
