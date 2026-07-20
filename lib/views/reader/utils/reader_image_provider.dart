import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../foundation/jm_image_recombine.dart';
import '../../../foundation/log.dart';
import '../../../network/jm/jm_network.dart' show jmScrambleId;

typedef ReaderImageBytesTransformer =
    Future<Uint8List> Function(Uint8List bytes);

/// Source-aware provider shared by the reader and its preloader.
///
/// Downloads raw bytes before decoding so JM can recombine scrambled strips.
/// Candidates (primary + fallbacks) are tried in order. Non-image 2xx bodies
/// (HTML/JSON error pages) are rejected with host/status/content evidence.
class ReaderNetworkImageProvider
    extends ImageProvider<ReaderNetworkImageProvider> {
  const ReaderNetworkImageProvider({
    required this.url,
    required this.cacheKey,
    this.fallbackUrls = const <String>[],
    this.headers,
    this.bytesTransformer,
    this.scale = 1.0,
  });

  final String url;
  final String cacheKey;
  final List<String> fallbackUrls;
  final Map<String, String>? headers;
  final ReaderImageBytesTransformer? bytesTransformer;
  final double scale;

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 45),
      responseType: ResponseType.bytes,
      // Let HttpClient manage content decompression; callers must not force
      // opaque Accept-Encoding that leaves compressed bytes undecoded.
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  List<String> get _urls => <String>{
    url,
    ...fallbackUrls,
  }.where((value) => value.trim().isNotEmpty).toList(growable: false);

  @override
  Future<ReaderNetworkImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<ReaderNetworkImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    ReaderNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode, chunkEvents),
      scale: key.scale,
      debugLabel: key.cacheKey,
      chunkEvents: chunkEvents.stream,
    );
  }

  Future<ui.Codec> _loadAsync(
    ReaderNetworkImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    Object? lastError;
    StackTrace? lastStack;
    try {
      for (final candidate in key._urls) {
        try {
          final bytes = await _downloadCandidate(
            candidate,
            key.headers,
            chunkEvents,
          );
          var payload = bytes;
          if (key.bytesTransformer != null) {
            payload = await key.bytesTransformer!(bytes);
          }
          if (payload.isEmpty) {
            throw StateError('empty transformed image');
          }
          if (!_looksLikeImage(payload)) {
            throw StateError(
              'transformed bytes are not a decodable image '
              '(len=${payload.length}, magic=${_magic(payload)})',
            );
          }
          return decode(await ui.ImmutableBuffer.fromUint8List(payload));
        } catch (error, stackTrace) {
          lastError = error;
          lastStack = stackTrace;
          final host = Uri.tryParse(candidate)?.host;
          Log.w(
            'Reader image candidate failed: '
            '${host?.isNotEmpty == true ? host : 'invalid host'}',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      Error.throwWithStackTrace(
        lastError ?? StateError('no image URL'),
        lastStack ?? StackTrace.current,
      );
    } catch (error, stackTrace) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      await chunkEvents.close();
    }
  }

  static Future<Uint8List> _downloadCandidate(
    String candidate,
    Map<String, String>? headers,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    final host = Uri.tryParse(candidate)?.host ?? 'invalid host';
    final sanitized = _sanitizeHeaders(headers);
    final response = await _dio.get<List<int>>(
      candidate,
      options: Options(headers: sanitized),
    );
    final status = response.statusCode ?? 0;
    final contentType = response.headers.value('content-type') ?? '';
    final data = response.data;
    if (status < 200 || status >= 300) {
      throw StateError(
        'HTTP $status from $host (content-type=${contentType.isEmpty ? 'n/a' : contentType})',
      );
    }
    if (data == null || data.isEmpty) {
      throw StateError('empty image response from $host');
    }
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    if (!_looksLikeImage(bytes)) {
      final preview = _safePreview(bytes);
      throw StateError(
        'non-image body from $host '
        '(status=$status, content-type=${contentType.isEmpty ? 'n/a' : contentType}, '
        'len=${bytes.length}, magic=${_magic(bytes)}'
        '${preview.isEmpty ? '' : ', preview=$preview'})',
      );
    }
    if (!chunkEvents.isClosed) {
      chunkEvents.add(
        ImageChunkEvent(
          cumulativeBytesLoaded: bytes.length,
          expectedTotalBytes: bytes.length,
        ),
      );
    }
    Log.i(
      'Reader image ok: $host status=$status len=${bytes.length} '
      'ct=${contentType.isEmpty ? 'n/a' : contentType}',
    );
    return bytes;
  }

  /// Drop hop-by-hop / encoding headers so Dio/HttpClient can decompress.
  static Map<String, String>? _sanitizeHeaders(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return headers;
    final out = <String, String>{};
    for (final entry in headers.entries) {
      final key = entry.key.toLowerCase();
      if (key == 'accept-encoding' ||
          key == 'content-encoding' ||
          key == 'content-length' ||
          key == 'transfer-encoding' ||
          key == 'connection') {
        continue;
      }
      out[entry.key] = entry.value;
    }
    return out.isEmpty ? null : out;
  }

  static bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 3) return false;
    // JPEG
    if (bytes[0] == 0xff && bytes[1] == 0xd8) return true;
    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e) return true;
    // GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;
    // WEBP (RIFF....WEBP)
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
    // AVIF / HEIC ftyp box
    if (bytes.length >= 12 &&
        bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      return true;
    }
    return false;
  }

  static String _magic(Uint8List bytes) {
    final n = bytes.length < 8 ? bytes.length : 8;
    return List.generate(
      n,
      (i) => bytes[i].toRadixString(16).padLeft(2, '0'),
    ).join(' ');
  }

  static String _safePreview(Uint8List bytes) {
    final n = bytes.length < 48 ? bytes.length : 48;
    final text = String.fromCharCodes(bytes.sublist(0, n));
    final cleaned = text.replaceAll(RegExp(r'[^\x20-\x7E]'), '.');
    if (cleaned.trim().isEmpty) return '';
    return cleaned;
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderNetworkImageProvider &&
      other.cacheKey == cacheKey &&
      listEquals(other._urls, _urls) &&
      mapEquals(other.headers, headers);

  @override
  int get hashCode => Object.hash(
    cacheKey,
    Object.hashAll(_urls),
    Object.hashAll(headers?.entries ?? const []),
  );
}

/// Builds the JM strip-recombine transformer.
///
/// [imageName] may include an extension; it is stripped so MD5 uses the
/// extensionless picture name required by the scramble algorithm. GIFs are
/// never scrambled and skip recombination.
ReaderImageBytesTransformer? jmReaderTransformer({
  required String episodeId,
  required String imageName,
}) {
  final eps = episodeId.trim();
  if (eps.isEmpty) return null;
  final raw = imageName.trim();
  if (raw.isEmpty) return null;
  if (raw.toLowerCase().endsWith('.gif')) return null;
  final bookId = raw.replaceFirst(RegExp(r'\.[^.]+$'), '');
  if (bookId.isEmpty) return null;
  return (bytes) async {
    // GIF payloads that lost their extension still skip recombine.
    if (bytes.length >= 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return bytes;
    }
    final out = await recombineJmImage(bytes, eps, jmScrambleId, bookId);
    if (out.isEmpty) {
      throw StateError('JM recombine produced empty bytes for $bookId');
    }
    return out;
  };
}

ImageProvider readerImageProvider({
  required String url,
  required String cacheKey,
  List<String> fallbackUrls = const <String>[],
  Map<String, String>? headers,
  ReaderImageBytesTransformer? bytesTransformer,
  int? cacheWidth,
}) {
  final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
  final ImageProvider provider = scheme == 'http' || scheme == 'https'
      ? ReaderNetworkImageProvider(
          url: url,
          cacheKey: cacheKey,
          fallbackUrls: fallbackUrls,
          headers: headers,
          bytesTransformer: bytesTransformer,
        )
      : FileImage(File(url));
  return ResizeImage.resizeIfNeeded(cacheWidth, null, provider);
}
