import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/views/detail/detail_navigation.dart';
import 'package:joycomic/views/reader/state/comic_state.dart';

void main() {
  test('start reading selects the earliest chapter from a reversed list', () {
    const chapters = <ReaderChapter>[
      ReaderChapter(id: '3', order: 3, name: '第三章'),
      ReaderChapter(id: '2', order: 2, name: '第二章'),
      ReaderChapter(id: '1', order: 1, name: '第一章'),
    ];

    expect(selectStartReadingChapter(chapters).id, '1');
  });

  test(
    'start reading keeps the earliest chapter from normal and single lists',
    () {
      const normal = <ReaderChapter>[
        ReaderChapter(id: '1', order: 1, name: '第一章'),
        ReaderChapter(id: '2', order: 2, name: '第二章'),
      ];
      const single = <ReaderChapter>[
        ReaderChapter(id: 'only', order: 9, name: '独章'),
      ];

      expect(selectStartReadingChapter(normal).id, '1');
      expect(selectStartReadingChapter(single).id, 'only');
    },
  );

  test('start reading rejects an empty chapter list', () {
    expect(
      () => selectStartReadingChapter(const <ReaderChapter>[]),
      throwsArgumentError,
    );
  });
}
