import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/jm/jm_network.dart';

void main() {
  test('JM image host latency rejects 403 and always closes Dio', () async {
    final adapter = _StatusAdapter(403);
    final network = JmNetwork(
      dioFactory: (options) {
        final dio = Dio(options);
        dio.httpClientAdapter = adapter;
        return dio;
      },
    );

    expect(await network.testImgHostLatency('images.example'), -1);
    expect(adapter.closed, isTrue);
    expect(adapter.forceClosed, isTrue);
  });
}

class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.statusCode);

  final int statusCode;
  bool closed = false;
  bool forceClosed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('', statusCode);

  @override
  void close({bool force = false}) {
    closed = true;
    forceClosed = force;
  }
}
