import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/detail_models.dart';
import '../reader/state/comic_state.dart';
import 'detail_view_model.dart';

String detailSearchRoute({required String sourceKey, required String keyword}) {
  return Uri(
    path: '/search/${Uri.encodeComponent(sourceKey)}',
    queryParameters: <String, String>{'q': keyword.trim()},
  ).toString();
}

String detailCategoryRoute({
  required String sourceKey,
  required String category,
}) =>
    '/category/${Uri.encodeComponent(sourceKey)}/${Uri.encodeComponent(category.trim())}';

String detailChaptersRoute({
  required String sourceKey,
  required String comicId,
}) =>
    '/detail/${Uri.encodeComponent(sourceKey)}/${Uri.encodeComponent(comicId)}/chapters';

String detailCommentsRoute({
  required String sourceKey,
  required String comicId,
}) =>
    '/detail/${Uri.encodeComponent(sourceKey)}/${Uri.encodeComponent(comicId)}/comments';

/// Selects the first chapter for a new reading session.
///
/// Sources may expose chapters newest-first, so list position is not a
/// reliable indication of the first chapter. The typed order is the source
/// of truth instead.
ReaderChapter selectStartReadingChapter(List<ReaderChapter> chapters) {
  if (chapters.isEmpty) {
    throw ArgumentError.value(chapters, 'chapters', 'must not be empty');
  }
  return chapters.reduce(
    (first, chapter) => chapter.order < first.order ? chapter : first,
  );
}

void openDetailKeywordSearch(
  BuildContext context, {
  required String sourceKey,
  required String keyword,
}) {
  context.push(detailSearchRoute(sourceKey: sourceKey, keyword: keyword));
}

void openDetailCategory(
  BuildContext context, {
  required String sourceKey,
  required String category,
}) {
  context.push(detailCategoryRoute(sourceKey: sourceKey, category: category));
}

void openDetailChapters(
  BuildContext context, {
  required String sourceKey,
  required String comicId,
}) {
  context.push(detailChaptersRoute(sourceKey: sourceKey, comicId: comicId));
}

void openDetailComments(
  BuildContext context, {
  required String sourceKey,
  required String comicId,
}) {
  context.push(detailCommentsRoute(sourceKey: sourceKey, comicId: comicId));
}

/// Opens the reader from detail or full-chapters pages.
///
/// Direct chapter taps always start that chapter at page 0.
/// The main resume action uses the saved [DetailViewModel.readRecord].
void openDetailReader(
  BuildContext context,
  DetailViewModel viewModel,
  ComicChapter? entry,
) {
  final info = viewModel.data?.info;
  final chapters = ReaderChapter.fromComicChapters(viewModel.chapters);
  if (info == null || chapters.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('暂无章节')));
    return;
  }

  final record = viewModel.readRecord;
  final start = entry != null
      ? chapters.firstWhere(
          (chapter) => chapter.id == entry.id,
          orElse: () => chapters.last,
        )
      : record == null
      ? selectStartReadingChapter(chapters)
      : chapters.firstWhere(
          (chapter) => chapter.id == record.chapterId,
          orElse: () => chapters.last,
        );
  final pageNo = entry == null && record?.chapterId == start.id
      ? record!.pageNo.clamp(0, 1 << 30)
      : 0;

  context.push(
    '/reader',
    extra: ComicState(
      id: info.comicId,
      title: info.title,
      coverUrl: info.cover,
      author: viewModel.author,
      chapters: chapters,
      chapter: start,
      pageNo: pageNo,
      sourceKey: viewModel.sourceKey,
    ),
  );
}
