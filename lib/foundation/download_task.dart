/// 下载任务数据模型。
library download_task;

/// 下载状态枚举。
enum DownloadStatus { pending, downloading, paused, completed, failed }

/// 下载项数据。
class DownloadItem {
  final int? id;
  final String comicId;
  final String sourceKey;
  final String chapterId;
  final String url;
  final String? fileName;
  String? filePath;
  DownloadStatus status;
  double progress;
  final DateTime createdAt;
  DateTime? updatedAt;

  DownloadItem({
    this.id,
    required this.comicId,
    required this.sourceKey,
    required this.chapterId,
    required this.url,
    this.fileName,
    this.filePath,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 从数据库行构造。
  factory DownloadItem.fromRow(Map<String, dynamic> row) {
    return DownloadItem(
      id: row['id'] as int?,
      comicId: row['comic_id'] as String,
      sourceKey: row['source_key'] as String,
      chapterId: row['chapter_id'] as String,
      url: row['url'] as String,
      fileName: row['file_name'] as String?,
      filePath: row['file_path'] as String?,
      status: DownloadStatus.values.firstWhere(
        (s) => s.name == row['status'],
        orElse: () => DownloadStatus.pending,
      ),
      progress: (row['progress'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as int?) ?? 0,
      ),
      updatedAt: row['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int)
          : null,
    );
  }

  Map<String, dynamic> toRow() => {
        if (id != null) 'id': id,
        'comic_id': comicId,
        'source_key': sourceKey,
        'chapter_id': chapterId,
        'url': url,
        'file_name': fileName,
        'file_path': filePath,
        'status': status.name,
        'progress': progress,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt?.millisecondsSinceEpoch,
      };
}
