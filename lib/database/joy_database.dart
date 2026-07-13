/// JoyComic 数据库基础设施。
///
/// 多库隔离设计：每条数据线一个独立的 .db 文件，避免锁竞争。
/// - `joycomic.db`：核心数据（阅读记录、搜索历史、收藏追踪、图片尺寸）
/// - `downloads.db`：下载队列
///
/// 基于 sqlite3 纯 Dart 驱动 + sqlite3_flutter_libs 原生库，
/// 不需要额外 ORM，手工 SQL 更轻量可控。
library joy_database;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';

import '../foundation/log.dart';

/// 数据库管理器（单例）。
class JoyDatabase {
  JoyDatabase._();

  static final JoyDatabase instance = JoyDatabase._();
  bool _initialized = false;

  Database? _coreDb;
  Database? _downloadDb;

  Database get core => _coreDb ?? (throw StateError('JoyDatabase not initialized'));
  Database get downloadDb => _downloadDb ?? (throw StateError('JoyDatabase not initialized'));

  /// 初始化数据库（应用启动时调用）。
  Future<void> initialize() async {
    if (_initialized) return;

    // 确保 sqlite3 原生库可用
    _ensureSqlite3();

    final dir = await getApplicationDocumentsDirectory();
    final dbDir = Directory(p.join(dir.path, 'db'));
    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    _coreDb = sqlite3.open(p.join(dbDir.path, 'joycomic.db'));
    _downloadDb = sqlite3.open(p.join(dbDir.path, 'downloads.db'));

    _createTables();
    _initialized = true;
    Log.i('Database initialized', 'joycomic.db + downloads.db');
  }

  void _ensureSqlite3() {
    // sqlite3_flutter_libs 会在 Dart VM 初始化时自动注册
    // 无需手动 open.overrideFor
  }

  void _createTables() {
    core.execute('''
      CREATE TABLE IF NOT EXISTS search_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        keyword TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL
      )
    ''');

    core.execute('''
      CREATE TABLE IF NOT EXISTS read_records (
        comic_id TEXT NOT NULL,
        source_key TEXT NOT NULL,
        chapter_id TEXT NOT NULL,
        page_no INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (comic_id, source_key, chapter_id)
      )
    ''');

    core.execute('''
      CREATE TABLE IF NOT EXISTS favorites (
        comic_id TEXT NOT NULL,
        source_key TEXT NOT NULL,
        title TEXT,
        cover_url TEXT,
        author TEXT,
        favorited_at INTEGER NOT NULL,
        PRIMARY KEY (comic_id, source_key)
      )
    ''');

    core.execute('''
      CREATE TABLE IF NOT EXISTS image_sizes (
        image_id TEXT NOT NULL,
        comic_id TEXT NOT NULL,
        width INTEGER NOT NULL,
        height INTEGER NOT NULL,
        PRIMARY KEY (image_id, comic_id)
      )
    ''');

    _downloadDb!.execute('''
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
    _coreDb?.dispose();
    _downloadDb?.dispose();
    _initialized = false;
  }
}
