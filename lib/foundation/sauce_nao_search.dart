/// SauceNAO reverse-image search with typed failure semantics.
library;

import 'dart:io';

import 'package:dio/dio.dart';

enum SauceNaoErrorKind {
  missingKey,
  invalidKey,
  rateLimited,
  network,
  malformed,
}

class SauceNaoException implements Exception {
  const SauceNaoException(this.kind, [this.message]);

  final SauceNaoErrorKind kind;
  final String? message;

  @override
  String toString() => message ?? kind.name;
}

class SauceNaoHttpResponse {
  const SauceNaoHttpResponse({required this.statusCode, required this.data});

  final int statusCode;
  final Object? data;
}

typedef SauceNaoTransport =
    Future<SauceNaoHttpResponse> Function(File image, String apiKey);

class SauceResult {
  const SauceResult({
    required this.similarity,
    required this.thumbnail,
    required this.source,
    this.title,
    this.author,
    this.extUrls = const <String>[],
  });

  final double similarity;
  final String thumbnail;
  final String source;
  final String? title;
  final String? author;
  final List<String> extUrls;
}

class SauceNaoSearch {
  SauceNaoSearch({SauceNaoTransport? transport})
    : _transport = transport ?? _dioTransport;

  final SauceNaoTransport _transport;

  Future<List<SauceResult>> search(File image, {required String apiKey}) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const SauceNaoException(SauceNaoErrorKind.missingKey);
    }

    SauceNaoHttpResponse response;
    try {
      response = await _transport(image, key);
    } on SauceNaoException {
      rethrow;
    } catch (_) {
      throw const SauceNaoException(SauceNaoErrorKind.network);
    }

    switch (response.statusCode) {
      case 403:
        throw const SauceNaoException(SauceNaoErrorKind.invalidKey);
      case 429:
        throw const SauceNaoException(SauceNaoErrorKind.rateLimited);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const SauceNaoException(SauceNaoErrorKind.network);
    }
    final businessError = _businessErrorKind(response.data);
    if (businessError != null) throw SauceNaoException(businessError);

    try {
      return _parse(response.data);
    } on FormatException {
      throw const SauceNaoException(SauceNaoErrorKind.malformed);
    }
  }

  static Future<SauceNaoHttpResponse> _dioTransport(
    File image,
    String apiKey,
  ) async {
    final dio = Dio(BaseOptions(validateStatus: (_) => true));
    final form = FormData.fromMap(<String, Object>{
      'file': await MultipartFile.fromFile(image.path),
    });
    final response = await dio.post<Object?>(
      'https://saucenao.com/search.php',
      queryParameters: <String, String>{
        'output_type': '2',
        'numres': '6',
        'api_key': apiKey,
      },
      data: form,
    );
    return SauceNaoHttpResponse(
      statusCode: response.statusCode ?? 0,
      data: response.data,
    );
  }

  static SauceNaoErrorKind? _businessErrorKind(Object? raw) {
    if (raw is! Map) return null;
    final header = raw['header'];
    if (header is! Map) return null;
    final status = num.tryParse('${header['status'] ?? 0}') ?? 0;
    final remaining = <Object?>[
      header['short_remaining'],
      header['long_remaining'],
    ].any((value) => value != null && (num.tryParse('$value') ?? 0) < 0);
    if (status >= 0 && !remaining) return null;

    final message = '${header['message'] ?? ''}'.toLowerCase();
    if (remaining ||
        message.contains('limit') ||
        message.contains('quota') ||
        message.contains('rate') ||
        message.contains('too many')) {
      return SauceNaoErrorKind.rateLimited;
    }
    if (message.contains('api key') ||
        message.contains('api_key') ||
        message.contains('anonymous account') ||
        message.contains('not permit api') ||
        message.contains('unauthor')) {
      return SauceNaoErrorKind.invalidKey;
    }
    return SauceNaoErrorKind.malformed;
  }

  static List<SauceResult> _parse(Object? raw) {
    if (raw is! Map) throw const FormatException('payload must be an object');
    final rawResults = raw['results'];
    if (rawResults is! List) {
      throw const FormatException('results must be a list');
    }

    final results = <SauceResult>[];
    for (final rawResult in rawResults) {
      if (rawResult is! Map) {
        throw const FormatException('result must be an object');
      }
      final header = rawResult['header'];
      final data = rawResult['data'];
      if (header is! Map || data is! Map) {
        throw const FormatException('result fields must be objects');
      }
      final extUrlsRaw = data['ext_urls'];
      if (extUrlsRaw != null && extUrlsRaw is! List) {
        throw const FormatException('ext_urls must be a list');
      }
      final extUrls = <String>[
        for (final value in extUrlsRaw is List ? extUrlsRaw : const <Object?>[])
          if (value is String && value.trim().isNotEmpty) value.trim(),
      ];
      results.add(
        SauceResult(
          similarity: double.tryParse('${header['similarity'] ?? 0}') ?? 0,
          thumbnail: header['thumbnail']?.toString() ?? '',
          source: header['index_name']?.toString() ?? '',
          title: _optionalString(data['title']),
          author: _optionalString(
            data['author_name'] ?? data['member_name'] ?? data['creator'],
          ),
          extUrls: List<String>.unmodifiable(extUrls),
        ),
      );
    }
    return List<SauceResult>.unmodifiable(results);
  }

  static String? bestTitle(List<SauceResult> results) {
    final ranked = List<SauceResult>.of(results)
      ..sort((a, b) => b.similarity.compareTo(a.similarity));
    for (final result in ranked) {
      final title = result.title?.trim();
      if (title != null && title.isNotEmpty) return title;
    }
    return null;
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
