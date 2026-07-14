/// Safe disk and Flutter image-cache management.
library cache_manager;

import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'download_manager.dart';
import 'download_task.dart';

/// The result of a cache size calculation.
class CacheSize {
  const CacheSize({required this.diskBytes, required this.imageCacheBytes});

  final int diskBytes;
  final int imageCacheBytes;

  int get totalBytes => diskBytes + imageCacheBytes;
}

/// A bounded cache cleaner.
///
/// Only directories explicitly supplied to this class are ever inspected or
/// deleted. Filesystem traversal does not follow symbolic links and every
/// path is checked against the configured root boundary before it is used.
class CacheManager {
  CacheManager({
    required Directory rootDirectory,
    required Directory cacheDirectory,
    required Directory temporaryDirectory,
    required Directory logDirectory,
    required Directory downloadTemporaryDirectory,
    this.onClearCompletedDownloads,
    this.partialDownloadStore,
    ImageCache? imageCache,
    Iterable<Directory>? securityRoots,
  })  : _rootDirectories = [
          rootDirectory,
          ...?securityRoots,
        ],
        _safeDirectories = [
          cacheDirectory,
          temporaryDirectory,
          logDirectory,
          downloadTemporaryDirectory,
        ],
        _imageCache = imageCache;

  /// Builds a manager for the real application directories.
  static Future<CacheManager> create({
    FutureOr<void> Function()? onClearCompletedDownloads,
  }) async {
    final cache = await getApplicationCacheDirectory();
    final temporary = await getTemporaryDirectory();
    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();
    final downloads = Directory(p.join(documents.path, 'downloads'));

    return CacheManager(
      rootDirectory: support,
      securityRoots: [cache, temporary, documents],
      cacheDirectory: cache,
      temporaryDirectory: temporary,
      logDirectory: Directory(p.join(cache.path, 'joycomic_logs')),
      downloadTemporaryDirectory: Directory(p.join(downloads.path, '.temp')),
      imageCache: PaintingBinding.instance.imageCache,
      onClearCompletedDownloads: onClearCompletedDownloads,
      partialDownloadStore: DownloadManager.instance,
    );
  }

  final List<Directory> _rootDirectories;
  final List<Directory> _safeDirectories;
  final ImageCache? _imageCache;
  final FutureOr<void> Function()? onClearCompletedDownloads;
  final PartialDownloadStore? partialDownloadStore;

  /// Calculates disk bytes plus Flutter's in-memory image cache bytes.
  Future<CacheSize> calculateSize({
    int? imageCacheBytes,
    Iterable<String> extraPaths = const <String>[],
  }) async {
    final seenFiles = <String>{};
    var diskBytes = 0;

    for (final directory in _safeDirectories) {
      diskBytes += await _directorySize(directory, seenFiles);
    }
    for (final target in await _partialDownloadTargets()) {
      diskBytes += await _directorySize(
        target.directory,
        seenFiles,
        allowOutsideSafeDirectory: true,
      );
    }

    // Extra paths are useful for diagnostics, but are still constrained to a
    // configured safe directory and root boundary.
    for (final path in extraPaths) {
      final normalized = _normalize(path);
      if (!_isInsideSafeDirectory(normalized)) continue;
      diskBytes += await _fileSize(File(normalized), seenFiles);
    }

    final memoryBytes = imageCacheBytes ?? _imageCache?.currentSizeBytes ?? 0;
    return CacheSize(diskBytes: diskBytes, imageCacheBytes: memoryBytes);
  }

  /// Alias kept for callers that use storage terminology.
  Future<CacheSize> getCacheSize({int? imageCacheBytes}) =>
      calculateSize(imageCacheBytes: imageCacheBytes);

  /// Removes cache/temp/log/incomplete-download contents only.
  Future<void> clearSafeCaches() async {
    for (final directory in _safeDirectories) {
      await _clearDirectoryContents(directory);
    }
    final store = partialDownloadStore;
    if (store != null) {
      for (final target in await _partialDownloadTargets()) {
        try {
          await store.clearPartialDownload(target.task);
        } catch (_) {
          // One unsafe or locked partial must not block other cache cleanup.
        }
      }
    }
    _imageCache?.clear();
    _imageCache?.clearLiveImages();
  }

  /// Explicitly invokes the dangerous completed-download deletion operation.
  ///
  /// This method is intentionally separate from [clearSafeCaches]. It never
  /// runs as part of ordinary cache cleanup.
  Future<void> clearCompletedDownloads() async {
    final cleaner = onClearCompletedDownloads;
    if (cleaner == null) {
      throw StateError('Completed-download deletion requires an explicit API');
    }
    await cleaner();
  }

  Future<List<_PartialDownloadTarget>> _partialDownloadTargets() async {
    final store = partialDownloadStore;
    if (store == null) return const <_PartialDownloadTarget>[];
    final targets = <_PartialDownloadTarget>[];
    final seen = <String>{};
    for (final task in store.tasks) {
      if (!_isPartialCacheStatus(task.status)) continue;
      final directory = task.directory;
      if (directory == null || directory.isEmpty) continue;
      final path = _normalize('$directory.part');
      if (!seen.add(path) || !_isAllowedPath(path)) continue;
      try {
        await store.validateManagedPath(path);
        if (await FileSystemEntity.type(path, followLinks: false) ==
            FileSystemEntityType.directory) {
          targets.add(_PartialDownloadTarget(task, Directory(path)));
        }
      } catch (_) {
        // Invalid, escaped, linked, missing, or unreadable task paths are skipped.
      }
    }
    return targets;
  }

  static bool _isPartialCacheStatus(DownloadStatus status) =>
      status == DownloadStatus.pending ||
      status == DownloadStatus.paused ||
      status == DownloadStatus.failed;

  Future<int> _directorySize(
    Directory directory,
    Set<String> seenFiles, {
    bool allowOutsideSafeDirectory = false,
  }) async {
    final path = _normalize(directory.path);
    if (!_isAllowedPath(path) ||
        (!allowOutsideSafeDirectory && !_isInsideSafeDirectory(path))) {
      return 0;
    }

    try {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return 0;
      }
      var bytes = 0;
      await for (final entity in Directory(path).list(followLinks: false)) {
        final entityPath = _normalize(entity.path);
        if (!_isAllowedPath(entityPath)) continue;
        try {
          final type = await FileSystemEntity.type(entityPath, followLinks: false);
          if (type == FileSystemEntityType.file) {
            bytes += await _fileSize(
              File(entityPath),
              seenFiles,
              allowOutsideSafeDirectory: allowOutsideSafeDirectory,
            );
          } else if (type == FileSystemEntityType.directory) {
            bytes += await _directorySize(
              Directory(entityPath),
              seenFiles,
              allowOutsideSafeDirectory: allowOutsideSafeDirectory,
            );
          }
        } catch (_) {
          // One broken entry must not hide the rest of the cache.
        }
      }
      return bytes;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _fileSize(
    File file,
    Set<String> seenFiles, {
    bool allowOutsideSafeDirectory = false,
  }) async {
    final path = _normalize(file.path);
    if (!_isAllowedPath(path) ||
        (!allowOutsideSafeDirectory && !_isInsideSafeDirectory(path))) {
      return 0;
    }
    if (!seenFiles.add(path)) return 0;

    try {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        return 0;
      }
      return await file.length();
    } catch (_) {
      seenFiles.remove(path);
      return 0;
    }
  }

  Future<void> _clearDirectoryContents(Directory directory) async {
    final path = _normalize(directory.path);
    if (!_isAllowedPath(path)) return;

    try {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return;
      }
      await for (final entity in Directory(path).list(followLinks: false)) {
        final entityPath = _normalize(entity.path);
        if (!_isAllowedPath(entityPath)) continue;
        try {
          final type = await FileSystemEntity.type(entityPath, followLinks: false);
          if (type == FileSystemEntityType.file) {
            await File(entityPath).delete();
          } else if (type == FileSystemEntityType.directory) {
            await _clearDirectoryContents(Directory(entityPath));
            await Directory(entityPath).delete();
          }
        } catch (_) {
          // Keep clearing siblings when one file is locked or malformed.
        }
      }
    } catch (_) {
      // The target itself may disappear while cleanup is running.
    }
  }

  String _normalize(String path) => p.normalize(p.absolute(path));

  bool _isAllowedPath(String path) {
    return _rootDirectories.any((root) => _isWithin(_normalize(root.path), path));
  }

  bool _isInsideSafeDirectory(String path) {
    return _safeDirectories.any((directory) =>
        _isWithin(_normalize(directory.path), path));
  }

  bool _isWithin(String root, String path) {
    if (root == path) return true;
    final relative = p.relative(path, from: root);
    return relative != '..' && !relative.startsWith('..${p.separator}') &&
        !p.isAbsolute(relative);
  }
}

/// Formats byte counts for settings and diagnostics surfaces.
String formatCacheBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class _PartialDownloadTarget {
  const _PartialDownloadTarget(this.task, this.directory);

  final DownloadTask task;
  final Directory directory;
}