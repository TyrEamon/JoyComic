/// [ImageProvider] driven by a download stream that ends with image bytes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../utils/reader_pipeline.dart';
import 'base_image_provider.dart';

/// Progress event for streaming download → bytes.
class DownloadProgress {
  const DownloadProgress(
    this.currentBytes,
    this.expectedBytes, {
    this.data,
  });

  final int currentBytes;
  final int expectedBytes;
  final Uint8List? data;
}

/// Builds a [Stream] of [DownloadProgress]; the last event must carry [data].
typedef ProgressStreamBuilder = Stream<DownloadProgress> Function();

class StreamImageProvider extends BaseImageProvider<StreamImageProvider> {
  const StreamImageProvider(
    this.streamBuilder,
    this.key, {
    this.pageIndex = -1,
  });

  final ProgressStreamBuilder streamBuilder;

  @override
  final String key;

  /// 阅读器页码，用于流水线诊断。
  final int pageIndex;

  @override
  int get diagnosticPageIndex => pageIndex;

  @override
  Future<Uint8List> load(StreamController<ImageChunkEvent> chunkEvents) async {
    ReaderPipeline.mark(
      ReaderStage.providerLoad,
      pageIndex: pageIndex,
      detail: 'key=len=${key.length}',
    );
    chunkEvents.add(
      const ImageChunkEvent(cumulativeBytesLoaded: 0, expectedTotalBytes: 100),
    );

    DownloadProgress? finish;
    await for (final progress in streamBuilder()) {
      if (progress.data != null) {
        finish = progress;
      }
      chunkEvents.add(
        ImageChunkEvent(
          cumulativeBytesLoaded: progress.currentBytes,
          expectedTotalBytes: progress.expectedBytes > 0
              ? progress.expectedBytes
              : null,
        ),
      );
    }

    final data = finish?.data;
    if (data == null || data.isEmpty) {
      throw Exception('Stream finished without image data');
    }
    return data;
  }

  @override
  Future<StreamImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }
}
