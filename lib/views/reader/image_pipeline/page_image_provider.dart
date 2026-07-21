/// Builds a [StreamImageProvider] for one reader page.
///
/// Download + optional JM recombine produce JPEG bytes; [StreamImageProvider]
/// + [ComicPageImage] own decode/paint (no custom Stateful load machine).
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../foundation/log.dart';
import '../utils/reader_image_provider.dart'
    show ReaderDiagnostics, ReaderImageBytesTransformer, jmReaderTransformer;
import '../utils/reader_pipeline.dart';
import 'stream_image_provider.dart';

export 'stream_image_provider.dart' show DownloadProgress, StreamImageProvider;

final Dio _dio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 45),
    responseType: ResponseType.bytes,
    validateStatus: (status) => status != null && status < 500,
  ),
);

bool _looksLikeImage(Uint8List bytes) {
  if (bytes.length < 3) return false;
  if (bytes[0] == 0xff && bytes[1] == 0xd8) return true;
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e) return true;
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return true;
  }
  return false;
}

String _magic(Uint8List bytes) {
  final n = bytes.length < 8 ? bytes.length : 8;
  return List.generate(
    n,
    (i) => bytes[i].toRadixString(16).padLeft(2, '0'),
  ).join(' ');
}

Map<String, String>? _sanitizeHeaders(Map<String, String>? headers) {
  if (headers == null || headers.isEmpty) return headers;
  final out = <String, String>{};
  for (final e in headers.entries) {
    final k = e.key.toLowerCase();
    if (k == 'accept-encoding' ||
        k == 'content-encoding' ||
        k == 'content-length' ||
        k == 'transfer-encoding' ||
        k == 'connection') {
      continue;
    }
    out[e.key] = e.value;
  }
  return out.isEmpty ? null : out;
}

/// Download one candidate URL as image bytes.
Future<Uint8List> _downloadOne(
  String url,
  Map<String, String>? headers,
) async {
  final host = Uri.tryParse(url)?.host ?? 'invalid';
  final response = await _dio.get<List<int>>(
    url,
    options: Options(headers: _sanitizeHeaders(headers)),
  );
  final status = response.statusCode ?? 0;
  final data = response.data;
  if (status < 200 || status >= 300 || data == null || data.isEmpty) {
    throw StateError('bad response host=$host status=$status');
  }
  final bytes = data is Uint8List ? data : Uint8List.fromList(data);
  if (!_looksLikeImage(bytes)) {
    throw StateError(
      'non-image host=$host status=$status len=${bytes.length} magic=${_magic(bytes)}',
    );
  }
  Log.i(
    'Reader image ok',
    'host=$host status=$status len=${bytes.length} magic=${_magic(bytes)}',
  );
  return bytes;
}

/// Stream: progress events then a final event with transformed JPEG/PNG bytes.
Stream<DownloadProgress> pageImageDownloadStream({
  required String url,
  required String cacheKey,
  List<String> fallbackUrls = const <String>[],
  Map<String, String>? headers,
  ReaderImageBytesTransformer? bytesTransformer,
  String? traceId,
  int? imageIndex,
}) async* {
  final urls = <String>{
    url,
    ...fallbackUrls,
  }.where((u) => u.trim().isNotEmpty).toList(growable: false);

  final prefix = [
    if (traceId != null) 'trace=$traceId',
    if (imageIndex != null) 'idx=$imageIndex',
  ].join(' ');

  final page = imageIndex ?? -1;
  Object? lastError;
  for (final candidate in urls) {
    final host = Uri.tryParse(candidate)?.host ?? 'invalid';
    try {
      ReaderPipeline.downloadBegin(page, host: host);
      yield const DownloadProgress(0, 1);
      final raw = await _downloadOne(candidate, headers);
      ReaderPipeline.downloadOk(
        page,
        host: host,
        len: raw.length,
        magic: _magic(raw),
      );
      yield DownloadProgress(raw.length, (raw.length / 0.75).ceil());

      var payload = raw;
      if (bytesTransformer != null) {
        ReaderPipeline.transformBegin(page, inLen: raw.length);
        try {
          payload = await bytesTransformer(raw);
          ReaderPipeline.transformOk(
            page,
            outLen: payload.length,
            magic: _magic(payload),
          );
        } catch (e) {
          ReaderPipeline.transformFail(page, error: e);
          rethrow;
        }
      }
      if (payload.isEmpty || !_looksLikeImage(payload)) {
        throw StateError(
          'bad transformed bytes len=${payload.length} magic=${_magic(payload)}',
        );
      }

      ReaderPipeline.bytesReady(
        page,
        len: payload.length,
        magic: _magic(payload),
      );
      Log.i(
        'Reader bytes ready',
        '$prefix cache=${ReaderDiagnostics.cacheKeySummary(cacheKey)} '
        'len=${payload.length} magic=${_magic(payload)} via=image_widget',
      );
      yield DownloadProgress(payload.length, payload.length, data: payload);
      return;
    } catch (e) {
      lastError = e;
      ReaderPipeline.downloadFail(page, error: e);
      Log.w(
        'Reader image candidate failed',
        error:
            '$prefix ${ReaderDiagnostics.sanitizeCaughtError(e, candidateUrl: candidate, headers: headers)}',
      );
    }
  }
  throw lastError ?? StateError('no image URL');
}

/// Factory used by the reader list.
ImageProvider createPageImageProvider({
  required String url,
  required String cacheKey,
  List<String> fallbackUrls = const <String>[],
  Map<String, String>? headers,
  ReaderImageBytesTransformer? bytesTransformer,
  String? traceId,
  int? imageIndex,
}) {
  final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    // Local file path.
    return FileImage(File(url));
  }
  return StreamImageProvider(
    () => pageImageDownloadStream(
      url: url,
      cacheKey: cacheKey,
      fallbackUrls: fallbackUrls,
      headers: headers,
      bytesTransformer: bytesTransformer,
      traceId: traceId,
      imageIndex: imageIndex,
    ),
    cacheKey,
    pageIndex: imageIndex ?? -1,
  );
}

/// JM transformer helper re-export for call sites.
ReaderImageBytesTransformer? pageJmTransformer({
  required String episodeId,
  required String imageName,
  String? traceId,
}) {
  return jmReaderTransformer(
    episodeId: episodeId,
    imageName: imageName,
    traceId: traceId,
  );
}
