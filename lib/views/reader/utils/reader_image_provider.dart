import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../foundation/jm_image_recombine.dart';
import '../../../foundation/log.dart';

typedef ReaderImageBytesTransformer =
    Future<Uint8List> Function(Uint8List bytes);

/// Source-aware provider shared by the reader and its preloader.
///
/// It downloads bytes before decoding so sources such as JM can restore their
/// scrambled image data. URL fallbacks are tried in order on the same request.
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
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.bytes,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
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
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: key.scale,
      debugLabel: key.url,
    );
  }

  Future<ui.Codec> _loadAsync(
    ReaderNetworkImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    Object? lastError;
    StackTrace? lastStack;
    for (final candidate in key._urls) {
      try {
        final response = await _dio.get<List<int>>(
          candidate,
          options: Options(headers: key.headers),
        );
        final data = response.data;
        if (data == null || data.isEmpty) {
          throw StateError('empty image response');
        }
        var bytes = data is Uint8List ? data : Uint8List.fromList(data);
        if (key.bytesTransformer != null) {
          bytes = await key.bytesTransformer!(bytes);
        }
        if (bytes.isEmpty) throw StateError('empty transformed image');
        return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      } catch (error, stackTrace) {
        lastError = error;
        lastStack = stackTrace;
        final host = Uri.tryParse(candidate)?.host;
        Log.w(
          'Reader image candidate failed: ${host?.isNotEmpty == true ? host : 'invalid host'}',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    Error.throwWithStackTrace(
      lastError ?? StateError('no image URL'),
      lastStack ?? StackTrace.current,
    );
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

ReaderImageBytesTransformer? jmReaderTransformer({
  required String episodeId,
  required String imageName,
}) {
  if (episodeId.trim().isEmpty) return null;
  final bookId = imageName.replaceFirst(RegExp(r'\.[^.]+$'), '');
  return (bytes) => recombineJmImage(bytes, episodeId, '220980', bookId);
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
