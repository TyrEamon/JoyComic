import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:joycomic/foundation/cache_manager.dart';
import 'package:joycomic/foundation/download_manager.dart';
import 'package:joycomic/foundation/download_task.dart';

void main() {
  late Directory root;
  late Directory cache;
  late Directory temporary;
  late Directory logs;
  late Directory downloadTemporary;
  late Directory completedDownloads;
  late Directory database;
  late Directory sourceData;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('joycomic-cache-test-');
    cache = Directory(p.join(root.path, 'cache'))..createSync(recursive: true);
    temporary = Directory(p.join(root.path, 'temp'))
      ..createSync(recursive: true);
    logs = Directory(p.join(root.path, 'log'))..createSync(recursive: true);
    downloadTemporary = Directory(p.join(root.path, 'download-temp'))
      ..createSync(recursive: true);
    completedDownloads = Directory(p.join(root.path, 'completed-downloads'))
      ..createSync(recursive: true);
    database = Directory(p.join(root.path, 'db'))..createSync(recursive: true);
    sourceData = Directory(p.join(root.path, 'source-data'))
      ..createSync(recursive: true);
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  CacheManager manager({
    Future<void> Function()? onClearCompleted,
    PartialDownloadStore? partialDownloadStore,
  }) {
    return CacheManager(
      rootDirectory: root,
      cacheDirectory: cache,
      temporaryDirectory: temporary,
      logDirectory: logs,
      downloadTemporaryDirectory: downloadTemporary,
      onClearCompletedDownloads: onClearCompleted,
      partialDownloadStore: partialDownloadStore,
    );
  }

  Future<void> write(String path, int bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(bytes, 1));
  }

  test(
    'recursively totals cache, temp, logs, download temp, and image cache',
    () async {
      await write(p.join(cache.path, 'nested', 'cover.jpg'), 7);
      await write(p.join(temporary.path, 'nested', 'part.tmp'), 11);
      await write(p.join(logs.path, 'latest.log'), 13);
      await write(p.join(downloadTemporary.path, 'chapter.part'), 17);

      final result = await manager().calculateSize(imageCacheBytes: 19);

      expect(result.diskBytes, 48);
      expect(result.imageCacheBytes, 19);
      expect(result.totalBytes, 67);
    },
  );

  test(
    'isolates unreadable or missing cache entries while measuring the rest',
    () async {
      await write(p.join(cache.path, 'valid.bin'), 5);
      final missing = File(p.join(cache.path, 'missing.bin'));

      final result = await manager().calculateSize(
        extraPaths: [missing.path, p.join(root.path, 'outside.bin')],
      );

      expect(result.diskBytes, 5);
    },
  );

  test(
    'never follows symlinks or counts paths outside the root boundary',
    () async {
      await write(p.join(cache.path, 'inside.bin'), 3);
      await write(p.join(root.parent.path, 'outside.bin'), 29);
      final link = Link(p.join(cache.path, 'outside-link'));
      try {
        await link.create(root.parent.path);
      } on FileSystemException {
        return;
      }

      final result = await manager().calculateSize();

      expect(result.diskBytes, 3);
    },
  );

  test('clearSafeCaches removes only approved cache trees', () async {
    await write(p.join(cache.path, 'cover.bin'), 1);
    await write(p.join(temporary.path, 'part.bin'), 1);
    await write(p.join(logs.path, 'latest.log'), 1);
    await write(p.join(downloadTemporary.path, 'chapter.part'), 1);
    await write(p.join(completedDownloads.path, 'finished.cbz'), 1);
    await write(p.join(database.path, 'joycomic.db'), 1);
    await write(p.join(sourceData.path, 'account.json'), 1);

    await manager().clearSafeCaches();

    expect(await File(p.join(cache.path, 'cover.bin')).exists(), isFalse);
    expect(await File(p.join(temporary.path, 'part.bin')).exists(), isFalse);
    expect(await File(p.join(logs.path, 'latest.log')).exists(), isFalse);
    expect(
      await File(p.join(downloadTemporary.path, 'chapter.part')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(completedDownloads.path, 'finished.cbz')).exists(),
      isTrue,
    );
    expect(await File(p.join(database.path, 'joycomic.db')).exists(), isTrue);
    expect(
      await File(p.join(sourceData.path, 'account.json')).exists(),
      isTrue,
    );
  });

  test(
    'counts and clears only paused and failed task partial directories',
    () async {
      final downloads = Directory(p.join(root.path, 'downloads'))
        ..createSync(recursive: true);
      final paused = p.join(downloads.path, 'paused');
      final failed = p.join(downloads.path, 'failed');
      final active = p.join(downloads.path, 'active');
      final completed = p.join(downloads.path, 'completed');
      final stranger = p.join(downloads.path, 'stranger.part');
      for (final path in [paused, failed, active, completed]) {
        await Directory('$path.part').create(recursive: true);
      }
      await write(p.join('$paused.part', 'page.bin'), 2);
      await write(p.join('$failed.part', 'page.bin'), 3);
      await write(p.join('$active.part', 'page.bin'), 5);
      await write(p.join('$completed.part', 'page.bin'), 7);
      await write(p.join(stranger, 'page.bin'), 11);

      final store = _FakePartialDownloadStore([
        _partialTask(1, paused, DownloadStatus.paused),
        _partialTask(2, failed, DownloadStatus.failed),
        _partialTask(3, active, DownloadStatus.downloading),
        _partialTask(4, completed, DownloadStatus.completed),
      ]);
      final cache = manager(partialDownloadStore: store);

      final result = await cache.calculateSize();
      expect(result.diskBytes, 5);

      await cache.clearSafeCaches();
      expect(store.clearedIds, [1, 2]);
      expect(await Directory('$paused.part').exists(), isFalse);
      expect(await Directory('$failed.part').exists(), isFalse);
      expect(await Directory('$active.part').exists(), isTrue);
      expect(await Directory('$completed.part').exists(), isTrue);
      expect(await Directory(stranger).exists(), isTrue);
      expect(store.validatedPaths, contains('$paused.part'));
      expect(store.validatedPaths, contains('$failed.part'));
      expect(store.validatedPaths, isNot(contains('$active.part')));
    },
  );

  test(
    'skips partial paths rejected by the download manager boundary',
    () async {
      final downloads = Directory(p.join(root.path, 'downloads'))
        ..createSync(recursive: true);
      final unmanaged = p.join(downloads.path, 'unmanaged');
      await Directory('$unmanaged.part').create(recursive: true);
      await write(p.join('$unmanaged.part', 'page.bin'), 13);
      final store = _FakePartialDownloadStore([
        _partialTask(5, unmanaged, DownloadStatus.failed),
      ]);

      final result = await manager(partialDownloadStore: store).calculateSize();

      expect(result.diskBytes, 0);
      expect(await Directory('$unmanaged.part').exists(), isTrue);
    },
  );

  test('completed downloads require an explicit separate operation', () async {
    var called = 0;
    await manager(
      onClearCompleted: () async => called++,
    ).clearCompletedDownloads();

    expect(called, 1);
  });
}

class _FakePartialDownloadStore implements PartialDownloadStore {
  _FakePartialDownloadStore(this.tasks);

  @override
  final List<DownloadTask> tasks;
  final validatedPaths = <String>[];
  final clearedIds = <int>[];

  @override
  Future<void> validateManagedPath(String path) async {
    validatedPaths.add(path);
    if (path.contains('unmanaged')) {
      throw FileSystemException('outside managed download root', path);
    }
  }

  @override
  Future<bool> clearPartialDownload(DownloadTask task) async {
    final partial = Directory('${task.directory}.part');
    await validateManagedPath(partial.path);
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.completed) {
      return false;
    }
    clearedIds.add(task.id!);
    if (await partial.exists()) await partial.delete(recursive: true);
    return true;
  }
}

DownloadTask _partialTask(int id, String directory, DownloadStatus status) {
  return DownloadTask(
    id: id,
    comicId: 'comic-$id',
    sourceKey: 'jm',
    chapterId: 'chapter-$id',
    directory: directory,
    status: status,
  );
}
