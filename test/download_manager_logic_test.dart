import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/database/download_helper.dart';
import 'package:joycomic/database/joy_database.dart';
import 'package:joycomic/foundation/download_manager.dart';
import 'package:joycomic/foundation/download_task.dart';
import 'package:joycomic/network/res.dart';
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
