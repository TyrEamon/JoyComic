/// Persistent chapter download model and guarded state machine.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

/// Stable identity of one downloadable chapter.
class DownloadIdentity {
  final String sourceKey;
  final String comicId;
  final String chapterId;

  const DownloadIdentity(this.sourceKey, this.comicId, this.chapterId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadIdentity &&
          sourceKey == other.sourceKey &&
          comicId == other.comicId &&
          chapterId == other.chapterId;

  @override
  int get hashCode => Object.hash(sourceKey, comicId, chapterId);

  @override
  String toString() => '$sourceKey/$comicId/$chapterId';
}

/// Runtime and persisted state of a chapter download.
enum DownloadStatus { pending, downloading, paused, completed, failed }

/// One chapter-level download task.
class DownloadTask {
  final int? id;
  final String comicId;
  final String sourceKey;
  final String chapterId;
  final String title;
  final String coverUrl;
  final String chapterTitle;
  List<String> pageUrls;
  int completedCount;
  String? directory;
  String? legacyFilePath;
  String? errorMessage;
  DownloadStatus status;
  final DateTime createdAt;
  DateTime updatedAt;

  DownloadTask({
    this.id,
    required this.comicId,
    required this.sourceKey,
    required this.chapterId,
    this.title = '',
    this.coverUrl = '',
    this.chapterTitle = '',
    List<String>? pageUrls,
    this.completedCount = 0,
    this.directory,
    this.legacyFilePath,
    this.errorMessage,
    this.status = DownloadStatus.pending,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : pageUrls = List<String>.unmodifiable(pageUrls ?? const <String>[]),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now();

  DownloadIdentity get identity =>
      DownloadIdentity(sourceKey, comicId, chapterId);

  double get progress {
    if (pageUrls.isEmpty) return status == DownloadStatus.completed ? 1 : 0;
    return (completedCount / pageUrls.length).clamp(0.0, 1.0);
  }

  /// Compatibility aliases for older widgets/call sites.
  String get cover => coverUrl;
  String get fileName => chapterTitle;
  String? get filePath => directory;
  String get url => pageUrls.isEmpty ? '' : pageUrls.first;

  bool canTransitionTo(DownloadStatus next) {
    return switch (status) {
      DownloadStatus.pending => next == DownloadStatus.downloading,
      DownloadStatus.downloading =>
        next == DownloadStatus.paused ||
            next == DownloadStatus.completed ||
            next == DownloadStatus.failed,
      DownloadStatus.paused ||
      DownloadStatus.failed => next == DownloadStatus.downloading,
      DownloadStatus.completed => false,
    };
  }

  /// Applies a legal state transition or rejects it without mutating the task.
  void transitionTo(DownloadStatus next) {
    if (!canTransitionTo(next)) {
      throw StateError(
        'Illegal download transition: ${status.name} -> ${next.name}',
      );
    }
    status = next;
    updatedAt = DateTime.now();
  }

  /// Deterministic filename keeps URL order stable across restarts.
  static String pageFileName(int index, String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    var extension = p.extension(path).toLowerCase();
    if (!const <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.gif',
    }.contains(extension)) {
      extension = '.jpg';
    }
    return '${(index + 1).toString().padLeft(6, '0')}$extension';
  }

  List<String> get localPagePaths {
    final root = directory;
    if (root == null || root.isEmpty) return const <String>[];
    return <String>[
      for (var index = 0; index < pageUrls.length; index++)
        p.join(root, pageFileName(index, pageUrls[index])),
    ];
  }

  factory DownloadTask.fromRow(Map<String, Object?> row) {
    final rawUrls = row['page_urls'];
    List<String> urls = const <String>[];
    if (rawUrls is String && rawUrls.isNotEmpty) {
      try {
        urls = (jsonDecode(rawUrls) as List<dynamic>).cast<String>();
      } catch (_) {
        urls = const <String>[];
      }
    }
    return DownloadTask(
      id: row['id'] as int?,
      comicId: (row['comic_id'] as String?) ?? '',
      sourceKey: (row['source_key'] as String?) ?? '',
      chapterId: (row['chapter_id'] as String?) ?? '',
      title: (row['title'] as String?) ?? '',
      coverUrl: (row['cover_url'] as String?) ?? '',
      chapterTitle: (row['chapter_title'] as String?) ?? '',
      pageUrls: urls,
      completedCount: (row['completed_count'] as int?) ?? 0,
      directory: row['directory'] as String?,
      legacyFilePath: row['legacy_file_path'] as String?,
      errorMessage: row['error_message'] as String?,
      status: DownloadStatus.values.firstWhere(
        (value) => value.name == row['status'],
        orElse: () => DownloadStatus.pending,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as int?) ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at'] as int?) ?? 0,
      ),
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
    if (id != null) 'id': id,
    'comic_id': comicId,
    'source_key': sourceKey,
    'chapter_id': chapterId,
    'title': title,
    'cover_url': coverUrl,
    'chapter_title': chapterTitle,
    'page_urls': jsonEncode(pageUrls),
    'completed_count': completedCount,
    'directory': directory ?? '',
    'legacy_file_path': legacyFilePath,
    'error_message': errorMessage,
    'status': status.name,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };
}

/// Backwards-compatible name used by the original download page.
typedef DownloadItem = DownloadTask;
