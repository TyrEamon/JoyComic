/// [ImageProvider] driven by a download stream that ends with image bytes.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

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

  bool get finished =>
      data != null ||
      (expectedBytes > 0 && currentBytes >= expectedBytes && data != null);
}

/// Builds a [Stream] of [DownloadProgress]; the last event must carry [data].
typedef ProgressStreamBuilder = Stream<DownloadProgress> Function();

class StreamImageProvider extends BaseImageProvider<StreamImageProvider> {
  const StreamImageProvider(this.streamBuilder, this.key);

  final ProgressStreamBuilder streamBuilder;

  @override
  final String key;

  @override
  Future<Uint8List> load(StreamController<ImageChunkEvent> chunkEvents) async {
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
