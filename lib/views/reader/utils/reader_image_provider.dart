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

/// Redaction and short-message helpers for reader diagnostics.
///
/// Never log credentials, cookies, authorization values, or full query URLs.
class ReaderDiagnostics {
  ReaderDiagnostics._();

  static String newTraceId() {
    final millis = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final suffix = (Object().hashCode & 0xffff).toRadixString(16).padLeft(4, '0');
    final id = '$millis$suffix';
    return id.length <= 12 ? id : id.substring(id.length - 12);
  }

  static String redactUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return 'empty';
    final uri = Uri.tryParse(trimmed);
    if (uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty) {
      final path = uri.path;
      final shortPath = path.length > 48 ? '${path.substring(0, 45)}...' : path;
      final queryNote = uri.hasQuery ? '?…' : '';
      return '${uri.scheme}://${uri.host}$shortPath$queryNote';
    }
    // Non-URI / opaque strings may contain tokens — never echo raw text.
    if (_looksSecretBearing(trimmed)) {
      return 'opaque(len=${trimmed.length},h=${_stableHashHex(trimmed)})';
    }
    // Safe-looking opaque path without query/secret markers: still avoid
    // returning the full value if it embeds `=` pairs that look like secrets.
    if (trimmed.contains('?') || trimmed.contains('=')) {
      return 'opaque(len=${trimmed.length},h=${_stableHashHex(trimmed)})';
    }
    if (trimmed.length > 64) {
      return 'opaque(len=${trimmed.length},h=${_stableHashHex(trimmed)})';
    }
    // Short non-secret opaque labels only.
    return 'opaque(len=${trimmed.length},h=${_stableHashHex(trimmed)})';
  }

  /// Deterministic one-way summary — never returns raw key material.
  static String cacheKeySummary(String cacheKey) {
    final key = cacheKey.trim();
    return 'len=${key.length},h=${_stableHashHex(key)}';
  }

  /// Safe log line for ReaderProvider chapter-load failures.
  ///
  /// Never embeds original API/network error text. Display messages for the
  /// UI should be kept separate from this log detail.
  static String formatProviderLoadFailure({
    required String? traceId,
    required String chapterId,
    required Object error,
  }) {
    final trace = (traceId == null || traceId.isEmpty) ? 'none' : traceId;
    final sanitized = sanitizeCaughtError(error);
    return 'trace=$trace chapter=$chapterId $sanitized';
  }

  static bool _looksSecretBearing(String text) {
    final lower = text.toLowerCase();
    return lower.contains('token') ||
        lower.contains('bearer') ||
        lower.contains('cookie') ||
        lower.contains('authorization') ||
        lower.contains('password') ||
        lower.contains('secret') ||
        lower.contains('sig=') ||
        lower.contains('session=') ||
        RegExp(r'https?://').hasMatch(lower);
  }

  /// FNV-1a 32-bit hex digest — stable across isolates, not reversible.
  static String _stableHashHex(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static String headerSummary(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) return 'none';
    final names = <String>[];
    for (final key in headers.keys) {
      final lower = key.toLowerCase();
      if (lower == 'authorization' ||
          lower == 'cookie' ||
          lower == 'set-cookie' ||
          lower == 'proxy-authorization') {
        continue;
      }
      names.add(key);
    }
    return names.isEmpty ? 'redacted' : names.join(',');
  }

  static String formatCandidateFailure({
    required String host,
    required int status,
    required String contentType,
    required int byteCount,
    required String magic,
    Map<String, String>? headers,
  }) {
    return 'host=$host status=$status ct=${contentType.isEmpty ? 'n/a' : contentType} '
        'len=$byteCount magic=$magic headers=${headerSummary(headers)}';
  }

  /// Safe category for a caught network/decode failure. Never echo raw text.
  static String errorCategory(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('timeout') || text.contains('timed out')) {
      return 'timeout';
    }
    if (text.contains('socket') ||
        text.contains('connection') ||
        text.contains('network')) {
      return 'network';
    }
    if (text.contains('certificate') || text.contains('handshake')) {
      return 'tls';
    }
    if (text.contains('http ') ||
        text.contains('status=') ||
        text.contains('403') ||
        text.contains('404') ||
        text.contains('401') ||
        text.contains('500')) {
      return 'http';
    }
    if (text.contains('codec') ||
        text.contains('decode') ||
        text.contains('not a decodable') ||
        text.contains('empty transformed') ||
        text.contains('non-image')) {
      return 'decode';
    }
    if (text.contains('transform') || text.contains('recombine')) {
      return 'transform';
    }
    return 'error';
  }

  /// Build a loggable diagnostic from a caught error without credentials,
  /// full request URLs, headers, or response body previews.
  static String sanitizeCaughtError(
    Object error, {
    String? candidateUrl,
    Map<String, String>? headers,
    int? statusCode,
    String? contentType,
    Uint8List? responseBytes,
  }) {
    final host = candidateUrl == null
        ? 'unknown'
        : (Uri.tryParse(candidateUrl)?.host.isNotEmpty == true
              ? Uri.parse(candidateUrl).host
              : 'invalid host');
    final status = statusCode ?? _guessStatus(error);
    final ct = (contentType == null || contentType.isEmpty) ? 'n/a' : contentType;
    final len = responseBytes?.length ?? 0;
    final magic = responseBytes == null || responseBytes.isEmpty
        ? 'n/a'
        : _magicBytes(responseBytes);
    final category = errorCategory(error);
    return 'cat=$category host=$host status=$status ct=$ct len=$len '
        'magic=$magic headers=${headerSummary(headers)}';
  }

  /// Stack traces may still embed request URLs from Dio frames; strip query
  /// values and known secret key patterns before persisting.
  static String? redactStackTrace(StackTrace? stackTrace) {
    if (stackTrace == null) return null;
    var text = stackTrace.toString();
    // Drop query strings from any URI-like fragment.
    text = text.replaceAllMapped(
      RegExp(r'(https?://[^\s)\]"]+)\?[^\s)\]"]*'),
      (match) {
        final base = match.group(1) ?? '';
        final uri = Uri.tryParse(base);
        if (uri == null) return '[redacted-url]';
        return '${uri.scheme}://${uri.host}${uri.path}?…';
      },
    );
    text = text.replaceAll(
      RegExp(
        r'(authorization|cookie|token|sig|password|secret)\s*[=:]\s*[^\s,;"]+',
        caseSensitive: false,
      ),
      r'$1=[redacted]',
    );
    // Hard reject if sensitive material remains.
    final lower = text.toLowerCase();
    if (lower.contains('authorization=') ||
        lower.contains('bearer ') ||
        lower.contains('cookie=') ||
        lower.contains('token=') ||
        RegExp(r'https?://[^\s]+\?[^\s]+').hasMatch(text)) {
      return 'stack=[redacted]';
    }
    if (text.length > 800) {
      return '${text.substring(0, 797)}...';
    }
    return text;
  }

  static int _guessStatus(Object error) {
    final match = RegExp(r'(?:status(?:Code)?[=:\s]|HTTP\s)(\d{3})')
        .firstMatch(error.toString());
    if (match == null) return 0;
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }

  static String _magicBytes(Uint8List bytes) {
    final n = bytes.length < 8 ? bytes.length : 8;
    return List.generate(
      n,
      (i) => bytes[i].toRadixString(16).padLeft(2, '0'),
    ).join(' ');
  }
}

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
    this.traceId,
    this.imageIndex,
  });

  final String url;
  final String cacheKey;
  final List<String> fallbackUrls;
  final Map<String, String>? headers;
  final ReaderImageBytesTransformer? bytesTransformer;
  final double scale;
  final String? traceId;
  final int? imageIndex;

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
    final trace = key.traceId == null ? '' : 'trace=${key.traceId} ';
    final index = key.imageIndex == null ? '' : 'idx=${key.imageIndex} ';
    try {
      for (final candidate in key._urls) {
        try {
          final bytes = await _downloadCandidate(
            candidate,
            key.headers,
            chunkEvents,
            traceId: key.traceId,
          );
          var payload = bytes;
          if (key.bytesTransformer != null) {
            // JM recombine runs in an isolate; never hang the ImageProvider forever.
            payload = await key.bytesTransformer!(bytes).timeout(
              const Duration(seconds: 20),
              onTimeout: () => throw TimeoutException(
                'image transform timed out after 20s',
              ),
            );
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
          final codec = await decode(
            await ui.ImmutableBuffer.fromUint8List(payload),
          );
          Log.i(
            'Reader codec ok',
            '$trace$index'
            'cache=${ReaderDiagnostics.cacheKeySummary(key.cacheKey)} '
            'len=${payload.length}',
          );
          return codec;
        } catch (error, stackTrace) {
          final sanitized = ReaderDiagnostics.sanitizeCaughtError(
            error,
            candidateUrl: candidate,
            headers: key.headers,
          );
          lastError = StateError(sanitized);
          lastStack = stackTrace;
          final redacted = ReaderDiagnostics.redactStackTrace(stackTrace);
          Log.w(
            'Reader image candidate failed',
            error: '$trace$index$sanitized',
            stackTrace: redacted == null
                ? null
                : StackTrace.fromString(redacted),
          );
        }
      }
      Error.throwWithStackTrace(
        lastError ?? StateError('no image URL'),
        lastStack ?? StackTrace.current,
      );
    } catch (error, stackTrace) {
      final sanitized = ReaderDiagnostics.sanitizeCaughtError(
        error,
        candidateUrl: key.url,
        headers: key.headers,
      );
      final redacted = ReaderDiagnostics.redactStackTrace(stackTrace);
      Log.e(
        'Reader codec failed',
        error: '$trace$index'
            'cache=${ReaderDiagnostics.cacheKeySummary(key.cacheKey)} $sanitized',
        stackTrace: redacted == null ? null : StackTrace.fromString(redacted),
      );
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      final safeError = error is StateError && error.message.startsWith('cat=')
          ? error
          : StateError(sanitized);
      Error.throwWithStackTrace(safeError, stackTrace);
    } finally {
      await chunkEvents.close();
    }
  }

  static Future<Uint8List> _downloadCandidate(
    String candidate,
    Map<String, String>? headers,
    StreamController<ImageChunkEvent> chunkEvents, {
    String? traceId,
  }) async {
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
        ReaderDiagnostics.formatCandidateFailure(
          host: host,
          status: status,
          contentType: contentType,
          byteCount: data?.length ?? 0,
          magic: data == null
              ? 'n/a'
              : _magic(
                  data is Uint8List ? data : Uint8List.fromList(data),
                ),
          headers: sanitized,
        ),
      );
    }
    if (data == null || data.isEmpty) {
      throw StateError('empty image response from $host');
    }
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    if (!_looksLikeImage(bytes)) {
      // Never attach response body previews — they may contain secrets.
      throw StateError(
        ReaderDiagnostics.formatCandidateFailure(
          host: host,
          status: status,
          contentType: contentType,
          byteCount: bytes.length,
          magic: _magic(bytes),
          headers: sanitized,
        ),
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
    final prefix = traceId == null ? '' : 'trace=$traceId ';
    Log.i(
      'Reader image ok',
      '${prefix}host=$host status=$status len=${bytes.length} '
      'ct=${contentType.isEmpty ? 'n/a' : contentType} magic=${_magic(bytes)}',
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
  String? traceId,
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
    final prefix = traceId == null ? '' : 'trace=$traceId ';
    Log.i(
      'Reader transform begin',
      '${prefix}episode=$eps image=$bookId in=${bytes.length} '
      'magic=${_magicStatic(bytes)}',
    );
    try {
      final out = await recombineJmImage(bytes, eps, jmScrambleId, bookId);
      if (out.isEmpty) {
        throw StateError('JM recombine produced empty bytes for $bookId');
      }
      Log.i(
        'Reader transform ok',
        '${prefix}episode=$eps image=$bookId out=${out.length} '
        'magic=${_magicStatic(out)}',
      );
      return out;
    } catch (error, stackTrace) {
      Log.e(
        'Reader transform failed',
        error: '${prefix}episode=$eps image=$bookId err=$error',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  };
}

String _magicStatic(Uint8List bytes) {
  final n = bytes.length < 8 ? bytes.length : 8;
  return List.generate(
    n,
    (i) => bytes[i].toRadixString(16).padLeft(2, '0'),
  ).join(' ');
}

ImageProvider readerImageProvider({
  required String url,
  required String cacheKey,
  List<String> fallbackUrls = const <String>[],
  Map<String, String>? headers,
  ReaderImageBytesTransformer? bytesTransformer,
  int? cacheWidth,
  String? traceId,
  int? imageIndex,
}) {
  final scheme = Uri.tryParse(url)?.scheme.toLowerCase();
  final ImageProvider provider = scheme == 'http' || scheme == 'https'
      ? ReaderNetworkImageProvider(
          url: url,
          cacheKey: cacheKey,
          fallbackUrls: fallbackUrls,
          headers: headers,
          bytesTransformer: bytesTransformer,
          traceId: traceId,
          imageIndex: imageIndex,
        )
      : FileImage(File(url));
  return ResizeImage.resizeIfNeeded(cacheWidth, null, provider);
}
