/// Memory-backed multi-frame [ImageProvider] base.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../utils/reader_pipeline.dart';

abstract class BaseImageProvider<T extends BaseImageProvider<T>>
    extends ImageProvider<T> {
  const BaseImageProvider();

  /// 诊断用页码；子类可覆盖。
  int get diagnosticPageIndex => -1;

  @override
  ImageStreamCompleter loadImage(T key, ImageDecoderCallback decode) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadBufferAsync(key, chunkEvents, decode),
      chunkEvents: chunkEvents.stream,
      scale: 1.0,
      informationCollector: () sync* {
        yield DiagnosticsProperty<ImageProvider>(
          'Image provider: $this \n Image key: $key',
          this,
          style: DiagnosticsTreeStyle.errorProperty,
        );
      },
    );
  }

  Future<ui.Codec> _loadBufferAsync(
    T key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    final page = key.diagnosticPageIndex;
    try {
      var retryTime = 1;
      var stop = false;
      chunkEvents.onCancel = () {
        stop = true;
      };

      Uint8List? data;
      while (data == null && !stop) {
        try {
          if (_cache.containsKey(key.key)) {
            data = _cache[key.key];
            ReaderPipeline.mark(
              ReaderStage.bytesReady,
              pageIndex: page,
              detail: 'from_mem_cache len=${data!.length}',
            );
          } else {
            data = await load(chunkEvents);
            _checkCacheSize();
            _cache[key.key] = data;
            _cacheSize += data.length;
          }
        } catch (e) {
          retryTime <<= 1;
          if (retryTime > (1 << 3) || stop) rethrow;
          await Future<void>.delayed(Duration(seconds: retryTime));
        }
      }

      if (stop) {
        throw Exception('Image loading is stopped');
      }
      if (data == null || data.isEmpty) {
        throw Exception('Empty image data');
      }

      ReaderPipeline.codecBegin(page, len: data.length);
      try {
        final buffer = await ui.ImmutableBuffer.fromUint8List(data);
        final codec = await decode(buffer);
        // 尺寸要等 frame；先记 codec 创建成功
        ReaderPipeline.mark(
          ReaderStage.codecOk,
          pageIndex: page,
          detail: 'codec_created len=${data.length}',
        );
        return codec;
      } catch (e) {
        ReaderPipeline.codecFail(page, error: e);
        rethrow;
      }
    } catch (e) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      await chunkEvents.close();
    }
  }

  static final Map<String, Uint8List> _cache = {};
  static var _cacheSize = 0;
  static final _cacheSizeLimit = 50 * 1024 * 1024;

  static void _checkCacheSize() {
    while (_cacheSize > _cacheSizeLimit && _cache.isNotEmpty) {
      final firstKey = _cache.keys.first;
      _cacheSize -= _cache[firstKey]!.length;
      _cache.remove(firstKey);
    }
  }

  static void clearCache() {
    _cache.clear();
    _cacheSize = 0;
  }

  Future<Uint8List> load(StreamController<ImageChunkEvent> chunkEvents);

  String get key;

  @override
  bool operator ==(Object other) =>
      other is BaseImageProvider<T> && key == other.key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => '$runtimeType($key)';
}
