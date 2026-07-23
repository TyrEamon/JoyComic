import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/jm/jm_endpoint_health.dart';
import 'package:joycomic/network/jm/jm_network.dart';
import 'package:joycomic/network/jm/jm_request_cache.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/network/source_state.dart';

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

  test(
    'concurrent selectDomain calls with the same candidates share one probe',
    () async {
      final adapter = _CountingProbeAdapter();
      final health = JmEndpointHealth();
      final network = JmNetwork(
        endpointHealth: health,
        dioFactory: (options) {
          final dio = Dio(options);
          dio.httpClientAdapter = adapter;
          return dio;
        },
      );

      final results = await Future.wait<int?>([
        network.selectDomain(const ['one.example']),
        network.selectDomain(const ['one.example']),
      ]);

      expect(results, [0, 0]);
      expect(adapter.probeCount, 1);
    },
  );

  test('selectDomain 401 records a successful reachable host first', () async {
    final adapter = _CountingProbeAdapter();
    final health = JmEndpointHealth();
    final network = JmNetwork(
      endpointHealth: health,
      dioFactory: (options) {
        final dio = Dio(options);
        dio.httpClientAdapter = adapter;
        return dio;
      },
    );

    final index = await network.selectDomain(const [
      'alive.example',
      'other.example',
    ]);

    expect(index, 0);
    expect(
      health.order(const ['other.example', 'alive.example']).first,
      'alive.example',
    );
    expect(health.isCoolingDown('alive.example'), isFalse);
  });

  test(
    'concurrent different GETs share one first-use domain warmup probe',
    () async {
      // Preferred host is dead; first built-in candidate is treated as live.
      const deadHost = 'dead.example';
      final liveHost = jmBuiltInDomains.first;
      final adapter = _WarmupThenOkAdapter(
        deadHost: deadHost,
        liveHost: liveHost,
      );
      final health = JmEndpointHealth();
      final state = _LatencyJmState(apiBaseUrl: 'https://$deadHost');
      final network = JmNetwork(
        endpointHealth: health,
        dioFactory: (options) {
          final dio = Dio(options);
          dio.httpClientAdapter = adapter;
          return dio;
        },
      )..state = state;

      final results = await Future.wait<Res<dynamic>>([
        network.get('https://$deadHost/setting'),
        network.get('https://$deadHost/hot_tags'),
      ]);

      expect(results.every((r) => !r.error), isTrue);
      // Shared warmup: live host is probed once for /login, not once per GET.
      expect(adapter.liveLoginProbeCount, 1);
      // After warmup, production GETs skip the dead preferred host.
      expect(adapter.getHosts, isNot(contains(deadHost)));
      expect(adapter.getHosts.toSet(), {liveHost});
      expect(health.order(<String>[deadHost, liveHost]).first, liveHost);
    },
  );

  test('injected getRequest path skips domain warmup probes', () async {
    var getCalls = 0;
    final health = JmEndpointHealth();
    final network = JmNetwork(
      endpointHealth: health,
      getRequest: (_) async {
        getCalls++;
        return const Res<dynamic>({'ok': true});
      },
      dioFactory: (options) {
        // Must not be used for a warmup probe when getRequest is injected.
        fail('dioFactory must not run when getRequest is injected');
      },
    );

    final res = await network.get('https://api.example/setting');
    expect(res.error, isFalse);
    expect(getCalls, 1);
  });

  test(
    'public GET cache serves a second identical request without network',
    () async {
      var networkCalls = 0;
      final cache = JmRequestCache();
      final network = JmNetwork(
        requestCache: cache,
        getRequest: (url) async {
          networkCalls++;
          return Res<dynamic>({'url': url, 'n': networkCalls});
        },
      );

      final first = await network.get(
        'https://api.example/setting',
        cacheTtl: const Duration(minutes: 5),
      );
      final second = await network.get(
        'https://api.example/setting',
        cacheTtl: const Duration(minutes: 5),
      );

      expect(first.error, isFalse);
      expect(second.error, isFalse);
      expect(first.data, containsPair('n', 1));
      expect(second.data, containsPair('n', 1));
      expect(identical(first.data, second.data), isFalse);
      expect(networkCalls, 1);
    },
  );

  test(
    'injected GET transport only caches when a cache is also injected',
    () async {
      var networkCalls = 0;
      final network = JmNetwork(
        getRequest: (_) async {
          networkCalls++;
          return Res<dynamic>(<String, dynamic>{'n': networkCalls});
        },
      );

      await network.get(
        'https://api.example/setting',
        cacheTtl: const Duration(minutes: 5),
      );
      await network.get(
        'https://api.example/setting',
        cacheTtl: const Duration(minutes: 5),
      );

      expect(networkCalls, 2);
    },
  );

  test('error responses are never stored in the public GET cache', () async {
    var networkCalls = 0;
    final cache = JmRequestCache();
    final network = JmNetwork(
      requestCache: cache,
      getRequest: (_) async {
        networkCalls++;
        return const Res<dynamic>(null, errorMessage: 'fail');
      },
    );

    await network.get(
      'https://api.example/search?q=x',
      cacheTtl: const Duration(seconds: 45),
    );
    await network.get(
      'https://api.example/search?q=x',
      cacheTtl: const Duration(seconds: 45),
    );

    expect(networkCalls, 2);
  });

  test(
    'logged-in album loads bypass public TTL cache; anonymous may cache',
    () async {
      var networkCalls = 0;
      Map<String, dynamic> albumPayload(int n) => <String, dynamic>{
        'name': 'Album $n',
        'id': '42',
        'author': <String>['a'],
        'description': '',
        'likes': n,
        'liked': n == 1,
        'is_favorite': n == 1,
        'tags': <String>[],
        'series': <dynamic>[],
        'images': <dynamic>[],
      };

      // Anonymous: second getComicInfo may hit cache (1 network call).
      final anonCache = JmRequestCache();
      final anonNetwork = JmNetwork(
        requestCache: anonCache,
        getRequest: (_) async {
          networkCalls++;
          return Res<dynamic>(albumPayload(networkCalls));
        },
      )..state = _LatencyJmState(username: null);

      expect((await anonNetwork.getComicInfo('42')).error, isFalse);
      expect((await anonNetwork.getComicInfo('42')).error, isFalse);
      expect(networkCalls, 1);

      // Logged-in: personalized liked/favorite — never cache (2 network calls).
      networkCalls = 0;
      final userCache = JmRequestCache();
      final userNetwork = JmNetwork(
        requestCache: userCache,
        getRequest: (_) async {
          networkCalls++;
          return Res<dynamic>(albumPayload(networkCalls));
        },
      )..state = _LatencyJmState(username: 'reader-one');

      final first = await userNetwork.getComicInfo('42');
      final second = await userNetwork.getComicInfo('42');
      expect(first.error, isFalse);
      expect(second.error, isFalse);
      expect(networkCalls, 2);
    },
  );
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

/// Counts POST /login domain probes used by [JmNetwork.selectDomain].
class _CountingProbeAdapter implements HttpClientAdapter {
  int probeCount = 0;
  final Completer<void> _releaseFirst = Completer<void>();
  bool _firstStarted = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    probeCount++;
    if (!_firstStarted) {
      _firstStarted = true;
      // Hold the first probe briefly so the concurrent twin must join single-flight.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (!_releaseFirst.isCompleted) _releaseFirst.complete();
    } else {
      await _releaseFirst.future;
    }
    return ResponseBody.fromString(
      '',
      401,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Simulates a dead preferred host and a live candidate discovered by warmup.
///
/// - POST `/login` on [liveHost] → 401 (reachable API probe).
/// - POST `/login` on [deadHost] / others → fail quickly.
/// - GET on [liveHost] → 200 JSON body that [JmNetwork._doGet] accepts.
class _WarmupThenOkAdapter implements HttpClientAdapter {
  _WarmupThenOkAdapter({required this.deadHost, required this.liveHost});

  final String deadHost;
  final String liveHost;
  int liveLoginProbeCount = 0;
  final List<String> getHosts = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final host = options.uri.host;
    final path = options.uri.path;
    final method = options.method.toUpperCase();

    if (method == 'POST' && path == '/login') {
      if (host == liveHost) {
        liveLoginProbeCount++;
        // Hold briefly so concurrent GETs must share the warmup single-flight.
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return ResponseBody.fromString(
          jsonEncode(<String, dynamic>{'errorMsg': '請先登入會員'}),
          401,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
          },
        );
      }
      // Non-live hosts fail the probe immediately (dead preferred + other built-ins).
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }

    if (method == 'GET') {
      getHosts.add(host);
      if (host == deadHost) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      // Plain JSON without encrypted data field — accepted by _doGet.
      return ResponseBody.fromBytes(
        utf8.encode(jsonEncode(<String, dynamic>{'ok': true, 'path': path})),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
    }

    throw StateError('unexpected ${options.method} ${options.uri}');
  }

  @override
  void close({bool force = false}) {}
}

class _LatencyJmState implements JmState {
  _LatencyJmState({this.apiBaseUrl = 'https://api.example', this.username});

  @override
  String apiBaseUrl;
  @override
  String imageBaseUrl = '';
  @override
  String preferredDomain = '';
  @override
  List<JmShunt> shunts = const <JmShunt>[];
  @override
  int selectedShuntKey = 0;
  @override
  String? username;
  @override
  String avs = '';

  @override
  Future<void> clearAvs() async => avs = '';

  @override
  List<String>? getAccount() => null;

  @override
  Future<bool> reLogin() async => false;

  @override
  Future<void> setAvs(String value) async => avs = value;

  @override
  void setApiBaseUrl(String url) => apiBaseUrl = url;

  @override
  void setImageBaseUrl(String url) => imageBaseUrl = url;

  @override
  void setPreferredDomain(String domain) => preferredDomain = domain;

  @override
  void setSelectedShuntKey(int key) => selectedShuntKey = key;

  @override
  void setShunts(List<JmShunt> value) => shunts = value;
}
