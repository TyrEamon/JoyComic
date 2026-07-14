/// SauceNAO 以图搜图服务。
///
/// 通过 SauceNAO API 反向搜索图片，返回可能匹配的漫画/插画结果。
/// 结果后通过两源搜索 title 做二次匹配，定位到禁漫/哔咔作品。
library;

import 'dart:io';

import 'package:dio/dio.dart';

/// SauceNAO 搜索结果项。
class SauceResult {
  const SauceResult({
    required this.similarity,
    required this.thumbnail,
    required this.source,
    this.title,
    this.author,
    this.extUrls = const [],
  });

  final double similarity;
  final String thumbnail;
  final String source;
  final String? title;
  final String? author;
  final List<String> extUrls;
}

/// SauceNAO 搜索服务。
class SauceNaoSearch {
  /// 默认测试 API Key（来自 joycomic-ios 内置）。
  static const kDefaultApiKey = '1f8fbe5632d20f8e025c610aef9e66c06ed39986';

  /// 执行以图搜图。
  ///
  /// [image] 待搜索的图片文件。
  /// [apiKey] SauceNAO API Key，不传则用默认内置 key。
  static Future<List<SauceResult>> search(File image, {String? apiKey}) async {
    final dio = Dio();
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(image.path),
    });
    final res = await dio.post(
      'https://saucenao.com/search.php',
      queryParameters: {
        'output_type': '2',
        'numres': '6',
        'api_key': apiKey ?? kDefaultApiKey,
      },
      data: form,
    );
    return _parse(res.data);
  }

  static List<SauceResult> _parse(dynamic data) {
    if (data is! Map) return [];
    final results = data['results'];
    if (results is! List) return [];

    return results.map<SauceResult>((r) {
      final header = r['header'] as Map? ?? {};
      final data = r['data'] as Map? ?? {};
      final similarity =
          double.tryParse('${header['similarity'] ?? '0'}') ?? 0.0;
      final extUrls = (data['ext_urls'] as List?)?.cast<String>() ?? [];
      return SauceResult(
        similarity: similarity,
        thumbnail: header['thumbnail']?.toString() ?? '',
        source: header['index_name']?.toString() ?? '',
        title: data['title']?.toString(),
        author: data['author_name']?.toString(),
        extUrls: extUrls,
      );
    }).toList();
  }

  /// 在 SauceNAO 结果中提取最佳匹配的标题用于二次搜索。
  static String? bestTitle(List<SauceResult> results) {
    if (results.isEmpty) return null;
    // 取相似度最高且有标题的结果
    results.sort((a, b) => b.similarity.compareTo(a.similarity));
    return results
        .firstWhere((r) => r.title != null, orElse: () => results.first)
        .title;
  }
}
