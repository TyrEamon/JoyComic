// JoyComic 数据库基础设施。
//
// 多库隔离设计：每条数据线一个独立的 .db 文件，避免锁竞争。
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../foundation/log.dart';

typedef DatabaseDirectoryProvider = Future<String> Function();
typedef DatabaseOpener = Database Function(String path);
typedef DatabaseMigrator = void Function(Database database);

/// 数据库管理器（单例）。
class JoyDatabase {
  JoyDatabase._()
    : _databaseDirectory = _defaultDatabaseDirectory,
      _openDatabase = sqlite3.open,
      _coreMigrator = migrateCore,
      _downloadMigrator = _migrateDownloads;

  JoyDatabase.forTesting({
    required DatabaseDirectoryProvider databaseDirectory,
    required DatabaseOpener openDatabase,
    DatabaseMigrator coreMigrator = migrateCore,
    DatabaseMigrator downloadMigrator = _migrateDownloads,
  }) : _databaseDirectory = databaseDirectory,
       _openDatabase = openDatabase,
       _coreMigrator = coreMigrator,
       _downloadMigrator = downloadMigrator;

  static final JoyDatabase instance = JoyDatabase._();

  /// 核心库当前 schema 版本。
  static const int coreSchemaVersion = 1;

  final DatabaseDirectoryProvider _databaseDirectory;
  final DatabaseOpener _openDatabase;
  final DatabaseMigrator _coreMigrator;
  final DatabaseMigrator _downloadMigrator;

  bool _initialized = false;
  Future<void>? _initializeFuture;
  Database? _coreDb;
  Database? _downloadDb;

  Database get core =>
      _coreDb ?? (throw StateError('JoyDatabase not initialized'));
  Database get downloadDb =>
      _downloadDb ?? (throw StateError('JoyDatabase not initialized'));

  /// 初始化数据库（应用启动时调用）。并发调用共享同一个 Future。
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initializeFuture ??= _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    Database? coreDatabase;
    Database? downloadDatabase;
    try {
      final directory = await _databaseDirectory();
      coreDatabase = _openDatabase(p.join(directory, 'joycomic.db'));
      downloadDatabase = _openDatabase(p.join(directory, 'downloads.db'));

      _coreMigrator(coreDatabase);
      _downloadMigrator(downloadDatabase);

      _coreDb = coreDatabase;
      _downloadDb = downloadDatabase;
      _initialized = true;
      Log.i('Database initialized', 'joycomic.db + downloads.db');
    } catch (error, stackTrace) {
      _coreDb = null;
      _downloadDb = null;
      _initialized = false;
      try {
        coreDatabase?.dispose();
      } catch (_) {
        // 继续释放另一条连接，并保留最初的初始化异常。
      }
      try {
        downloadDatabase?.dispose();
      } catch (_) {
        // 保留最初的初始化异常。
      }
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (!_initialized) _initializeFuture = null;
    }
  }

  static Future<String> _defaultDatabaseDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'db'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory.path;
  }

  /// 对任意数据库连接执行核心库迁移，便于内存数据库测试。
  ///
  /// 所有结构变更都在同一事务内完成；发生异常时恢复迁移前状态。
  static void migrateCore(Database db, {void Function()? beforeCommit}) {
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute('''
        CREATE TABLE IF NOT EXISTS schema_meta (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          version INTEGER NOT NULL
        )
      ''');

      db.execute('''
        CREATE TABLE IF NOT EXISTS search_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          keyword TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL
        )
      ''');

      _migrateFavorites(db);
      _migrateReadRecords(db);

      db.execute('''
        CREATE TABLE IF NOT EXISTS image_sizes (
          image_id TEXT NOT NULL,
          comic_id TEXT NOT NULL,
          width INTEGER NOT NULL,
          height INTEGER NOT NULL,
          PRIMARY KEY (image_id, comic_id)
        )
      ''');

      db.execute(
        'INSERT INTO schema_meta (id, version) VALUES (1, ?) '
        'ON CONFLICT(id) DO UPDATE SET version = excluded.version',
        <Object?>[coreSchemaVersion],
      );
      beforeCommit?.call();
      db.execute('COMMIT');
    } catch (error, stackTrace) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {
        // 保留最初的迁移异常。
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static void _migrateFavorites(Database db) {
    if (!_tableExists(db, 'favorites')) {
      _createFavoritesTable(db);
      return;
    }

    var columns = _columnNames(db, 'favorites');
    _addColumnIfMissing(
      db,
      table: 'favorites',
      columns: columns,
      name: 'source_key',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _addColumnIfMissing(
      db,
      table: 'favorites',
      columns: columns,
      name: 'comic_id',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _addColumnIfMissing(
      db,
      table: 'favorites',
      columns: columns,
      name: 'title',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _addColumnIfMissing(
      db,
      table: 'favorites',
      columns: columns,
      name: 'cover_url',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _addColumnIfMissing(
      db,
      table: 'favorites',
      columns: columns,
      name: 'author',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _addColumnIfMissing(
      db,
      table: 'favorites',
      columns: columns,
      name: 'favorited_at',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );

    final primaryKey = _primaryKeyColumns(db, 'favorites');
    if (primaryKey.toSet().containsAll(<String>{'source_key', 'comic_id'}) &&
        primaryKey.length == 2) {
      return;
    }

    db.execute('DROP TABLE IF EXISTS favorites_migration');
    _createFavoritesTable(db, table: 'favorites_migration');
    db.execute('''
      INSERT OR REPLACE INTO favorites_migration
        (source_key, comic_id, title, cover_url, author, favorited_at)
      SELECT
        COALESCE(source_key, ''), COALESCE(comic_id, ''),
        COALESCE(title, ''), COALESCE(cover_url, ''),
        COALESCE(author, ''), COALESCE(favorited_at, 0)
      FROM favorites
      ORDER BY favorited_at ASC, rowid ASC
    ''');
    db.execute('DROP TABLE favorites');
    db.execute('ALTER TABLE favorites_migration RENAME TO favorites');
  }

  static void _migrateReadRecords(Database db) {
    if (!_tableExists(db, 'read_records')) {
      _createReadRecordsTable(db);
      return;
    }

    var columns = _columnNames(db, 'read_records');
    _addColumnIfMissing(
      db,
      table: 'read_records',
      columns: columns,
      name: 'source_key',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _addColumnIfMissing(
      db,
      table: 'read_records',
      columns: columns,
      name: 'comic_id',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _addColumnIfMissing(
      db,
      table: 'read_records',
      columns: columns,
      name: 'title',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _addColumnIfMissing(
      db,
      table: 'read_records',
      columns: columns,
      name: 'cover_url',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _addColumnIfMissing(
      db,
      table: 'read_records',
      columns: columns,
      name: 'author',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _addColumnIfMissing(
      db,
      table: 'read_records',
      columns: columns,
      name: 'chapter_id',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _addColumnIfMissing(
      db,
      table: 'read_records',
      columns: columns,
      name: 'chapter_title',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    _addColumnIfMissing(
      db,
      table: 'read_records',
      columns: columns,
      name: 'page_no',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    _addColumnIfMissing(
      db,
      table: 'read_records',
      columns: columns,
      name: 'page_count',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    _addColumnIfMissing(
      db,
      table: 'read_records',
      columns: columns,
      name: 'updated_at',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );

    if (_primaryKeyColumns(db, 'read_records').join(',') ==
        'source_key,comic_id') {
      return;
    }

    db.execute('DROP TABLE IF EXISTS read_records_migration');
    _createReadRecordsTable(db, table: 'read_records_migration');
    db.execute('''
      INSERT INTO read_records_migration
        (source_key, comic_id, title, cover_url, author, chapter_id,
         chapter_title, page_no, page_count, updated_at)
      SELECT
        COALESCE(old.source_key, ''), COALESCE(old.comic_id, ''),
        COALESCE(old.title, ''), COALESCE(old.cover_url, ''),
        COALESCE(old.author, ''), COALESCE(old.chapter_id, ''),
        COALESCE(old.chapter_title, ''), COALESCE(old.page_no, 0),
        COALESCE(old.page_count, 0), COALESCE(old.updated_at, 0)
      FROM read_records AS old
      WHERE NOT EXISTS (
        SELECT 1 FROM read_records AS newer
        WHERE newer.source_key = old.source_key
          AND newer.comic_id = old.comic_id
          AND (
            COALESCE(newer.updated_at, 0) > COALESCE(old.updated_at, 0)
            OR (
              COALESCE(newer.updated_at, 0) = COALESCE(old.updated_at, 0)
              AND newer.rowid > old.rowid
            )
          )
      )
    ''');
    db.execute('DROP TABLE read_records');
    db.execute('ALTER TABLE read_records_migration RENAME TO read_records');
  }

  static void _createFavoritesTable(Database db, {String table = 'favorites'}) {
    db.execute('''
      CREATE TABLE $table (
        source_key TEXT NOT NULL,
        comic_id TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        cover_url TEXT NOT NULL DEFAULT '',
        author TEXT NOT NULL DEFAULT '',
        favorited_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (source_key, comic_id)
      )
    ''');
  }

  static void _createReadRecordsTable(
    Database db, {
    String table = 'read_records',
  }) {
    db.execute('''
      CREATE TABLE $table (
        source_key TEXT NOT NULL,
        comic_id TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        cover_url TEXT NOT NULL DEFAULT '',
        author TEXT NOT NULL DEFAULT '',
        chapter_id TEXT NOT NULL DEFAULT '',
        chapter_title TEXT NOT NULL DEFAULT '',
        page_no INTEGER NOT NULL DEFAULT 0,
        page_count INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (source_key, comic_id)
      )
    ''');
  }

  static bool _tableExists(Database db, String table) {
    return db.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object?>[table],
    ).isNotEmpty;
  }

  static Set<String> _columnNames(Database db, String table) {
    return db
        .select("PRAGMA table_info('$table')")
        .map((row) => row['name'] as String)
        .toSet();
  }

  static List<String> _primaryKeyColumns(Database db, String table) {
    final rows =
        db
            .select("PRAGMA table_info('$table')")
            .where((row) => (row['pk'] as int) > 0)
            .toList()
          ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
    return rows.map((row) => row['name'] as String).toList();
  }

  static void _addColumnIfMissing(
    Database db, {
    required String table,
    required Set<String> columns,
    required String name,
    required String definition,
  }) {
    if (columns.contains(name)) return;
    db.execute('ALTER TABLE $table ADD COLUMN $name $definition');
    columns.add(name);
  }

  static void _migrateDownloads(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS downloads (
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
  }

  /// 关闭数据库连接。
  Future<void> close() async {
    final initializing = _initializeFuture;
    if (initializing != null && !_initialized) {
      try {
        await initializing;
      } catch (_) {
        // 初始化失败时连接已由初始化流程释放。
      }
    }
    _coreDb?.dispose();
    _downloadDb?.dispose();
    _coreDb = null;
    _downloadDb = null;
    _initialized = false;
    _initializeFuture = null;
  }
}
