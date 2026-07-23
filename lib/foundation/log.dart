/// JoyComic 日志系统。
///
/// 基于 `logger` 包，支持：
/// - 文件输出（自动轮转，最多保留 3 个文件）
/// - debug 模式下控制台输出
/// - JSON 格式化，可解析回顾
/// - 5 级日志：d / i / w / e / f
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:jiffy/jiffy.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 日志条目数据。
class JoyLogEntry {
  const JoyLogEntry({
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
    required this.time,
  });

  final String level;
  final String message;
  final String? error;
  final String? stackTrace;
  final String time;

  @override
  String toString() => '[$time][$level]\n$message\n$error\n$stackTrace';
}

void appendBoundedDiagnosticEntry(
  List<JoyLogEntry> entries,
  JoyLogEntry entry, {
  int maxEntries = 80,
}) {
  if (maxEntries <= 0) {
    entries.clear();
    return;
  }
  entries.add(entry);
  final overflow = entries.length - maxEntries;
  if (overflow > 0) entries.removeRange(0, overflow);
}

List<JoyLogEntry> mergeDiagnosticLogs(
  Iterable<JoyLogEntry> persisted,
  Iterable<JoyLogEntry> videoSnapshot,
) {
  final unique = <String, JoyLogEntry>{};
  for (final entry in <JoyLogEntry>[...persisted, ...videoSnapshot]) {
    final key = jsonEncode(<Object?>[
      entry.time,
      entry.level,
      entry.message,
      entry.error,
      entry.stackTrace,
    ]);
    unique.putIfAbsent(key, () => entry);
  }
  final merged = unique.values.toList(growable: false)
    ..sort((left, right) => left.time.compareTo(right.time));
  return List<JoyLogEntry>.unmodifiable(merged);
}

/// 全局日志门面。
class Log {
  Log._();

  static Logger _logger = Logger();
  static late String _logsPath;
  static const int _maxVideoDiagnosticEntries = 80;
  static final List<JoyLogEntry> _videoDiagnostics = <JoyLogEntry>[];

  static String _timestamp() =>
      Jiffy.now().format(pattern: 'yyyy-MM-dd HH:mm:ss');

  static String _messageWithData(String message, dynamic data) =>
      '$message${data != null ? '\n$data' : ''}';

  static void _captureVideoDiagnostic(
    String level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!message.startsWith('Video ')) return;
    appendBoundedDiagnosticEntry(
      _videoDiagnostics,
      JoyLogEntry(
        level: level,
        message: message,
        error: error?.toString(),
        stackTrace: stackTrace?.toString(),
        time: _timestamp(),
      ),
      maxEntries: _maxVideoDiagnosticEntries,
    );
  }

  /// 在应用启动时初始化。
  static Future<void> initialize() async {
    try {
      _logsPath = p.join(
        (await getApplicationCacheDirectory()).path,
        'joycomic_logs',
      );

      final outputs = <LogOutput>[
        AdvancedFileOutput(path: _logsPath, maxRotatedFilesCount: 3),
      ];

      if (kDebugMode) {
        outputs.add(ConsoleOutput());
      }

      _logger = Logger(
        printer: _JoyPrinter(),
        filter: ProductionFilter(),
        level: kReleaseMode ? Level.info : Level.all,
        output: MultiOutput(outputs),
      );
    } catch (e, st) {
      _logger.e('Log init failed', error: e, stackTrace: st);
    }
  }

  /// 读取全部已持久化的日志。
  static Future<List<JoyLogEntry>> getLogs() async {
    try {
      final persisted = <JoyLogEntry>[];
      final path = p.join(_logsPath, 'latest.log');
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        final entries = content
            .split('<<<LOG_START>>>')
            .where((entry) => entry.contains('<<<LOG_END>>>'));

        for (final entry in entries) {
          final jsonStr = entry.replaceAll('<<<LOG_END>>>', '').trim();
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          persisted.add(
            JoyLogEntry(
              level: json['level'] ?? '',
              message: json['message'] ?? '',
              error: json['error']?.toString(),
              stackTrace: json['stackTrace']?.toString(),
              time: json['time'] ?? '',
            ),
          );
        }
      }
      return mergeDiagnosticLogs(persisted, _videoDiagnostics);
    } catch (e, st) {
      _logger.e('Failed to get logs', error: e, stackTrace: st);
      return List<JoyLogEntry>.unmodifiable(_videoDiagnostics);
    }
  }

  /// 将日志条目格式化为纯文本 TXT（时间升序，便于完整粘贴/转发）。
  static String formatLogsAsTxt(
    List<JoyLogEntry> logs, {
    DateTime? exportedAt,
    String? note,
  }) {
    final when = (exportedAt ?? DateTime.now()).toIso8601String();
    final buffer = StringBuffer()
      ..writeln('JoyComic 诊断日志')
      ..writeln('导出时间：$when')
      ..writeln('条目数：${logs.length}');
    if (note != null && note.trim().isNotEmpty) {
      buffer.writeln('备注：${note.trim()}');
    }
    buffer
      ..writeln('=' * 60)
      ..writeln();

    // Callers often pass newest-first; export chronological for reading.
    final ordered = logs.toList(growable: false);
    for (final log in ordered) {
      buffer.writeln('[${log.time}][${log.level.toUpperCase()}]');
      buffer.writeln(log.message);
      if (log.error != null && log.error!.isNotEmpty) {
        buffer.writeln('Error: ${log.error}');
      }
      if (log.stackTrace != null && log.stackTrace!.isNotEmpty) {
        buffer.writeln('Stack: ${log.stackTrace}');
      }
      buffer
        ..writeln()
        ..writeln('-' * 40)
        ..writeln();
    }
    return buffer.toString();
  }

  /// 写出临时 TXT 文件，供系统分享面板一键发出。
  ///
  /// 返回生成的 [File]；无日志时返回 null。
  static Future<File?> writeExportTxtFile({
    List<JoyLogEntry>? logs,
    String? note,
  }) async {
    final entries = logs ?? await getLogs();
    if (entries.isEmpty) return null;

    final text = formatLogsAsTxt(entries, note: note);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(p.join(dir.path, 'joycomic_logs_$stamp.txt'));
    await file.writeAsString(text, flush: true);
    return file;
  }

  /// 清除所有日志。
  static Future<void> clear() async {
    _videoDiagnostics.clear();
    await _logger.close();
    final dir = Directory(_logsPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await initialize();
  }

  // ============================ Log 方法 ============================

  /// trace（一般不直接用）。
  static void t(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    DateTime? time,
  }) => _logger.t(message, error: error, stackTrace: stackTrace, time: time);

  /// debug — 开发调试用。
  static void d(String message, [dynamic data]) {
    _logger.d(_messageWithData(message, data));
  }

  /// info — 关键流程记录。
  static void i(String message, [dynamic data]) {
    final text = _messageWithData(message, data);
    _captureVideoDiagnostic('info', text);
    _logger.i(text);
  }

  /// warn — 警告。
  static void w(String message, {Object? error, StackTrace? stackTrace}) {
    _captureVideoDiagnostic(
      'warning',
      message,
      error: error,
      stackTrace: stackTrace,
    );
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// error — 异常。
  static void e(String message, {Object? error, StackTrace? stackTrace}) {
    _captureVideoDiagnostic(
      'error',
      message,
      error: error,
      stackTrace: stackTrace,
    );
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// fatal — 致命错误。
  static void f(String message, {Object? error, StackTrace? stackTrace}) {
    _captureVideoDiagnostic(
      'fatal',
      message,
      error: error,
      stackTrace: stackTrace,
    );
    _logger.f(message, error: error, stackTrace: stackTrace);
  }
}

/// JSON 格式的日志打印机（与文件解析格式一致）。
class _JoyPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) {
    final json = {
      'time': Log._timestamp(),
      'level': event.level.name,
      'message': event.message.toString(),
      'error': event.error?.toString(),
      'stackTrace': event.stackTrace?.toString(),
    };
    return ['<<<LOG_START>>>', jsonEncode(json), '<<<LOG_END>>>'];
  }
}
