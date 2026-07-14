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
  String? _canonicalDownloadRoot;
  Future<void>? _initializeFuture;
  bool _initialized = false;
  bool _disposed = false;
  final Set<int> _activeIds = <int>{};
  final Set<int> _resumeRequested = <int>{};
  final Map<int, CancelToken> _cancelTokens = <int, CancelToken>{};

  int get activeCount => _activeIds.length;

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
      _canonicalDownloadRoot = p.normalize(
        await directory.resolveSymbolicLinks(),
      );
      _helper.recoverInterrupted();
      _tasks = _helper.getAll();
      for (final task in _tasks) {
        await _preparePersistedTaskStorage(task);
      }
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
    final safeSource = _safeSegment(sourceKey);
    final safeComic = _safeSegment(comicId);
    final safeChapter = _safeSegment(chapterId);
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
        safeSource,
        safeComic,
        '${safeChapter}_${saved.id}',
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

  Future<void> _preparePersistedTaskStorage(DownloadTask task) async {
    var changed = false;
    if (task.directory == null || task.directory!.trim().isEmpty) {
      try {
        task.directory = _safeTaskDirectory(task);
        changed = true;
      } on ArgumentError catch (error) {
        _failPersistedTaskStorage(task, error);
        return;
      }
    } else {
      try {
        await _assertManagedPath(task.directory!);
      } on FileSystemException catch (error) {
        _failPersistedTaskStorage(task, error);
        return;
      }
    }

    final legacyPath = task.legacyFilePath;
    if (legacyPath != null && legacyPath.trim().isNotEmpty) {
      if (task.status == DownloadStatus.completed) {
        try {
          await _migrateLegacyCompletedFile(task, File(legacyPath));
        } on FileSystemException catch (error) {
          _failPersistedTaskStorage(task, error);
        } on ArgumentError catch (error) {
          _failPersistedTaskStorage(task, error);
        }
        return;
      }
      task.legacyFilePath = null;
      changed = true;
    }
    if (changed) _helper.update(task);
  }

  void _failPersistedTaskStorage(DownloadTask task, Object error) {
    task.status = DownloadStatus.failed;
    task.completedCount = 0;
    task.errorMessage = error.toString();
    _helper.update(task);
  }

  String _safeTaskDirectory(DownloadTask task) {
    return p.join(
      _downloadDirectory!.path,
      _safeSegment(task.sourceKey),
      _safeSegment(task.comicId),
      '${_safeSegment(task.chapterId)}_${task.id}',
    );
  }

  Future<void> _migrateLegacyCompletedFile(
    DownloadTask task,
    File legacyFile,
  ) async {
    await _assertManagedPath(legacyFile.path);
    final safeDirectory = _safeTaskDirectory(task);
    final finalDirectory = Directory(safeDirectory);
    final partialDirectory = Directory('$safeDirectory.part');
    await _assertManagedPath(finalDirectory.path);
    await _assertManagedPath(partialDirectory.path);

    if (!await legacyFile.exists()) {
      task.directory = safeDirectory;
      task.completedCount = 0;
      task.status = DownloadStatus.failed;
      task.errorMessage = '旧版下载文件不存在：${legacyFile.path}';
      _helper.update(task);
      return;
    }
    if (task.pageUrls.isEmpty) {
      task.pageUrls = <String>[legacyFile.uri.toString()];
    }
    await _deleteDirectoryIfPresent(partialDirectory);
    await partialDirectory.create(recursive: true);
    final target = File(
      p.join(
        partialDirectory.path,
        DownloadTask.pageFileName(0, task.pageUrls.first),
      ),
    );
    final temporary = File('${target.path}.tmp');
    await _assertManagedPath(temporary.path);
    final sink = temporary.openWrite();
    try {
      await sink.addStream(legacyFile.openRead());
      await sink.flush();
    } finally {
      await sink.close();
    }
    await _renameManagedFile(temporary, target);
    await _deleteDirectoryIfPresent(finalDirectory);
    await _renameManagedDirectory(partialDirectory, finalDirectory);

    task.directory = safeDirectory;
    task.completedCount = 1;
    task.legacyFilePath = null;
    task.errorMessage = null;
    _helper.update(task);
    if (!p.equals(legacyFile.path, target.path) && await legacyFile.exists()) {
      await _assertManagedPath(legacyFile.path);
      await legacyFile.delete();
    }
  }

  void _processQueue() {
    if (!_initialized || _disposed) return;
    final persistenceFailures = <int>{};
    while (_activeIds.length < maxConcurrent) {
      final next = _tasks.firstWhereOrNull((task) {
        final id = task.id;
        if (id == null ||
            _activeIds.contains(id) ||
            persistenceFailures.contains(id)) {
          return false;
        }
        if (task.status == DownloadStatus.pending) return true;
        return _resumeRequested.contains(id) &&
            (task.status == DownloadStatus.paused ||
                task.status == DownloadStatus.failed);
      });
      if (next == null) break;
      final id = next.id!;
      final previousStatus = next.status;
      final previousError = next.errorMessage;
      final previousUpdatedAt = next.updatedAt;
      _resumeRequested.remove(id);
      _activeIds.add(id);
      next.transitionTo(DownloadStatus.downloading);
      next.errorMessage = null;
      try {
        _helper.update(next);
      } catch (error, stackTrace) {
        next.status = previousStatus;
        next.errorMessage = previousError;
        next.updatedAt = previousUpdatedAt;
        if (previousStatus == DownloadStatus.paused ||
            previousStatus == DownloadStatus.failed) {
          _resumeRequested.add(id);
        }
        _activeIds.remove(id);
        persistenceFailures.add(id);
        Log.e(
          'Download scheduling persistence failed',
          error: error,
          stackTrace: stackTrace,
        );
        _notify();
        continue;
      }
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
      await _assertManagedPath(finalDirectory.path);
      await _assertManagedPath(partialDirectory.path);
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
        final temporary = File('${target.path}.tmp');
        await _assertManagedPath(target.path);
        await _assertManagedPath(temporary.path);
        if (task.sourceKey.toLowerCase() == 'jm') {
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
          final rawBytes = data is Uint8List ? data : Uint8List.fromList(data);
          final imageName = p.basenameWithoutExtension(Uri.parse(url).path);
          final recombined = await JmRecombine.recombine(
            rawBytes,
            task.chapterId,
            jmScrambleId,
            imageName,
          );
          await temporary.writeAsBytes(recombined, flush: true);
        } else {
          final response = await _dio.request<ResponseBody>(
            requestUrl,
            options: Options(
              method: method,
              headers: headers,
              responseType: ResponseType.stream,
            ),
            cancelToken: cancelToken,
          );
          if (task.status != DownloadStatus.downloading) return;
          final body = response.data;
          if (body == null) {
            throw StateError('图片 ${index + 1} 返回空数据');
          }
          final sink = temporary.openWrite();
          try {
            await sink.addStream(body.stream);
            await sink.flush();
          } finally {
            await sink.close();
          }
          if (await temporary.length() == 0) {
            throw StateError('图片 ${index + 1} 返回空数据');
          }
        }
        if (task.status != DownloadStatus.downloading) return;
        if (await target.exists()) {
          await _assertManagedPath(target.path);
          await target.delete();
        }
        await _renameManagedFile(temporary, target);
        task.completedCount = index + 1;
        task.errorMessage = null;
        _helper.update(task);
        _notify();
      }

      if (task.status != DownloadStatus.downloading) return;
      await _deleteDirectoryIfPresent(finalDirectory);
      await _renameManagedDirectory(partialDirectory, finalDirectory);
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
    if (deleteFiles && task.directory != null && task.directory!.isNotEmpty) {
      await _assertManagedPath(task.directory!);
      await _assertManagedPath('${task.directory}.part');
    }
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

  /// Deletes completed downloads and their partial files through the existing
  /// managed-path checks. This explicit API is intentionally separate from
  /// [clearCompleted], which only removes queue metadata.
  Future<void> clearCompletedSafely() async {
    final ids = _tasks
        .where((task) => task.status == DownloadStatus.completed)
        .map((task) => task.id!)
        .toList();
    for (final id in ids) {
      await deleteFiles(id);
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

  Future<void> _deleteDirectoryIfPresent(Directory directory) async {
    await _assertManagedPath(directory.path);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> _renameManagedFile(File source, File target) async {
    await _assertManagedPath(source.path);
    await _assertManagedPath(target.path);
    await source.rename(target.path);
  }

  Future<void> _renameManagedDirectory(
    Directory source,
    Directory target,
  ) async {
    await _assertManagedPath(source.path);
    await _assertManagedPath(target.path);
    await source.rename(target.path);
  }

  Future<void> _assertManagedPath(String candidatePath) async {
    final root = _canonicalDownloadRoot;
    if (root == null) throw StateError('DownloadManager not initialized');
    final candidate = await _canonicalPath(candidatePath);
    final comparableRoot = Platform.isWindows ? root.toLowerCase() : root;
    final comparableCandidate = Platform.isWindows
        ? candidate.toLowerCase()
        : candidate;
    if (p.equals(comparableRoot, comparableCandidate) ||
        !p.isWithin(comparableRoot, comparableCandidate)) {
      throw FileSystemException(
        'Refusing unsafe download path outside the managed root',
        candidatePath,
      );
    }
  }

  static Future<String> _canonicalPath(String input) async {
    var probe = p.normalize(p.absolute(input));
    final missingSegments = <String>[];
    while (await FileSystemEntity.type(probe, followLinks: true) ==
        FileSystemEntityType.notFound) {
      final parent = p.dirname(probe);
      if (p.equals(parent, probe)) {
        throw FileSystemException('Cannot canonicalize path', input);
      }
      missingSegments.insert(0, p.basename(probe));
      probe = parent;
    }
    final resolvedParent = await File(probe).resolveSymbolicLinks();
    return p.normalize(
      missingSegments.isEmpty
          ? resolvedParent
          : p.joinAll(<String>[resolvedParent, ...missingSegments]),
    );
  }

  static String _safeSegment(String value) {
    final trimmed = value.trim();
    if (trimmed == '.' || trimmed == '..') {
      throw ArgumentError.value(value, 'value', 'dot path segments are unsafe');
    }
    final safe = trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    if (safe == '.' || safe == '..') {
      throw ArgumentError.value(value, 'value', 'dot path segments are unsafe');
    }
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