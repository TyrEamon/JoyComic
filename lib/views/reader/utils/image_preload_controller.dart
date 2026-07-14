/// 方向感知的图片预加载控制器。
///
/// 在用户翻页 / 滚动时，预先解码周边图片到 Flutter ImageCache 中，减少首帧白屏。
/// 方向感知：前滚时预加载尾部，后滚时预加载前部。
///
/// 预加载的图片用与显示端相同的 [ResizeImage.resizeIfNeeded] + [cacheWidth] 包裹，
/// 保证预加载缓存键与显示键一致，避免"白预加载"（预加载了解析度不同的副本）。
library;

import 'dart:async';
import 'dart:io';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../../../foundation/log.dart';
import '../providers/reader_provider.dart';
import '../state/comic_state.dart';
import '../widgets/retry_for_image.dart';

/// 方向感知的图片预加载控制器。
///
/// 接收 [List<ReaderImage>] 作为数据源，通过 [onAnchorChanged] 接收可视区域
/// 首尾索引，据此判断滚动方向并调度预加载。
class ImagePreloadController implements ImagePreloadControllerRef {
  ImagePreloadController({
    required this.context,
    required this.items,
    required this.type,
    this.maxPreloadCount = 4,
    this.keepWindow = 10,
    this.debounceDuration = const Duration(milliseconds: 50),
    this.cacheWidth,
  });

  /// Widget tree 上下文，用于 [precacheImage]。
  final BuildContext context;

  /// 当前章节的全部图片。
  List<ReaderImage> items;

  /// 图片来源类型（网络 / 本地）。
  final ReaderType type;

  /// 单次最大预加载数量。
  int maxPreloadCount;

  /// 预加载索引保留窗口（锚点前后各保留 [keepWindow] 项）。
  final int keepWindow;

  /// 防抖时长（锚点连续变化时合并预加载请求）。
  final Duration debounceDuration;

  /// 解码宽度（物理像素）。与显示端保持一致以共享 ImageCache 条目。
  /// 为 null 时不限制解码尺寸（原始分辨率）。
  @override
  int? cacheWidth;

  Timer? _debounceTimer;

  /// generation 计数器：items 替换或缓存失效时递增，用于辨认可抛弃的旧记录。
  int _generation = 0;

  /// 已预加载索引集合（generation, index）。
  final Set<(int, int)> _preloaded = {};

  /// 最近一次锚点首索引，用于判断滚动方向。
  int _lastAnchorIndex = 0;

  // ============================ 锚点变化 ============================

  /// 可视区域首尾索引变化时调用。
  ///
  /// [indexes] 的首项为首索引，末项为尾索引。
  /// 通过比较首索引与 [_lastAnchorIndex] 判定滚动方向：
  ///   - 前滚（isBackward=false）：预加载尾索引之后的图
  ///   - 后滚（isBackward=true）：预加载首索引之前的图
  @override
  void onAnchorChanged(List<int> indexes) {
    final first = indexes.first;
    final last = indexes.last;
    final isBackward = first < _lastAnchorIndex;

    if (isBackward) {
      _schedulePreload(
        start: first - 1,
        end: first - maxPreloadCount,
        anchor: first,
      );
    } else {
      _schedulePreload(
        start: last + 1,
        end: last + maxPreloadCount,
        anchor: last,
      );
    }

    _lastAnchorIndex = first;
  }

  // ============================ 主调度 ============================

  void _schedulePreload({
    required int start,
    required int end,
    required int anchor,
  }) {
    _debounceTimer?.cancel();

    _debounceTimer = Timer(debounceDuration, () {
      if (!context.mounted) return;

      _trimPreloaded(anchor);

      final from = start < end ? start : end;
      final to = start < end ? end : start;

      int count = 0;
      for (int i = from; i <= to; i++) {
        if (count >= maxPreloadCount) break;
        if (i < 0 || i >= items.length) continue;

        final key = (_generation, i);
        if (_preloaded.contains(key)) continue;

        _preloaded.add(key);
        count++;

        final item = items[i];
        final ImageProvider base = type == ReaderType.network
            ? CachedNetworkImageProvider(
                item.url,
                cacheManager: cacheManager,
                cacheKey: item.cacheKey,
              )
            : FileImage(File(item.url));

        // 用与显示端一致的 ResizeImage 包裹，保证预加载进入的缓存键与显示一致。
        // 否则显示时会因键不同而重新解码一次，预加载就浪费了。
        final ImageProvider provider = cacheWidth != null
            ? ResizeImage.resizeIfNeeded(cacheWidth, null, base)
            : base;

        precacheImage(
          provider,
          context,
          onError: (error, stackTrace) {
            Log.e(
              'Reader image preload failed',
              error: error,
              stackTrace: stackTrace,
            );
          },
        );
      }
    });
  }

  // ============================ 窗口修剪 ============================

  /// 移除 [anchor] 前后 [keepWindow] 之外的预加载记录。
  ///
  /// 同时剔除 generation 不匹配的旧记录（replaceItems / invalidatePreloaded
  /// 产生的旧代数据）。
  void _trimPreloaded(int anchor) {
    _preloaded.removeWhere((key) {
      final (gen, index) = key;
      if (gen != _generation) return true;
      return (index - anchor).abs() > keepWindow;
    });
  }

  // ============================ 数据替换 ============================

  /// 替换图片列表（章节切换后调用）。
  ///
  /// 递增 generation 使旧预加载记录自然失效，无需逐个清理。
  @override
  void replaceItems(List<ReaderImage> newItems) {
    _debounceTimer?.cancel();
    items = newItems;
    _generation++;
    _lastAnchorIndex = 0;
  }

  // ============================ 缓存失效 ============================

  /// 使所有已预加载记录失效。
  ///
  /// [cacheWidth] 变化等会改变 ImageCache key 的场景下调用，以便后续
  /// 锚点变化时重新按新尺寸预解码。
  ///
  /// 注意：**不**取消正在排队的 debounce timer。取消会让"数据加载成功后
  /// 立即排好的首批预加载"被 LayoutBuilder 中的 cacheWidth 校准吃掉，
  /// 造成预加载迟迟不发生。旧 timer 即使继续跑，也会因 generation 不匹配
  /// 在 [_trimPreloaded] 阶段被自然清理。
  @override
  void invalidatePreloaded() {
    _generation++;
    _preloaded.clear();
  }

  // ============================ 资源释放 ============================

  /// 取消未执行的预加载请求并清理记录。
  void dispose() {
    _debounceTimer?.cancel();
    _preloaded.clear();
  }
}
