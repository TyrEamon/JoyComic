/// 阅读器领域的"漫画阅读态" DTO。
///
/// 章节类型为 joycomic 自有 [ReaderChapter]，由 [ComicInfoData.chapters]
/// （Map<章节id, 章节名>）转换而来，保持源契约不动。
library comic_state;

/// 阅读器源类型：网络实时取图 vs 本地已下载图（阶段4 接下载前仅用 network）。
enum ReaderType { network, local }

/// 阅读器领域的单个章节。
///
/// [id] 用于 `loadComicPages(comicId, ep)` 取图；[order] 为章节序号（从 1）；
/// [name] 为展示标题。由 [ComicInfoData.chapters] 按 map 顺序转换。
class ReaderChapter {
  /// 章节 id（对应 `ComicInfoData.chapters` 的 key，或 `loadComicPages` 的 ep）。
  final String id;

  /// 章节序号（从 1）。
  final int order;

  /// 章节展示名（无则显示"第N话"）。
  final String name;

  const ReaderChapter({
    required this.id,
    required this.order,
    required this.name,
  });

  /// 由 [ComicInfoData.chapters] 的 Map<章节id, 章节名> 转换为有序章节列表。
  ///
  /// 编排顺序直接取 map 遍历序（源侧应已按章节顺序组织）；空 map 视为单话漫画，
  /// 退化为仅含 [singleChapter]。
  static List<ReaderChapter> fromChapterMap(Map<String, String>? chapters) {
    if (chapters == null || chapters.isEmpty) return const [];
    final list = <ReaderChapter>[];
    var order = 1;
    chapters.forEach((id, name) {
      list.add(ReaderChapter(
        id: id,
        order: order,
        name: name.isEmpty ? '第$order话' : name,
      ));
      order++;
    });
    return list;
  }

  /// 无分章漫画的占位单章节（ep=null 取全本图）。
  static ReaderChapter singleChapter() =>
      const ReaderChapter(id: '', order: 1, name: '全本');
}

/// 进阅读器前的初始快照：漫画 id、标题、章节列表、起始章节、起始页码、源类型。
class ComicState {
  /// 漫画 id。
  final String id;

  /// 漫画标题。
  final String title;

  /// 全部章节（[ReaderChapter] 列表；无分章漫画仅含 [ReaderChapter.singleChapter]）。
  final List<ReaderChapter> chapters;

  /// 当前章节。
  final ReaderChapter chapter;

  /// 当前页码。
  final int pageNo;

  /// 阅读源类型。
  final ReaderType type;

  /// 源 key（区分 recomb 哪种图片：禁漫需重组，哔咔直加载）。
  final String sourceKey;

  const ComicState({
    required this.id,
    required this.title,
    required this.chapters,
    required this.chapter,
    required this.pageNo,
    required this.sourceKey,
    this.type = ReaderType.network,
  });
}
