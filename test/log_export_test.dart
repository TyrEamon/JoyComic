import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/foundation/log.dart';

void main() {
  test('formatLogsAsTxt writes chronological plain text', () {
    final text = Log.formatLogsAsTxt(
      const [
        JoyLogEntry(
          level: 'info',
          message: 'Reader load begin',
          time: '2026-07-21 12:00:00',
        ),
        JoyLogEntry(
          level: 'error',
          message: 'Reader API failed',
          error: 'cat=http host=example status=500',
          time: '2026-07-21 12:00:01',
        ),
      ],
      exportedAt: DateTime.utc(2026, 7, 21, 4, 0, 0),
      note: 'unit-test',
    );

    expect(text, contains('JoyComic 诊断日志'));
    expect(text, contains('条目数：2'));
    expect(text, contains('备注：unit-test'));
    expect(text, contains('[2026-07-21 12:00:00][INFO]'));
    expect(text, contains('Reader load begin'));
    expect(text, contains('[2026-07-21 12:00:01][ERROR]'));
    expect(text, contains('Error: cat=http host=example status=500'));
    expect(text, isNot(contains('<<<LOG_START>>>')));
  });

  test('log viewer and reader expose one-tap TXT export', () {
    final viewer = File(
      'lib/views/settings/log_viewer_page.dart',
    ).readAsStringSync();
    final errorPage = File(
      'lib/views/reader/widgets/error_page.dart',
    ).readAsStringSync();
    final reader = File('lib/views/reader/reader.dart').readAsStringSync();
    final exportHelper = File(
      'lib/foundation/log_export.dart',
    ).readAsStringSync();

    expect(viewer, contains("Key('log-export-txt-button')"));
    expect(viewer, contains('一键导出为 TXT'));
    expect(exportHelper, contains('exportJoyComicLogsTxt'));
    expect(errorPage, contains('导出 TXT'));
    expect(reader, contains('导出 TXT'));
  });

  test('bounded diagnostics retain only the newest entries', () {
    final entries = <JoyLogEntry>[];
    for (var index = 0; index < 5; index++) {
      appendBoundedDiagnosticEntry(
        entries,
        JoyLogEntry(
          level: 'info',
          message: 'Video event $index',
          time: '2026-07-23 22:00:0$index',
        ),
        maxEntries: 3,
      );
    }

    expect(entries.map((entry) => entry.message), <String>[
      'Video event 2',
      'Video event 3',
      'Video event 4',
    ]);
  });

  test('video diagnostics survive noisy persisted logs without duplicates', () {
    final persisted = <JoyLogEntry>[
      for (var index = 0; index < 62; index++)
        JoyLogEntry(
          level: 'warning',
          message: 'Reader image candidate failed $index',
          time: '2026-07-23 22:56:${index.toString().padLeft(2, '0')}',
        ),
    ];
    const videoEntry = JoyLogEntry(
      level: 'error',
      message: 'Video native initialization failed',
      error: 'host=cdn.example status=tls',
      time: '2026-07-23 22:51:00',
    );

    final merged = mergeDiagnosticLogs(
      persisted,
      const <JoyLogEntry>[videoEntry, videoEntry],
    );

    expect(
      merged.where((entry) => entry.message.startsWith('Video ')),
      hasLength(1),
    );
    expect(merged.first.message, 'Video native initialization failed');
    expect(merged, hasLength(63));
  });
}
