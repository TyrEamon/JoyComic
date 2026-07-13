/// 阅读器通用工具与扩展。
///
/// 收纳阅读器使用的页码换算、屏高、图片解码宽度、列表分割、平台判定与
/// BuildContext 便捷访问。按需引入，不含下载/归档等非阅读器件。
library reader_utils;

import 'dart:io' show Platform;
import 'dart:ui' as ui show PlatformDispatcher;

import 'package:flutter/material.dart';

// ============================ 页码换算（双页模式） ============================

/// 单页页码 → 多页页码（向下取整）。
///
/// 双页模式下，相邻两页（pageNo、pageNo+1）同属一屏，故实际翻屏序号为
/// pageNo ~/ 2。
int toCorrectMultiPageNo(int pageNo, int pageSize) {
  return pageNo ~/ pageSize;
}

/// 多页页码 → 单页页码。
int toCorrectSinglePageNo(int pageNo, int pageSize) {
  return pageNo * pageSize;
}

/// [pageSize] 页码 → [anotherPageSize] 页码换算。
int toAnotherMultiPageNo(int pageNo, int pageSize, int anotherPageSize) {
  return (pageNo * pageSize) ~/ anotherPageSize;
}

// ============================ 屏幕尺寸 ============================

/// 主视图逻辑屏高（物理高 / 设备像素比）。
///
/// 用于 [VerticalList] 的 minCacheExtent（×2）与 [slipFactor] 翻页阈值。
double get screenHeight {
  final view = ui.PlatformDispatcher.instance.views.first;
  final physicalHeight = view.physicalSize.height;
  final dpr = view.devicePixelRatio;
  return physicalHeight / dpr;
}

// ============================ 图片解码宽度 ============================

/// 计算图片解码的 cacheWidth（物理像素）。
///
/// 按 [layoutWidth] × [devicePixelRatio] × [zoomHeadroom] 计算所需解码宽度，
/// 再夹到 [minWidth]~[maxWidth]：小屏保证基本细节，大屏防止解码 8K 级位图
/// 占爆内存。单页模式 layoutWidth 取全可视宽，双页模式取半屏宽。
int computeImageCacheWidth({
  required double layoutWidth,
  required double devicePixelRatio,
  double zoomHeadroom = 2.0,
  int minWidth = 1080,
  int maxWidth = 3840,
}) {
  if (layoutWidth <= 0 || devicePixelRatio <= 0 || !layoutWidth.isFinite) {
    return maxWidth;
  }
  final raw = (layoutWidth * devicePixelRatio * zoomHeadroom).round();
  return raw.clamp(minWidth, maxWidth);
}

// ============================ 列表分割 ============================

/// 把 [list] 按 [n] 个一组切分（双页模式按页对齐用）。
List<List<E>> splitList<E>(List<E> list, int n) {
  final result = <List<E>>[];
  for (var i = 0; i < list.length; i += n) {
    final end = (i + n) < list.length ? i + n : list.length;
    result.add(list.sublist(i, end));
  }
  return result;
}

// ============================ 文本 ============================

/// 取首个换行前的文本（章节标题等多行情形截首行）。
String getTextBeforeNewLine(String text) {
  final index = text.indexOf('\n');
  return index != -1 ? text.substring(0, index) : text;
}

// ============================ 平台判定 ============================

/// iOS 平台（阅读器据此在沉浸式 UI/手势上做平台差异）。
final bool isIOSPlatform = Platform.isIOS;

/// macOS 平台。
final bool isMacOSPlatform = Platform.isMacOS;

/// 桌面平台（macOS/Windows/Linux）。
bool get isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

// ============================ BuildContext 扩展 ============================

extension WaitFuture<T> on Future<T> {
  /// 等待并吞掉异常（场景内副作用调用，不关心成败）。
  Future<void> wait() async {
    try {
      await this;
    } catch (_) {
      // 阅读器次要副作用失败不影响主流程。
    }
  }
}

/// 阅读器常用 MediaQuery / Theme 的便捷访问。
extension ReaderBuildContextExt on BuildContext {
  EdgeInsets get padding => MediaQuery.paddingOf(this);
  double get left => padding.left;
  double get right => padding.right;
  double get top => padding.top;
  double get bottom => padding.bottom;

  Size get size => MediaQuery.sizeOf(this);
  double get width => size.width;
  double get height => size.height;

  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  TextTheme get textTheme => Theme.of(this).textTheme;
}

extension FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) predicate) {
    for (final element in this) {
      if (predicate(element)) return element;
    }
    return null;
  }
}
