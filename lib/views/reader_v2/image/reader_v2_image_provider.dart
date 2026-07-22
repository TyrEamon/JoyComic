import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../core/reader_v2_scheduler.dart';
import '../core/reader_v2_session.dart';
import '../data/reader_v2_page.dart';

typedef ReaderV2CandidateFetcher =
    Future<Uint8List> Function(
      String url,
      Map<String, String>? headers,
      ReaderV2Session session,
    );
typedef ReaderV2BytesLoader =
    Future<Uint8List> Function(ReaderV2Page page, ReaderV2Session session);

final class ReaderV2PageLoader {
  ReaderV2PageLoader({ReaderV2CandidateFetcher? candidateFetcher})
    : _candidateFetcher = candidateFetcher ?? _fetchCandidate;

  final ReaderV2CandidateFetcher _candidateFetcher;

  Future<Uint8List> load(ReaderV2Page page, ReaderV2Session session) async {
    final candidates = <String>{
      page.url,
      ...page.fallbackUrls,
    }.where((url) => url.trim().isNotEmpty);
    Object? lastError;
    StackTrace? lastStack;
    for (final candidate in candidates) {
      try {
        session.throwIfCancelled();
        session.record('download', page: page.index, detail: candidate);
        var bytes = await _candidateFetcher(candidate, page.headers, session);
        session.throwIfCancelled();
        final transformer = page.bytesTransformer;
        if (transformer != null) {
          session.record('transform', page: page.index);
          bytes = await transformer(bytes);
          session.throwIfCancelled();
        }
        if (!_looksLikeImage(bytes)) {
          throw StateError('invalid image bytes len=${bytes.length}');
        }
        session.record('bytes', page: page.index, detail: '${bytes.length}');
        return bytes;
      } catch (error, stackTrace) {
        if (error is ReaderV2Cancelled) rethrow;
        lastError = error;
        lastStack = stackTrace;
        session.record('candidate-error', page: page.index, detail: '$error');
      }
    }
    Error.throwWithStackTrace(
      lastError ?? StateError('no image candidate'),
      lastStack ?? StackTrace.current,
    );
  }

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 45),
      responseType: ResponseType.bytes,
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  static Future<Uint8List> _fetchCandidate(
    String url,
    Map<String, String>? headers,
    ReaderV2Session session,
  ) async {
    final token = CancelToken();
    void cancel(ReaderV2Cancelled error) => token.cancel(error.reason);
    session.addCancelListener(cancel);
    try {
      final response = await _dio.get<List<int>>(
        url,
        cancelToken: token,
        options: Options(headers: _safeHeaders(headers)),
      );
      session.throwIfCancelled();
      final status = response.statusCode ?? 0;
      final data = response.data;
      if (status < 200 || status >= 300 || data == null || data.isEmpty) {
        throw StateError('bad response status=$status');
      }
      return data is Uint8List ? data : Uint8List.fromList(data);
    } finally {
      session.removeCancelListener(cancel);
    }
  }

  static Map<String, String>? _safeHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return headers;
    final result = Map<String, String>.of(headers);
    for (final key in const [
      'Accept-Encoding',
      'Content-Encoding',
      'Content-Length',
      'Transfer-Encoding',
      'Connection',
    ]) {
      result.remove(key);
      result.remove(key.toLowerCase());
    }
    return result.isEmpty ? null : result;
  }

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 3) return false;
    if (bytes[0] == 0xff && bytes[1] == 0xd8) return true;
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e) {
      return true;
    }
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return true;
    }
    return bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
  }
}

final class ReaderV2ImageProvider extends ImageProvider<ReaderV2ImageProvider> {
  const ReaderV2ImageProvider({
    required this.page,
    required this.session,
    required this.scheduler,
    required this.priority,
    required this.bytesLoader,
  });

  final ReaderV2Page page;
  final ReaderV2Session session;
  final ReaderV2Scheduler scheduler;
  final ReaderV2Priority priority;
  final ReaderV2BytesLoader bytesLoader;

  String get imageKey => '${session.traceId}|${page.cacheKey}';

  @override
  Future<ReaderV2ImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<ReaderV2ImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    ReaderV2ImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadCodec(decode),
      scale: 1,
      informationCollector: () sync* {
        yield DiagnosticsProperty<ImageProvider>('readerV2', this);
      },
    );
  }

  Future<ui.Codec> _loadCodec(ImageDecoderCallback decode) async {
    final bytes = await scheduler.schedule<Uint8List>(
      key: page.cacheKey,
      page: page.index,
      priority: priority,
      task: () => bytesLoader(page, session),
    );
    session.throwIfCancelled();
    session.record('decode', page: page.index, detail: '${bytes.length}');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderV2ImageProvider && other.imageKey == imageKey;

  @override
  int get hashCode => imageKey.hashCode;
}
