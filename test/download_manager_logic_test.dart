import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/database/download_helper.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/foundation/download_manager.dart';
import 'package:joycomic/foundation/download_task.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/views/reader/reader.dart';
import 'package:joycomic/views/reader/state/comic_state.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('DownloadTask identity and state machine', () {
    test('identity is source comic and chapter', () {
      const first = DownloadIdentity('jm', 'comic', 'chapter');
      const same = DownloadIdentity('jm', 'comic', 'chapter');
      const otherSource = DownloadIdentity('picacg', 'comic', 'chapter');

      expect(first, same);
      expect(first.hashCode, same.hashCode);
      expect(first, isNot(otherSource));
    });

    test('accepts only declared state transitions', () {
      final task = _task();

      task.transitionTo(DownloadStatus.downloading);
      task.transitionTo(DownloadStatus.paused);
      task.transitionTo(DownloadStatus.downloading);
      task.transitionTo(DownloadStatus.failed);
      task.transitionTo(DownloadStatus.downloading);
      task.transitionTo(DownloadStatus.completed);

      expect(() => task.transitionTo(DownloadStatus.pending), throwsStateError);
      expect(() => task.transitionTo(DownloadStatus.failed), throwsStateError);
    });
  });

  group('download schema and helper', () {
    late Database db;
    late DownloadHelper helper;

    setUp(() {
      db = sqlite3.openInMemory();
      JoyDatabase.migrateDownloads(db);
      helper = DownloadHelper(db);
    });

    tearDown(() => db.dispose());

    test('duplicate enqueue returns the existing persisted task', () {
      final first = helper.enqueue(_task(title: 'Original'));
      final duplicate = helper.enqueue(_task(title: 'Duplicate'));

      expect(duplicate.id, first.id);
      expect(duplicate.title, 'Original');
      expect(helper.getAll(), hasLength(1));
    });

    test('round trips chapter metadata and ordered page urls', () {
      final original =
          _task(
              title: 'Comic title',
              coverUrl: 'https://cover',
              chapterTitle: 'Chapter title',
            )
            ..pageUrls = <String>['https://page/2', 'https://page/1']
            ..completedCount = 1
            ..directory = p.join('root', 'chapter')
            ..errorMessage = 'network error';
      final saved = helper.enqueue(original);
      saved.transitionTo(DownloadStatus.downloading);
      saved.transitionTo(DownloadStatus.failed);
      helper.update(saved);

      final restored = helper.find(saved.identity)!;
      expect(restored.title, 'Comic title');
      expect(restored.coverUrl, 'https://cover');
      expect(restored.chapterTitle, 'Chapter title');
      expect(restored.pageUrls, <String>['https://page/2', 'https://page/1']);
      expect(restored.completedCount, 1);
      expect(restored.directory, p.join('root', 'chapter'));
      expect(restored.errorMessage, 'network error');
      expect(restored.status, DownloadStatus.failed);
    });

    test('migrates legacy rows and enforces the chapter unique index', () {
      final legacy = sqlite3.openInMemory();
      addTearDown(legacy.dispose);
      legacy.execute('''
        CREATE TABLE downloads (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          comic_id TEXT NOT NULL,
          source_key TEXT NOT NULL,
          chapter_id TEXT NOT NULL,
          url TEXT NOT NULL,
          file_name TEXT,
          file_path TEXT,
          status TEXT NOT NULL DEFAULT 'pending',
          progress REAL NOT NULL DEFAULT 0.0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      legacy.execute(
        'INSERT INTO downloads '
        '(comic_id, source_key, chapter_id, url, status, progress, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          'comic',
          'jm',
          'chapter',
          'https://old/1.jpg',
          'pending',
          0,
          1,
          1,
        ],
      );
      legacy.execute(
        'INSERT INTO downloads '
        '(comic_id, source_key, chapter_id, url, status, progress, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          'comic',
          'jm',
          'chapter',
          'https://new/1.jpg',
          'failed',
          0,
          2,
          2,
        ],
      );

      JoyDatabase.migrateDownloads(legacy);
      JoyDatabase.migrateDownloads(legacy);

      final migrated = DownloadHelper(legacy).getAll();
      expect(migrated, hasLength(1));
      expect(migrated.single.pageUrls, <String>['https://new/1.jpg']);
      expect(
        () => legacy.execute(
          'INSERT INTO downloads '
          '(source_key, comic_id, chapter_id, title, cover_url, chapter_title, '
          'page_urls, completed_count, directory, status, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            'jm',
            'comic',
            'chapter',
            '',
            '',
            '',
            '[]',
            0,
            '',
            'pending',
            3,
            3,
          ],
        ),
        throwsA(anything),
      );
    });
  });

  group('DownloadManager chapter worker', () {
    late Database db;
    late DownloadHelper helper;
    late Directory temp;
    late HttpServer server;
    late Uri baseUri;
    late Map<String, int> hits;
    late List<String?> authHeaders;

    setUp(() async {
      db = sqlite3.openInMemory();
      JoyDatabase.migrateDownloads(db);
      helper = DownloadHelper(db);
      temp = await Directory.systemTemp.createTemp('joycomic-download-test-');
      hits = <String, int>{};
      authHeaders = <String?>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUri = Uri.parse('http://${server.address.host}:${server.port}/');
      unawaited(_serve(server, hits, authHeaders));
    });

    tearDown(() async {
      await server.close(force: true);
      db.dispose();
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test(
      'deduplicates concurrent enqueue and saves ordered pages atomically',
      () async {
        final source = _source(
          pages: <String>[
            baseUri.resolve('page-1.jpg').toString(),
            baseUri.resolve('page-2.jpg').toString(),
          ],
        );
        final manager = _manager(helper, temp, source);
        addTearDown(manager.dispose);

        await manager.initialize();
        final results = await Future.wait(<Future<DownloadTask>>[
          manager.enqueue(
            sourceKey: 'test',
            comicId: 'comic',
            chapterId: 'chapter',
            title: 'Comic',
            coverUrl: 'cover',
            chapterTitle: 'Chapter',
          ),
          manager.enqueue(
            sourceKey: 'test',
            comicId: 'comic',
            chapterId: 'chapter',
            title: 'Comic',
            coverUrl: 'cover',
            chapterTitle: 'Chapter',
          ),
        ]);
        await manager.whenIdle();

        expect(results[0].id, results[1].id);
        final completed = manager.tasks.single;
        expect(completed.status, DownloadStatus.completed);
        expect(completed.completedCount, 2);
        expect(completed.pageUrls, hasLength(2));
        expect(completed.localPagePaths.map(p.basename), <String>[
          '000001.jpg',
          '000002.jpg',
        ]);
        expect(
          await File(completed.localPagePaths[0]).readAsBytes(),
          Uint8List.fromList(<int>[1, 2, 3]),
        );
        expect(
          await File(completed.localPagePaths[1]).readAsBytes(),
          Uint8List.fromList(<int>[4, 5, 6]),
        );
        expect(
          await Directory('${completed.directory}.part').exists(),
          isFalse,
        );
        expect(authHeaders, everyElement('download-test'));
        expect(helper.find(completed.identity)?.completedCount, 2);
      },
    );

    test('persists failure and resumes from completed pages', () async {
      final source = _source(
        pages: <String>[
          baseUri.resolve('page-1.jpg').toString(),
          baseUri.resolve('flaky.jpg').toString(),
        ],
      );
      final manager = _manager(helper, temp, source);
      addTearDown(manager.dispose);
      await manager.initialize();

      final task = await manager.enqueue(
        sourceKey: 'test',
        comicId: 'comic',
        chapterId: 'flaky',
        title: 'Comic',
        coverUrl: '',
        chapterTitle: 'Flaky',
      );
      await manager.whenIdle();

      expect(task.status, DownloadStatus.failed);
      expect(task.completedCount, 1);
      expect(task.errorMessage, contains('500'));
      expect(await manager.resume(task.id!), isTrue);
      await manager.whenIdle();

      expect(task.status, DownloadStatus.completed);
      expect(task.completedCount, 2);
      expect(hits['/page-1.jpg'], 1);
      expect(hits['/flaky.jpg'], 2);
    });

    test('pause rejects invalid states and a paused task can resume', () async {
      final source = _source(
        pages: <String>[baseUri.resolve('slow.jpg').toString()],
      );
      final manager = _manager(helper, temp, source);
      addTearDown(manager.dispose);
      await manager.initialize();
      final task = await manager.enqueue(
        sourceKey: 'test',
        comicId: 'comic',
        chapterId: 'slow',
        title: 'Comic',
        coverUrl: '',
        chapterTitle: 'Slow',
      );
      await _waitFor(() => task.status == DownloadStatus.downloading);

      expect(await manager.pause(task.id!), isTrue);
      expect(task.status, DownloadStatus.paused);
      expect(await manager.pause(task.id!), isFalse);
      expect(await manager.resume(task.id!), isTrue);
      await manager.whenIdle();
      expect(task.status, DownloadStatus.completed);
      expect(await manager.resume(task.id!), isFalse);
    });

    test('restart recovers downloading rows and finishes them', () async {
      final persisted = helper.enqueue(
        _task(sourceKey: 'test', chapterId: 'restart'),
      );
      persisted.pageUrls = <String>[baseUri.resolve('page-1.jpg').toString()];
      persisted.directory = p.join(temp.path, 'old-directory');
      persisted.transitionTo(DownloadStatus.downloading);
      helper.update(persisted);
      final source = _source(pages: persisted.pageUrls);
      final manager = _manager(helper, temp, source);
      addTearDown(manager.dispose);

      await manager.initialize();
      await manager.whenIdle();

      expect(manager.tasks.single.status, DownloadStatus.completed);
      expect(manager.tasks.single.completedCount, 1);
    });

    test('task deletion and file deletion have separate boundaries', () async {
      final source = _source(
        pages: <String>[baseUri.resolve('page-1.jpg').toString()],
      );
      final manager = _manager(helper, temp, source);
      addTearDown(manager.dispose);
      await manager.initialize();
      final keepFiles = await manager.enqueue(
        sourceKey: 'test',
        comicId: 'comic',
        chapterId: 'keep-files',
        title: 'Comic',
        coverUrl: '',
        chapterTitle: 'Keep',
      );
      await manager.whenIdle();
      final keptDirectory = Directory(keepFiles.directory!);

      expect(await manager.deleteTask(keepFiles.id!), isTrue);
      expect(await keptDirectory.exists(), isTrue);
      expect(helper.find(keepFiles.identity), isNull);

      final deleteFiles = await manager.enqueue(
        sourceKey: 'test',
        comicId: 'comic',
        chapterId: 'delete-files',
        title: 'Comic',
        coverUrl: '',
        chapterTitle: 'Delete',
      );
      await manager.whenIdle();
      final deletedDirectory = Directory(deleteFiles.directory!);

      expect(await manager.deleteFiles(deleteFiles.id!), isTrue);
      expect(await deletedDirectory.exists(), isFalse);
      expect(helper.find(deleteFiles.identity), isNull);
      expect(await manager.deleteFiles(-1), isFalse);
    });

    test(
      'completed task creates local reader state with ordered file paths',
      () async {
        final directory = await Directory(
          p.join(temp.path, 'offline'),
        ).create();
        final task = _task(chapterId: 'offline')
          ..pageUrls = <String>['https://page/one.png', 'https://page/two.webp']
          ..completedCount = 2
          ..directory = directory.path;
        task.transitionTo(DownloadStatus.downloading);
        task.transitionTo(DownloadStatus.completed);

        final state = ComicState.fromDownload(task);

        expect(state.type, ReaderType.local);
        expect(state.localPagePaths, <String>[
          p.join(directory.path, '000001.png'),
          p.join(directory.path, '000002.webp'),
        ]);
        expect(state.chapter.id, 'offline');
        expect(state.chapters, hasLength(1));
      },
    );
  });
  group('secure legacy download lifecycle', () {
    test(
      'moves a legacy completed file into a readable chapter directory',
      () async {
        final db = sqlite3.openInMemory();
        final root = await Directory.systemTemp.createTemp('joycomic-legacy-');
        addTearDown(db.dispose);
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });
        final legacyFile = File(p.join(root.path, '7_legacy.jpg'));
        await legacyFile.writeAsBytes(<int>[9, 8, 7], flush: true);
        db.execute('''
        CREATE TABLE downloads (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          comic_id TEXT NOT NULL,
          source_key TEXT NOT NULL,
          chapter_id TEXT NOT NULL,
          url TEXT NOT NULL,
          file_name TEXT,
          file_path TEXT,
          status TEXT NOT NULL DEFAULT 'pending',
          progress REAL NOT NULL DEFAULT 0.0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
        db.execute(
          'INSERT INTO downloads '
          '(comic_id, source_key, chapter_id, url, file_name, file_path, status, progress, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            'legacy-comic',
            'test',
            'legacy-chapter',
            'https://legacy/page.jpg',
            'page.jpg',
            legacyFile.path,
            'completed',
            1,
            1,
            1,
          ],
        );
        JoyDatabase.migrateDownloads(db);
        final helper = DownloadHelper(db);
        final manager = DownloadManager.forTesting(
          helper: helper,
          downloadDirectory: root,
          sourceResolver: (_) => null,
        );
        addTearDown(manager.dispose);

        await manager.initialize();

        final task = manager.tasks.single;
        expect(task.status, DownloadStatus.completed);
        expect(p.equals(task.directory!, root.path), isFalse);
        expect(p.isWithin(root.path, task.directory!), isTrue);
        expect(task.localPagePaths, hasLength(1));
        expect(await File(task.localPagePaths.single).readAsBytes(), <int>[
          9,
          8,
          7,
        ]);
        expect(helper.getById(task.id!)?.legacyFilePath, isNull);
      },
    );

    test(
      'rebuilds empty pending and failed directories under the root',
      () async {
        final db = sqlite3.openInMemory();
        final root = await Directory.systemTemp.createTemp(
          'joycomic-empty-dir-',
        );
        addTearDown(db.dispose);
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });
        JoyDatabase.migrateDownloads(db);
        final helper = DownloadHelper(db);
        helper.enqueue(_task(sourceKey: 'test', chapterId: 'pending'));
        final failed = helper.enqueue(
          _task(sourceKey: 'test', chapterId: 'failed'),
        );
        failed.transitionTo(DownloadStatus.downloading);
        failed.transitionTo(DownloadStatus.failed);
        helper.update(failed);
        final source = _source(pages: const <String>[]);
        final manager = DownloadManager.forTesting(
          helper: helper,
          downloadDirectory: root,
          sourceResolver: (_) => source,
          maxConcurrent: 1,
        );
        addTearDown(manager.dispose);

        await manager.initialize();
        await manager.whenIdle();

        for (final task in manager.tasks) {
          expect(task.directory, isNotEmpty);
          expect(p.isWithin(root.path, task.directory!), isTrue);
          expect(p.equals(root.path, task.directory!), isFalse);
        }
      },
    );

    test(
      'deleting one chapter preserves root and sibling and rejects unsafe paths',
      () async {
        final db = sqlite3.openInMemory();
        final root = await Directory.systemTemp.createTemp(
          'joycomic-delete-safe-',
        );
        final outside = await Directory.systemTemp.createTemp(
          'joycomic-outside-',
        );
        addTearDown(db.dispose);
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
          if (await outside.exists()) await outside.delete(recursive: true);
        });
        JoyDatabase.migrateDownloads(db);
        final helper = DownloadHelper(db);
        final firstDir = await Directory(p.join(root.path, 'first')).create();
        final secondDir = await Directory(p.join(root.path, 'second')).create();
        await File(p.join(firstDir.path, '000001.jpg')).writeAsBytes(<int>[1]);
        final sibling = File(p.join(secondDir.path, '000001.jpg'));
        await sibling.writeAsBytes(<int>[2]);
        final first = helper.enqueue(_completedTask('first', firstDir.path));
        helper.enqueue(_completedTask('second', secondDir.path));
        final unsafe = helper.enqueue(_completedTask('unsafe', outside.path));
        final rootTask = helper.enqueue(_completedTask('root', root.path));
        final manager = DownloadManager.forTesting(
          helper: helper,
          downloadDirectory: root,
          sourceResolver: (_) => null,
        );
        addTearDown(manager.dispose);
        await manager.initialize();

        expect(await manager.deleteFiles(first.id!), isTrue);
        expect(await root.exists(), isTrue);
        expect(await sibling.exists(), isTrue);
        await expectLater(
          manager.deleteFiles(unsafe.id!),
          throwsA(isA<FileSystemException>()),
        );
        await expectLater(
          manager.deleteFiles(rootTask.id!),
          throwsA(isA<FileSystemException>()),
        );
        expect(await outside.exists(), isTrue);
        expect(await root.exists(), isTrue);
        expect(helper.getById(unsafe.id!), isNotNull);
        expect(helper.getById(rootTask.id!), isNotNull);
      },
    );

    test('rejects dot path segments before inserting a task', () async {
      final db = sqlite3.openInMemory();
      final root = await Directory.systemTemp.createTemp(
        'joycomic-dot-segment-',
      );
      addTearDown(db.dispose);
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      JoyDatabase.migrateDownloads(db);
      final helper = DownloadHelper(db);
      final manager = DownloadManager.forTesting(
        helper: helper,
        downloadDirectory: root,
        sourceResolver: (_) => null,
      );
      addTearDown(manager.dispose);
      await manager.initialize();

      await expectLater(
        manager.enqueue(
          sourceKey: 'test',
          comicId: 'comic',
          chapterId: '..',
          title: 'Comic',
          coverUrl: '',
          chapterTitle: 'Unsafe',
        ),
        throwsArgumentError,
      );
      expect(helper.count(), 0);
    });
    test(
      'quarantines persisted dot segments instead of aborting startup',
      () async {
        final db = sqlite3.openInMemory();
        final root = await Directory.systemTemp.createTemp(
          'joycomic-persisted-dot-segment-',
        );
        addTearDown(db.dispose);
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });
        JoyDatabase.migrateDownloads(db);
        final helper = DownloadHelper(db);
        final unsafe = helper.enqueue(
          _task(sourceKey: 'test', chapterId: '..'),
        );
        unsafe.transitionTo(DownloadStatus.downloading);
        unsafe.transitionTo(DownloadStatus.failed);
        helper.update(unsafe);
        final manager = DownloadManager.forTesting(
          helper: helper,
          downloadDirectory: root,
          sourceResolver: (_) => null,
        );
        addTearDown(manager.dispose);

        await manager.initialize();

        final loaded = manager.tasks.single;
        expect(loaded.status, DownloadStatus.failed);
        expect(loaded.completedCount, 0);
        expect(loaded.errorMessage, contains('dot path segments'));
        expect(
          helper.getById(loaded.id!)?.errorMessage,
          contains('dot path segments'),
        );
      },
    );
  });

  group('local reader resolution', () {
    test(
      'route does not inject network loader and Reader resolves local paths first',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'joycomic-reader-local-',
        );
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });
        final page = File(p.join(directory.path, '000001.jpg'));
        await page.writeAsBytes(<int>[1]);
        final task = _completedTask('offline', directory.path);
        final state = ComicState.fromDownload(task);
        var networkCalls = 0;
        final source = ComicSource.named(
          name: 'Offline must not call',
          key: 'test',
          filePath: 'test',
          loadComicPages: (_, __) async {
            networkCalls++;
            return const Res<List<String>>.error('offline');
          },
        );

        expect(readerRouteNetworkLoader(state, source), isNull);
        final loader = resolveReaderImageLoader(
          state: state,
          supplied: (_, __) async {
            networkCalls++;
            return const Res<List<String>>.error('offline');
          },
          source: source,
        );
        final result = await loader!(state.id, state.chapter.id);

        expect(result.data, <String>[page.path]);
        expect(networkCalls, 0);
      },
    );
  });

  group('scheduler persistence failure', () {
    test('rolls back active state and continues with the next task', () async {
      final db = sqlite3.openInMemory();
      final root = await Directory.systemTemp.createTemp(
        'joycomic-schedule-fault-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(db.dispose);
      addTearDown(() async {
        await server.close(force: true);
        if (await root.exists()) await root.delete(recursive: true);
      });
      unawaited(_serve(server, <String, int>{}, <String?>[]));
      JoyDatabase.migrateDownloads(db);
      final helper = _SchedulingFaultDownloadHelper(db, 'blocked');
      helper.enqueue(_task(sourceKey: 'test', chapterId: 'next'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      helper.enqueue(_task(sourceKey: 'test', chapterId: 'blocked'));
      final page = 'http://${server.address.host}:${server.port}/page-1.jpg';
      final source = _source(pages: <String>[page]);
      final manager = DownloadManager.forTesting(
        helper: helper,
        downloadDirectory: root,
        sourceResolver: (_) => source,
        maxConcurrent: 1,
      );
      addTearDown(manager.dispose);

      await manager.initialize();
      await _waitFor(
        () =>
            manager.findTask('test', 'comic', 'next')?.status ==
            DownloadStatus.completed,
      );

      final blocked = manager.findTask('test', 'comic', 'blocked')!;
      expect(blocked.status, DownloadStatus.pending);
      expect(helper.getById(blocked.id!)?.status, DownloadStatus.pending);
      expect(manager.activeCount, 0);
      expect(helper.scheduleFailures, greaterThan(0));
    });
  });

  group('streaming non-JM downloads', () {
    test(
      'requests a stream and writes a large response to the page file',
      () async {
        final db = sqlite3.openInMemory();
        final root = await Directory.systemTemp.createTemp('joycomic-stream-');
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(db.dispose);
        addTearDown(() async {
          await server.close(force: true);
          if (await root.exists()) await root.delete(recursive: true);
        });
        unawaited(_serve(server, <String, int>{}, <String?>[]));
        JoyDatabase.migrateDownloads(db);
        final helper = DownloadHelper(db);
        final responseTypes = <ResponseType>[];
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                responseTypes.add(options.responseType);
                handler.next(options);
              },
            ),
          );
        final page = 'http://${server.address.host}:${server.port}/large.bin';
        final source = _source(pages: <String>[page]);
        final manager = DownloadManager.forTesting(
          helper: helper,
          downloadDirectory: root,
          sourceResolver: (_) => source,
          dio: dio,
        );
        addTearDown(manager.dispose);
        await manager.initialize();
        final task = await manager.enqueue(
          sourceKey: 'test',
          comicId: 'comic',
          chapterId: 'large',
          title: 'Large',
          coverUrl: '',
          chapterTitle: 'Large',
        );
        await manager.whenIdle();

        expect(task.status, DownloadStatus.completed);
        expect(responseTypes, contains(ResponseType.stream));
        expect(
          await File(task.localPagePaths.single).length(),
          2 * 1024 * 1024,
        );
      },
    );
  });
}

DownloadTask _completedTask(String chapterId, String directory) {
  final task = _task(sourceKey: 'test', chapterId: chapterId)
    ..pageUrls = <String>['https://page/$chapterId.jpg']
    ..completedCount = 1
    ..directory = directory;
  task.transitionTo(DownloadStatus.downloading);
  task.transitionTo(DownloadStatus.completed);
  return task;
}

class _SchedulingFaultDownloadHelper extends DownloadHelper {
  _SchedulingFaultDownloadHelper(super.database, this.blockedChapter);

  final String blockedChapter;
  int scheduleFailures = 0;

  @override
  void update(DownloadTask task) {
    if (task.chapterId == blockedChapter &&
        task.status == DownloadStatus.downloading) {
      scheduleFailures++;
      throw StateError('injected scheduling persistence failure');
    }
    super.update(task);
  }
}

DownloadTask _task({
  String sourceKey = 'jm',
  String comicId = 'comic',
  String chapterId = 'chapter',
  String title = 'Title',
  String coverUrl = '',
  String chapterTitle = 'Chapter',
}) {
  return DownloadTask(
    sourceKey: sourceKey,
    comicId: comicId,
    chapterId: chapterId,
    title: title,
    coverUrl: coverUrl,
    chapterTitle: chapterTitle,
  );
}

ComicSource _source({required List<String> pages}) {
  return ComicSource.named(
    name: 'Test',
    key: 'test',
    filePath: 'test',
    loadComicPages: (_, __) async => Res<List<String>>(pages),
    getImageLoadingConfig: (_, __, ___) => <String, dynamic>{
      'X-Download-Test': 'download-test',
    },
  );
}

DownloadManager _manager(
  DownloadHelper helper,
  Directory directory,
  ComicSource source,
) {
  return DownloadManager.forTesting(
    helper: helper,
    downloadDirectory: directory,
    sourceResolver: (key) => key == source.key ? source : null,
    maxConcurrent: 2,
  );
}

Future<void> _serve(
  HttpServer server,
  Map<String, int> hits,
  List<String?> authHeaders,
) async {
  await for (final request in server) {
    final path = request.uri.path;
    hits[path] = (hits[path] ?? 0) + 1;
    authHeaders.add(request.headers.value('X-Download-Test'));
    if (path == '/flaky.jpg' && hits[path] == 1) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
      continue;
    }
    if (path == '/large.bin') {
      request.response.statusCode = HttpStatus.ok;
      final chunk = List<int>.filled(32 * 1024, 7);
      for (var i = 0; i < 64; i++) {
        request.response.add(chunk);
      }
      await request.response.close();
      continue;
    }
    if (path == '/slow.jpg') {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    request.response.statusCode = HttpStatus.ok;
    request.response.add(
      path == '/page-2.jpg' ? <int>[4, 5, 6] : <int>[1, 2, 3],
    );
    await request.response.close();
  }
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final limit = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(limit)) {
      throw TimeoutException('condition was not reached', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
