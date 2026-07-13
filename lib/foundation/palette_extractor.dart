/// 动态取色：从封面图实时提取主色调，注入详情页 UI。
///
/// 流程：取字节（dio 按 url + 可选鉴权 headers）→ Isolate 解码缩放 →
/// 步长采样 RGB→HSL → 色相分桶聚类 → 过滤低饱和/过暗过亮 → 取主桶均值
/// → 派生 accent + accentVariant 二色 → HSL 校验，不可用则回退品牌色。
///
/// 缓存：以 cover url 为 key 记录结果，同一漫画重入直接命中，不重复解码。
/// 取色全程失败 → 回退静态品牌色，调用方无感。
///
/// 与 [jm_image_recombine.dart] 同用 `package:image`，纯 Dart，Isolate 安全。
library palette_extractor;

import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' show decodeImage;

import '../theme/app_colors.dart';

/// 一次取色结果。
class ComicPalette {
  const ComicPalette({
    required this.accent,
    required this.accentVariant,
    required this.isExtracted,
  });

  /// 主强调色（头部渐变起点、底栏主按钮、星级高亮）。
  final Color accent;

  /// 副色（渐变终点，比 accent 冷暖对侧，丰富层次）。
  final Color accentVariant;

  /// 是否真实从封面提取；false 表示回退的静态品牌色。
  final bool isExtracted;

  /// 横向渐变（accent → accentVariant）。
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [accent, accentVariant],
      );

  /// 垂直渐变（胶囊/底栏纵向容器）。
  LinearGradient get gradientVertical => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [accent, accentVariant],
      );

  /// 兜底静态品牌色板（取色失败时回退）。
  static const ComicPalette fallback = ComicPalette(
    accent: AppColors.brandPink,
    accentVariant: AppColors.brandViolet,
    isExtracted: false,
  );
}

/// 动态取色器。
///
/// 用法：
///   `final p = await PaletteExtractor.extract(coverUrl, headers: cfg);`
///   或对已有字节：`await PaletteExtractor.extractFromBytes(bytes);`
class PaletteExtractor {
  PaletteExtractor._();

  /// url → 已取色结果缓存，避免重复解码。
  static final Map<String, ComicPalette> _cache = {};

  /// 从网络/本地 url 取色。[headers] 可选鉴权头（哔咔/禁漫缩略图）。
  static Future<ComicPalette> extract(
    String? url, {
    Map<String, dynamic>? headers,
  }) async {
    if (url == null || url.isEmpty) return ComicPalette.fallback;
    final cached = _cache[url];
    if (cached != null) return cached;

    try {
      final bytes = await _fetchBytes(url, headers);
      if (bytes == null || bytes.isEmpty) return _fallback(url);
      final palette = await extractFromBytes(bytes, cacheKey: url);
      _cache[url] = palette;
      return palette;
    } catch (_) {
      return _fallback(url);
    }
  }

  /// 从已有字节取色。Isolate 内执行解码与聚类。
  static Future<ComicPalette> extractFromBytes(
    Uint8List bytes, {
    String? cacheKey,
  }) async {
    if (cacheKey != null) {
      final cached = _cache[cacheKey];
      if (cached != null) return cached;
    }
    try {
      final result = await compute(_extractSync, bytes);
      final palette = result ?? ComicPalette.fallback;
      if (cacheKey != null) _cache[cacheKey] = palette;
      return palette;
    } catch (_) {
      return ComicPalette.fallback;
    }
  }

  static ComicPalette _fallback(String url) {
    _cache[url] = ComicPalette.fallback;
    return ComicPalette.fallback;
  }

  /// 字节拉取。http(s) 走轻量 dio；本地路径走 dart:io File。
  static Future<Uint8List?> _fetchBytes(
    String url,
    Map<String, dynamic>? headers,
  ) async {
    if (url.startsWith('http')) {
      return _dioFetch(url, headers);
    }
    try {
      final f = io.File(url);
      if (!await f.exists()) return null;
      return f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// 单例 dio，复用连接池。
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 10),
  ));

  static Future<Uint8List?> _dioFetch(
    String url,
    Map<String, dynamic>? headers,
  ) async {
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes, headers: headers),
    );
    final data = resp.data;
    if (data == null || data.isEmpty) return null;
    return Uint8List.fromList(data);
  }

  // ============================ Isolate 取色核心 ============================

  /// Isolate 同步入口：解码 → 大步长采样 → 聚类 → 返回或 null。
  ///
  /// 只用 `decodeImage` + `getRange` + `.current.r/g/b`，与
  /// [jm_image_recombine.dart] 同套已验证 API，不引入 copyResize 等未验证项。
  static ComicPalette? _extractSync(Uint8List bytes) {
    final img = decodeImage(bytes);
    if (img == null) return null;

    // 步长：约采样 32×32 网格，对任意分辨率都够取色且开销恒定。
    final stepX = (img.width / 32).ceil().clamp(1, 64);
    final stepY = (img.height / 32).ceil().clamp(1, 64);
    final buckets = <int, _ColorBucket>{};

    for (var y = 0; y < img.height; y += stepY) {
      final row = img.getRange(0, y, img.width, 1);
      var x = 0;
      while (row.moveNext()) {
        if (x % stepX == 0) {
          final p = row.current;
          final r = (p.r as num).round();
          final g = (p.g as num).round();
          final b = (p.b as num).round();
          final hsl = _rgbToHsl(r, g, b);
          // 过滤：低饱和（灰/白/黑）与过暗过亮跳过，避免主色脏。
          if (hsl[1] >= 0.18 && hsl[2] >= 0.12 && hsl[2] <= 0.92) {
            final bucketKey = _hueBucket(hsl[0]);
            buckets
                .putIfAbsent(bucketKey, _ColorBucket.new)
                .accumulate(r, g, b);
          }
        }
        x++;
      }
    }

    if (buckets.isEmpty) return null;

    // 取人口最多的桶作为 accent。
    final sorted = buckets.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    final primary = sorted.first;
    if (primary.count == 0) return null;

    final accent = _sanitize(primary.average());

    // accentVariant：取次大桶；若无次桶则由 accent 派生（色调偏移 + 提亮）。
    final accentVariant = (sorted.length >= 2 && sorted[1].count > 0)
        ? _sanitize(sorted[1].average())
        : _deriveVariant(accent);

    return ComicPalette(
      accent: accent,
      accentVariant: accentVariant,
      isExtracted: true,
    );
  }

  /// 将 RGB 规整到可用的强调色：保证对深色底有足够亮度与饱和度。
  static Color _sanitize(List<int> rgb) {
    final hsl = _rgbToHsl(rgb[0], rgb[1], rgb[2]);
    // 钳制亮度到 0.5~0.72、饱和度到 0.55~1.0，确保深底上够亮够艳。
    final fixed = [
      hsl[0],
      hsl[1].clamp(0.55, 1.0),
      hsl[2].clamp(0.5, 0.72),
    ];
    final out = _hslToRgb(fixed[0], fixed[1], fixed[2]);
    return Color.fromARGB(255, out[0], out[1], out[2]);
  }

  /// 由 accent 派生一个冷暖对侧的副色（色调 +30°、提亮一点）。
  static Color _deriveVariant(Color c) {
    final r = c.red, g = c.green, b = c.blue;
    final hsl = _rgbToHsl(r, g, b);
    final h2 = (hsl[0] + 30) % 360;
    final out = _hslToRgb(h2, hsl[1].clamp(0.5, 1.0), (hsl[2] + 0.06).clamp(0.5, 0.8));
    return Color.fromARGB(255, out[0], out[1], out[2]);
  }

  static int _hueBucket(double hue) => (hue / 30).floor() % 12;

  // ============================ 颜色换算（纯函数） ============================

  static List<double> _rgbToHsl(int r, int g, int b) {
    final rf = r / 255, gf = g / 255, bf = b / 255;
    final max = [rf, gf, bf].reduce((a, b) => a > b ? a : b);
    final min = [rf, gf, bf].reduce((a, b) => a < b ? a : b);
    final l = (max + min) / 2;
    final d = max - min;
    double h = 0;
    double s = 0;
    if (d != 0) {
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
      if (max == rf) {
        h = ((gf - bf) / d) % 6;
      } else if (max == gf) {
        h = (bf - rf) / d + 2;
      } else {
        h = (rf - gf) / d + 4;
      }
      h *= 60;
      if (h < 0) h += 360;
    }
    return [h, s, l];
  }

  static List<int> _hslToRgb(double h, double s, double l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - (((h / 60) % 2) - 1).abs());
    final m = l - c / 2;
    double r1, g1, b1;
    if (h < 60) {
      r1 = c; g1 = x; b1 = 0;
    } else if (h < 120) {
      r1 = x; g1 = c; b1 = 0;
    } else if (h < 180) {
      r1 = 0; g1 = c; b1 = x;
    } else if (h < 240) {
      r1 = 0; g1 = x; b1 = c;
    } else if (h < 300) {
      r1 = x; g1 = 0; b1 = c;
    } else {
      r1 = c; g1 = 0; b1 = x;
    }
    return [
      ((r1 + m) * 255).round().clamp(0, 255),
      ((g1 + m) * 255).round().clamp(0, 255),
      ((b1 + m) * 255).round().clamp(0, 255),
    ];
  }

  // ============================ 缓存管理 ============================

  /// 预热缓存（列表页滚动到某卡时前置取色，详情页零等待）。
  static void prefetch(String url, {Map<String, dynamic>? headers}) {
    if (_cache.containsKey(url)) return;
    extract(url, headers: headers);
  }

  /// 清空缓存（源切换 / 内存压力）。
  static void clearCache() => _cache.clear();
}

/// 色相聚类桶：累加 RGB、计人口，最后取均值。
class _ColorBucket {
  int rSum = 0, gSum = 0, bSum = 0, count = 0;

  void accumulate(int r, int g, int b) {
    rSum += r;
    gSum += g;
    bSum += b;
    count++;
  }

  List<int> average() => [rSum ~/ count, gSum ~/ count, bSum ~/ count];
}
