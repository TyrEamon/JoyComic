/// 下载管理器。
///
/// 功能：
/// - 并发限流（默认最多 3 个同时下载）
/// - 队列持久化（sqlite3）
/// - 进度追踪
/// - 错误重试
library download_manager;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/download_helper.dart';
import '../foundation/download_task.dart';
import '../foundation/log.dart';

/// 下载管理器单例，管理并发下载队列。
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final _helper = DownloadHelper();

  /// 并发上限。
  int maxConcurrent = 3;

  /// 全部任务列表（按创建时间倒序）。
  List<DownloadItem> _tasks = [];
  List<DownloadItem> get tasks => _tasks;

  /// 正在执行的任务数。
  int _activeCount = 0;

  /// 下载目录。
  String? _downloadDir;

  /// 初始化（应用启动时调用）。
  Future<void> initialize() async {
    final dir = await getApplicationDocumentsDirectory();
    _downloadDir = p.join(dir.path, 'downloads');
    await Directory(_downloadDir!).create(recursive: true);
    _tasks = _helper.getAll();
    Log.i('DownloadManager init', '${_tasks.length} tasks, dir: $_downloadDir');
  }

  /// 添加下载任务（自动开始排队）。
  Future<void> addTask({
    required String comicId,
    required String sourceKey,
    required String chapterId,
    required String url,
    String? fileName,
  }) async {
    final item = DownloadItem(
      comicId: comicId,
      sourceKey: sourceKey,
      chapterId: chapterId,
      url: url,
      fileName: fileName ?? p.basename(url),
    );

    final id = _helper.insert(item);
    final saved = _helper.getByStatus('pending').where((t) => t.id == id).firstOrNull;
    if (saved != null) {
      _tasks.insert(0, saved); // 最新在前
      notifyListeners();
      _processQueue();
    }
  }

  /// 处理队列（调度并发下载）。
  void _processQueue() {
    while (_activeCount < maxConcurrent) {
      final next = _tasks.firstWhereOrNull(
        (t) => t.status == DownloadStatus.pending,
      );
      if (next == null) break;
      _startDownload(next);
    }
  }

  Future<void> _startDownload(DownloadItem item) async {
    if (_downloadDir == null) return;

    _activeCount++;
    item.status = DownloadStatus.downloading;
    _helper.update(item);
    notifyListeners();

    try {
      final filePath = p.join(_downloadDir!, '${item.id}_${item.fileName ?? 'image'}');
      final dio = Dio();

      await dio.download(
        item.url,
        filePath,
        onReceiveProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          item.progress = progress.clamp(0.0, 1.0);
          _helper.update(item);
          notifyListeners();
        },
      );

      item.status = DownloadStatus.completed;
      item.filePath = filePath;
      item.progress = 1.0;
      _helper.update(item);
      Log.i('Download complete', filePath);
    } catch (e) {
      item.status = DownloadStatus.failed;
      Log.e('Download failed', error: '${item.url}: $e');
      _helper.update(item);
    } finally {
      _activeCount--;
      notifyListeners();
      _processQueue();
    }
  }

  /// 暂停任务。
  void pause(int id) {
    final item = _tasks.firstWhereOrNull((t) => t.id == id);
    if (item == null || item.status != DownloadStatus.downloading) return;
    item.status = DownloadStatus.paused;
    _helper.update(item);
    notifyListeners();
  }

  /// 恢复任务。
  void resume(int id) {
    final item = _tasks.firstWhereOrNull((t) => t.id == id);
    if (item == null || item.status != DownloadStatus.paused) return;
    item.status = DownloadStatus.pending;
    _helper.update(item);
    notifyListeners();
    _processQueue();
  }

  /// 删除任务（同时删除本地文件）。
  void delete(int id) {
    final item = _tasks.firstWhereOrNull((t) => t.id == id);
    if (item?.filePath != null) {
      File(item!.filePath!).delete().ignore();
    }
    _tasks.removeWhere((t) => t.id == id);
    _helper.delete(id);
    notifyListeners();
  }

  /// 重试失败任务。
  void retry(int id) {
    final item = _tasks.firstWhereOrNull((t) => t.id == id);
    if (item == null || item.status != DownloadStatus.failed) return;
    item.status = DownloadStatus.pending;
    item.progress = 0.0;
    _helper.update(item);
    notifyListeners();
    _processQueue();
  }

  /// 清空已完成。
  void clearCompleted() {
    for (final t in _tasks.where((t) => t.status == DownloadStatus.completed)) {
      if (t.filePath != null) File(t.filePath!).delete().ignore();
    }
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed);
    _helper.clearCompleted();
    notifyListeners();
  }

  /// 获取某漫画的下载状态。
  List<DownloadItem> getByComic(String comicId) =>
      _tasks.where((t) => t.comicId == comicId).toList();
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
