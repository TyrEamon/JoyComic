/// 竖直连续列表的可见索引计算工具。
///
/// [ItemPositionsListener] 提供的索引经过过滤：只保留完全在可视区域内的项，
/// 排除 itemLeadingEdge < 0（在顶部之上）和 itemTrailingEdge > 1（在底部之下）的项。
library;

import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// 提取可视区域内的图片索引。
///
/// 只返回 [itemLeadingEdge] >= 0、[itemTrailingEdge] > 0 且在 [0, imageCount) 内的项。
/// 结果按索引升序排列。
List<int> visibleVerticalImageIndices(
  Iterable<ItemPosition> positions, {
  required int imageCount,
}) {
  if (imageCount <= 0) return [];

  final indices = positions
      .where((pos) => pos.index >= 0 && pos.index < imageCount)
      .where(
        (pos) =>
            pos.itemLeadingEdge < 1.0 &&
            pos.itemTrailingEdge > 0.0 &&
            pos.itemTrailingEdge <= 1.0,
      )
      .map((position) => position.index)
      .toList();

  indices.sort();
  return indices;
}

/// 获取当前页面在可视区域表格中的最后一个索引。
int? currentVerticalPageIndex(
  Iterable<ItemPosition> positions, {
  required int imageCount,
}) {
  final indices = visibleVerticalImageIndices(
    positions,
    imageCount: imageCount,
  );
  if (indices.isEmpty) return null;
  return indices.last;
}
