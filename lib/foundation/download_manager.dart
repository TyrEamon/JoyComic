/// Source-aware chapter download queue.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../comic_source/comic_source.dart';
import '../database/download_helper.dart';
import '../network/jm/jm_network.dart' show jmScrambleId;
import 'download_task.dart';
import 'jm_image_recombine.dart';
import 'log.dart';

typedef DownloadSourceResolver = ComicSource? Function(String sourceKey);

/// Persists, schedules, pauses and resumes chapter-level downloads.
class DownloadManager extends ChangeNotifier {
  DownloadManager._()
    : _helper = DownloadHelper(),
      _configuredDirectory = null,
      _sourceResolver = ComicSource.find,
      _dio = Dio(),
      maxConcurrent = 3;

  DownloadManager.forTesting({
    required DownloadHelper helper,
    required Directory downloadDirectory,
    required DownloadSourceResolver sourceResolver,
    Dio? dio,
    this.maxConcurrent = 3,
  }) : _helper = helper,
       _configuredDirectory = downloadDirectory,
       _sourceResolver = sourceResolver,
       _dio = dio ?? Dio();

  static final DownloadManager instance = DownloadManager._();

  final DownloadHelper _helper;
  final Directory? _configuredDirectory;
  final DownloadSourceResolver _sourceResolver;
  final Dio _dio;

  int maxConcurrent;

  List<DownloadTask> _tasks = <DownloadTask>[];
  List<DownloadTask> get tasks => List<DownloadTask>.unmodifiable(_tasks);

  Directory? _downloadDirectory;
  Future<void>? _initializeFuture;
  bool _initialized = false;
  bool _disposed = false;
  final Set<int> _activeIds = <int>{};
  final Set<int> _resumeRequested = <int>{};
  final Map<int, CancelToken> _cancelTokens = <int, CancelToken>{};

  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializeFuture ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    try {
      final directory =
          _configuredDirectory ??
          Directory(
            p.join(
              (await getApplicationDocumentsDirectory()).path,
              'downloads',
            ),
          );
      await directory.create(recursive: true);
      _downloadDirectory = directory;
      _helper.recoverInterrupted();
      _tasks = _helper.getAll();
      _initialized = true;
      Log.i(
        'DownloadManager init',
        '${_tasks.length} tasks, dir: ${directory.path}',
      );
      _notify();
      _processQueue();
    } finally {
      if (!_initialized) _initializeFuture = null;
    }
  }

  DownloadTask? findTask(String sourceKey, String comicId, String chapterId) {
    final identity = DownloadIdentity(sourceKey, comicId, chapterId);
    return _tasks.firstWhereOrNull((task) => task.identity == identity);
  }

  Future<DownloadTask> enqueue({
    required String sourceKey,
    required String comicId,
    required String chapterId,
    required String title,
    required String coverUrl,
    required String chapterTitle,
  }) async {
    await initialize();
    final identity = DownloadIdentity(sourceKey, comicId, chapterId);
    final inMemory = _tasks.firstWhereOrNull(
      (task) => task.identity == identity,
    );
    if (inMemory != null) return inMemory;

    var saved = _helper.enqueue(
      DownloadTask(
        sourceKey: sourceKey,
        comicId: comicId,
        chapterId: chapterId,
        title: title,
        coverUrl: coverUrl,
        chapterTitle: chapterTitle,
      ),
    );
    final raced = _tasks.firstWhereOrNull((task) => task.identity == identity);
    if (raced != null) return raced;

    if (saved.directory == null || saved.directory!.isEmpty) {
      saved.directory = p.join(
        _downloadDirectory!.path,
        _safeSegment(sourceKey),
        _safeSegment(comicId),
        '${_safeSegment(chapterId)}_${saved.id}',
      );
      _helper.update(saved);
      saved = _helper.getById(saved.id!)!;
    }
    _tasks.insert(0, saved);
    _notify();
    _processQueue();
    return saved;
  }

  /// Compatibility wrapper retained for old callers.
  Future<DownloadTask> addTask({
    required String comicId,
    required String sourceKey,
    required String chapterId,
    String url = '',
    String? fileName,
  }) {
    return enqueue(
      sourceKey: sourceKey,
      comicId: comicId,
      chapterId: chapterId,
      title: comicId,
      coverUrl: '',
      chapterTitle: fileName ?? chapterId,
    );
  }

  void _processQueue() {
    if (!_initialized || _disposed) return;
    while (_activeIds.length < maxConcurrent) {
      final next = _tasks.firstWhereOrNull((task) {
        final id = task.id;
        if (id == null || _activeIds.contains(id)) return false;
        if (task.status == DownloadStatus.pending) return true;
        return _resumeRequested.contains(id) &&
            (task.status == DownloadStatus.paused ||
                task.status == DownloadStatus.failed);
      });
      if (next == null) break;
      final id = next.id!;
      _resumeRequested.remove(id);
      _activeIds.add(id);
      next.transitionTo(DownloadStatus.downloading);
      next.errorMessage = null;
      _helper.update(next);
      _notify();
      unawaited(_runTask(next));
    }
  }

  Future<void> _runTask(DownloadTask task) async {
    final id = task.id!;
    try {
      final source = _sourceResolver(task.sourceKey);
      if (source == null) {
        throw StateError('漫画源 ${task.sourceKey} 未启用');
      }
      final loadPages = source.loadComicPages;
      if (loadPages == null) {
        throw StateError('漫画源 ${source.name} 不支持章节下载');
      }

      if (task.pageUrls.isEmpty) {
        final result = await loadPages(task.comicId, task.chapterId);
        if (result.error) {
          throw StateError(result.errorMessage ?? '加载章节图片失败');
        }
        final urls = result.data;
        if (urls.isEmpty) throw StateError('章节没有可下载图片');
        task.pageUrls = List<String>.unmodifiable(urls);
        task.completedCount = 0;
        _helper.update(task);
        _notify();
      }
      if (task.status != DownloadStatus.downloading) return;

      final finalDirectory = Directory(task.directory!);
      final partialDirectory = Directory('${task.directory}.part');
      if (await finalDirectory.exists() && !await partialDirectory.exists()) {
        final complete = await _hasAllPages(finalDirectory, task);
        if (complete) {
          task.completedCount = task.pageUrls.length;
          task.transitionTo(DownloadStatus.completed);
          _helper.update(task);
          return;
        }
      }
      await partialDirectory.create(recursive: true);
      task.completedCount = await _contiguousPageCount(partialDirectory, task);
      _helper.update(task);

      for (
        var index = task.completedCount;
        index < task.pageUrls.length;
        index++
      ) {
        if (task.status != DownloadStatus.downloading) return;
        final url = task.pageUrls[index];
        final filename = DownloadTask.pageFileName(index, url);
        final target = File(p.join(partialDirectory.path, filename));
        if (await target.exists()) {
          task.completedCount = index + 1;
          _helper.update(task);
          continue;
        }

        final config = source.getImageLoadingConfig?.call(
          url,
          task.comicId,
          task.chapterId,
        );
        final requestUrl = config?['url'] is String
            ? config!['url'] as String
            : url;
        final method = config?['method'] is String
            ? config!['method'] as String
            : 'GET';
        final headers = _extractHeaders(config);
        final cancelToken = CancelToken();
        _cancelTokens[id] = cancelToken;
        final response = await _dio.request<List<int>>(
          requestUrl,
          options: Options(
            method: method,
            headers: headers,
            responseType: ResponseType.bytes,
          ),
          cancelToken: cancelToken,
        );
        if (task.status != DownloadStatus.downloading) return;
        final data = response.data;
        if (data == null || data.isEmpty) {
          throw StateError('图片 ${index + 1} 返回空数据');
        }
        var bytes = Uint8List.fromList(data);
        if (task.sourceKey.toLowerCase() == 'jm') {
          final imageName = p.basenameWithoutExtension(Uri.parse(url).path);
          bytes = await JmRecombine.recombine(
            bytes,
            task.chapterId,
            jmScrambleId,
            imageName,
          );
        }
        if (task.status != DownloadStatus.downloading) return;

        final temporary = File('${target.path}.tmp');
        await temporary.writeAsBytes(bytes, flush: true);
        if (await target.exists()) await target.delete();
        await temporary.rename(target.path);
        task.completedCount = index + 1;
        task.errorMessage = null;
        _helper.update(task);
        _notify();
      }

      if (task.status != DownloadStatus.downloading) return;
      if (await finalDirectory.exists()) {
        await finalDirectory.delete(recursive: true);
      }
      await partialDirectory.rename(finalDirectory.path);
      task.completedCount = task.pageUrls.length;
      task.transitionTo(DownloadStatus.completed);
      _helper.update(task);
      Log.i('Download complete', finalDirectory.path);
    } catch (error, stackTrace) {
      if (task.status == DownloadStatus.downloading &&
          _tasks.any((candidate) => candidate.id == id)) {
        task.errorMessage = error.toString();
        task.transitionTo(DownloadStatus.failed);
        _helper.update(task);
        Log.e('Download failed', error: error, stackTrace: stackTrace);
      }
    } finally {
      _cancelTokens.remove(id);
      _activeIds.remove(id);
      _notify();
      _processQueue();
    }
  }

  Future<bool> pause(int id) async {
    final task = _taskById(id);
    if (task == null || task.status != DownloadStatus.downloading) return false;
    task.transitionTo(DownloadStatus.paused);
    _helper.update(task);
    _cancelTokens[id]?.cancel('paused');
    _notify();
    return true;
  }

  Future<bool> resume(int id) async {
    final task = _taskById(id);
    if (task == null ||
        (task.status != DownloadStatus.paused &&
            task.status != DownloadStatus.failed) ||
        _resumeRequested.contains(id)) {
      return false;
    }
    _resumeRequested.add(id);
    _processQueue();
    return true;
  }

  Future<bool> retry(int id) => resume(id);

  /// Removes only queue metadata; downloaded/partial files are preserved.
  Future<bool> deleteTask(int id) => _remove(id, deleteFiles: false);

  /// Removes queue metadata and both final and partial chapter directories.
  Future<bool> deleteFiles(int id) => _remove(id, deleteFiles: true);

  /// Compatibility API: the old action deleted both record and file.
  Future<bool> delete(int id) => deleteFiles(id);

  Future<bool> _remove(int id, {required bool deleteFiles}) async {
    final task = _taskById(id);
    if (task == null) return false;
    if (task.status == DownloadStatus.downloading) {
      task.transitionTo(DownloadStatus.paused);
      _cancelTokens[id]?.cancel('deleted');
    }
    _resumeRequested.remove(id);
    _tasks.remove(task);
    _helper.delete(id);
    _notify();

    while (_activeIds.contains(id)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    if (deleteFiles && task.directory != null && task.directory!.isNotEmpty) {
      await _deleteDirectoryIfPresent(Directory(task.directory!));
      await _deleteDirectoryIfPresent(Directory('${task.directory}.part'));
    }
    return true;
  }

  /// Clears completed task records while deliberately preserving chapter files.
  Future<void> clearCompleted() async {
    final ids = _tasks
        .where((task) => task.status == DownloadStatus.completed)
        .map((task) => task.id!)
        .toList();
    for (final id in ids) {
      await deleteTask(id);
    }
  }

  Future<void> whenIdle({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_activeIds.isNotEmpty ||
        _resumeRequested.isNotEmpty ||
        _tasks.any((task) => task.status == DownloadStatus.pending)) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('DownloadManager did not become idle', timeout);
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  DownloadTask? _taskById(int id) =>
      _tasks.firstWhereOrNull((task) => task.id == id);

  static Map<String, dynamic>? _extractHeaders(Map<String, dynamic>? config) {
    if (config == null || config.isEmpty) return null;
    final nested = config['headers'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    return <String, dynamic>{
      for (final entry in config.entries)
        if (entry.key != 'url' && entry.key != 'method') entry.key: entry.value,
    };
  }

  static Future<int> _contiguousPageCount(
    Directory directory,
    DownloadTask task,
  ) async {
    var count = 0;
    for (var index = 0; index < task.pageUrls.length; index++) {
      final file = File(
        p.join(
          directory.path,
          DownloadTask.pageFileName(index, task.pageUrls[index]),
        ),
      );
      if (!await file.exists()) break;
      count++;
    }
    return count;
  }

  static Future<bool> _hasAllPages(
    Directory directory,
    DownloadTask task,
  ) async {
    return await _contiguousPageCount(directory, task) == task.pageUrls.length;
  }

  static Future<void> _deleteDirectoryIfPresent(Directory directory) async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  static String _safeSegment(String value) {
    final safe = value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    return safe.isEmpty ? '_' : safe;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final token in _cancelTokens.values) {
      token.cancel('disposed');
    }
    _cancelTokens.clear();
    super.dispose();
  }
}

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
