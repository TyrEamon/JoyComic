/// JoyComic 日志系统。
///
/// 基于 `logger` 包，支持：
/// - 文件输出（自动轮转，最多保留 3 个文件）
/// - debug 模式下控制台输出
/// - JSON 格式化，可解析回顾
/// - 5 级日志：d / i / w / e / f
library log;

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

/// 全局日志门面。
class Log {
  Log._();

  static Logger _logger = Logger();
  static late String _logsPath;

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
      final path = p.join(_logsPath, 'latest.log');
      final file = File(path);
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      final entries = content
          .split('<<<LOG_START>>>')
          .where((e) => e.contains('<<<LOG_END>>>'));

      return entries.map((e) {
        final jsonStr = e.replaceAll('<<<LOG_END>>>', '').trim();
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        return JoyLogEntry(
          level: json['level'] ?? '',
          message: json['message'] ?? '',
          error: json['error']?.toString(),
          stackTrace: json['stackTrace']?.toString(),
          time: json['time'] ?? '',
        );
      }).toList();
    } catch (e, st) {
      _logger.e('Failed to get logs', error: e, stackTrace: st);
      return [];
    }
  }

  /// 清除所有日志。
  static Future<void> clear() async {
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
  }) =>
      _logger.t(message, error: error, stackTrace: stackTrace, time: time);

  /// debug — 开发调试用。
  static void d(
    String message, [
    dynamic data,
  ]) =>
      _logger.d('$message${data != null ? '\n$data' : ''}');

  /// info — 关键流程记录。
  static void i(
    String message, [
    dynamic data,
  ]) =>
      _logger.i('$message${data != null ? '\n$data' : ''}');

  /// warn — 警告。
  static void w(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _logger.w(message, error: error, stackTrace: stackTrace);

  /// error — 异常。
  static void e(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _logger.e(message, error: error, stackTrace: stackTrace);

  /// fatal — 致命错误。
  static void f(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) =>
      _logger.f(message, error: error, stackTrace: stackTrace);
}

/// JSON 格式的日志打印机（与文件解析格式一致）。
class _JoyPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) {
    final now = Jiffy.now().format(pattern: 'yyyy-MM-dd HH:mm:ss');
    final json = {
      'time': now,
      'level': event.level.name,
      'message': event.message.toString(),
      'error': event.error?.toString(),
      'stackTrace': event.stackTrace?.toString(),
    };
    return [
      '<<<LOG_START>>>',
      jsonEncode(json),
      '<<<LOG_END>>>',
    ];
  }
}
