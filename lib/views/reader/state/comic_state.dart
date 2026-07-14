/// 阅读器领域的“漫画阅读态” DTO。
library;

import '../../../database/read_record_helper.dart';

/// 阅读器源类型：网络实时取图 vs 本地已下载图。
enum ReaderType { network, local }

/// 阅读器领域的单个章节。
class ReaderChapter {
  final String id;
  final int order;
  final String name;

  const ReaderChapter({
    required this.id,
    required this.order,
    required this.name,
  });

  static List<ReaderChapter> fromChapterMap(Map<String, String>? chapters) {
    if (chapters == null || chapters.isEmpty) return const [];
    final list = <ReaderChapter>[];
    var order = 1;
    chapters.forEach((id, name) {
      list.add(
        ReaderChapter(
          id: id,
          order: order,
          name: name.isEmpty ? '第$order话' : name,
        ),
      );
      order++;
    });
    return list;
  }

  static ReaderChapter singleChapter() =>
      const ReaderChapter(id: '', order: 1, name: '全本');
}

/// 进阅读器前的初始快照以及写入阅读历史所需的完整漫画元数据。
class ComicState {
  final String id;
  final String title;
  final String coverUrl;
  final String author;
  final List<ReaderChapter> chapters;
  final ReaderChapter chapter;
  final int pageNo;
  final ReaderType type;
  final String sourceKey;

  const ComicState({
    required this.id,
    required this.title,
    this.coverUrl = '',
    this.author = '',
    required this.chapters,
    required this.chapter,
    required this.pageNo,
    required this.sourceKey,
    this.type = ReaderType.network,
  });

  /// 从本地历史恢复阅读器。历史只持久化当前章节，因此恢复列表包含该章节。
  factory ComicState.fromReadRecord(ReadRecord record) {
    final chapter = record.chapterId.isEmpty
        ? ReaderChapter.singleChapter()
        : ReaderChapter(
            id: record.chapterId,
            order: 1,
            name: record.chapterTitle.isEmpty ? '当前章节' : record.chapterTitle,
          );
    return ComicState(
      id: record.comic,
      title: record.title,
      coverUrl: record.cover,
      author: record.author,
      chapters: <ReaderChapter>[chapter],
      chapter: chapter,
      pageNo: record.pageNo < 0 ? 0 : record.pageNo,
      sourceKey: record.source,
    );
  }
}
