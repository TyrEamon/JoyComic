import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/built_in/picacg.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/foundation/source_credential_store.dart';
import 'package:joycomic/network/picacg/picacg_headers.dart';
import 'package:joycomic/network/picacg/picacg_network.dart';
import 'package:joycomic/network/source_state.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'joycomic-pica-auth-',
    );
    ComicSource.dataPathProvider = () => tempDirectory.path;
    ComicSource.sources.clear();
  });

  tearDown(() async {
    ComicSource.sources.clear();
    ComicSource.dataPathProvider = null;
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('Pica headers do not hardcode Host and sign path with query', () {
    const signedTarget = 'comics?page=2&s=dd';
    final options = buildHeaders(
      method: 'GET',
      token: 'token',
      urlPath: signedTarget,
    );

    expect(
      options.headers.keys.map((key) => key.toString().toLowerCase()),
      isNot(contains('host')),
    );
    expect(
      options.headers['signature'],
      createSignature(
        signedTarget,
        options.headers['nonce']! as String,
        options.headers['time']! as String,
        'GET',
      ),
    );
    expect(
      options.headers['signature'],
      isNot(
        createSignature(
          'comics',
          options.headers['nonce']! as String,
          options.headers['time']! as String,
          'GET',
        ),
      ),
    );
  });

  test('auth 401 never triggers automatic relogin', () async {
    final adapter = _RecordingAdapter(
      (_) => _jsonResponse(401, {'message': 'unauthorized'}),
    );
    final state = _FakePicacgState(token: 'expired-token');
    final network = PicacgNetwork(dioFactory: _dioFactory(adapter))
      ..state = state;

    final result = await network.login('person@example.com', 'password');

    expect(result.error, isTrue);
    expect(state.reLoginCalls, 0);
    expect(
      adapter.requests.where((r) => r.uri.path == '/auth/sign-in'),
      hasLength(picacgApiHosts.values.toSet().length),
    );
  });

  test(
    'fallback relogin retries the triggering request on the new API host',
    () async {
      final adapter = _RecordingAdapter((options) {
        if (options.uri.host == 'picaapi.picacomic.com') {
          return _jsonResponse(401, {'message': 'unauthorized'});
        }
        return _jsonResponse(200, {
          'message': 'success',
          'data': <String, dynamic>{},
        });
      });
      late final _FakePicacgState state;
      state = _FakePicacgState(
        token: 'expired-token',
        onReLogin: () async {
          state.apiBaseUrl = picacgApiHosts['go2778']!;
          return true;
        },
      )..apiBaseUrl = picacgApiHosts['picacomic']!;
      final network = PicacgNetwork(dioFactory: _dioFactory(adapter))
        ..state = state;

      final result = await network.get(
        '${picacgApiHosts['picacomic']}/comics?page=2&s=dd',
      );

      expect(result.error, isFalse);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.first.uri.host, 'picaapi.picacomic.com');
      expect(adapter.requests.last.uri.host, 'picaapi.go2778.com');
      expect(adapter.requests.last.uri.path, '/comics');
      expect(adapter.requests.last.uri.query, 'page=2&s=dd');
    },
  );

  test('Pica authentication operations execute serially', () async {
    final network = PicacgNetwork(
      dioFactory: _dioFactory(
        _RecordingAdapter(
          (_) => _jsonResponse(200, {
            'message': 'success',
            'data': <String, dynamic>{},
          }),
        ),
      ),
    );
    final firstGate = Completer<void>();
    final firstStarted = Completer<void>();
    var active = 0;
    var maxActive = 0;

    Future<void> operation({required bool wait}) =>
        network.runAuthenticationOperation(() async {
          active++;
          if (active > maxActive) maxActive = active;
          if (wait) {
            firstStarted.complete();
            await firstGate.future;
          }
          active--;
        });

    final first = operation(wait: true);
    await firstStarted.future;
    final second = operation(wait: false);
    await Future<void>.delayed(Duration.zero);
    expect(maxActive, 1);
    firstGate.complete();
    await Future.wait(<Future<void>>[first, second]);
    expect(maxActive, 1);
  });

  test(
    'profile 401 during relogin terminates without recursively relogging',
    () async {
      final adapter = _RecordingAdapter((options) {
        if (options.uri.path == '/auth/sign-in') {
          return _jsonResponse(200, {
            'message': 'success',
            'data': {'token': 'renewed-token'},
          });
        }
        if (options.uri.path == '/users/profile') {
          return _jsonResponse(401, {'message': 'unauthorized'});
        }
        return _jsonResponse(401, {'message': 'unauthorized'});
      });
      final secrets = SourceCredentialStore(_MemorySecretStore());
      await secrets.saveCredentials(
        'picacg',
        'person@example.com',
        'secure-password',
      );
      final network = PicacgNetwork(dioFactory: _dioFactory(adapter));
      final source = buildPicacgSource(
        credentialStore: secrets,
        network: network,
      );
      source.data['token'] = 'expired-token';
      source.data['apiBaseUrl'] = picacgApiHosts['picacomic'];
      ComicSource.sources.add(source);
      await source.initData!(source);

      final result = await network
          .get('${picacgApiHosts['picacomic']}/comics?page=1')
          .timeout(const Duration(milliseconds: 500));

      expect(result.error, isTrue);
      expect(
        adapter.requests.where((r) => r.uri.path == '/auth/sign-in'),
        hasLength(1),
      );
      expect(
        adapter.requests.where((r) => r.uri.path == '/users/profile'),
        hasLength(1),
      );
    },
  );

  test(
    'ordinary authenticated 401 relogins and retries original request once',
    () async {
      var attempts = 0;
      final adapter = _RecordingAdapter((options) {
        attempts++;
        if (attempts == 1) {
          return _jsonResponse(401, {'message': 'unauthorized'});
        }
        return _jsonResponse(200, {
          'message': 'success',
          'data': <String, dynamic>{},
        });
      });
      final state = _FakePicacgState(
        token: 'expired-token',
        reLoginResult: true,
      );
      final network = PicacgNetwork(dioFactory: _dioFactory(adapter))
        ..state = state;

      final result = await network.get(
        'https://picaapi.picacomic.com/comics?page=2&s=dd',
      );

      expect(result.error, isFalse);
      expect(state.reLoginCalls, 1);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[0].uri, adapter.requests[1].uri);
      expect(
        adapter.requests[0].headers['signature'],
        isNot(adapter.requests[1].headers['signature']),
      );
    },
  );

  test(
    'an ordinary request retries at most once after a successful relogin',
    () async {
      final adapter = _RecordingAdapter(
        (_) => _jsonResponse(401, {'message': 'unauthorized'}),
      );
      final state = _FakePicacgState(
        token: 'expired-token',
        reLoginResult: true,
      );
      final network = PicacgNetwork(dioFactory: _dioFactory(adapter))
        ..state = state;

      final result = await network.post(
        'https://picaapi.picacomic.com/comics/id/favourite?from=test',
        {'value': 'same-body'},
      );

      expect(result.error, isTrue);
      expect(state.reLoginCalls, 1);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.map((request) => request.uri.toString()).toSet(),
        hasLength(1),
      );
      expect(
        adapter.requests.map((request) => request.data).toSet(),
        hasLength(1),
      );
    },
  );

  test(
    'login tries deduplicated configured, official and go2778 endpoints and persists the successful endpoint securely',
    () async {
      final attemptedLoginBases = <String>[];
      final adapter = _RecordingAdapter((options) {
        if (options.uri.path == '/auth/sign-in') {
          attemptedLoginBases.add(options.uri.origin);
          if (options.uri.host == 'picaapi.picacomic.com') {
            return _jsonResponse(400, {'message': 'official unavailable'});
          }
          return _jsonResponse(200, {
            'message': 'success',
            'data': {'token': 'go-token'},
          });
        }
        if (options.uri.path == '/users/profile') {
          return _jsonResponse(200, {
            'message': 'success',
            'data': {
              'user': {
                '_id': 'profile-id',
                'name': 'Pica User',
                'email': 'person@example.com',
              },
            },
          });
        }
        return _jsonResponse(404, {'message': 'unexpected'});
      });
      final secrets = SourceCredentialStore(_MemorySecretStore());
      final network = PicacgNetwork(dioFactory: _dioFactory(adapter));
      final source = buildPicacgSource(
        credentialStore: secrets,
        network: network,
      );
      source.data['apiBaseUrl'] = picacgApiHosts['picacomic'];
      ComicSource.sources.add(source);

      final result = await source.account!.login!(
        'person@example.com',
        'secure-password',
      );

      expect(result.error, isFalse);
      expect(attemptedLoginBases, [
        picacgApiHosts['picacomic'],
        picacgApiHosts['go2778'],
      ]);
      expect(source.data['apiBaseUrl'], picacgApiHosts['go2778']);
      expect(source.data['token'], 'go-token');
      expect((source.data['user'] as Map)['id'], 'profile-id');
      expect(source.data['authenticated'], isTrue);
      expect(source.data.containsKey('account'), isFalse);
      expect(await secrets.readCredentials('picacg'), (
        user: 'person@example.com',
        password: 'secure-password',
      ));

      final persisted = jsonDecode(
        await File(
          '${tempDirectory.path}/comic_source/picacg.data',
        ).readAsString(),
      );
      expect(jsonEncode(persisted), isNot(contains('secure-password')));
    },
  );

  test('Pica account APIs contain secure credential read failures', () async {
    final memory = _MemorySecretStore()..failReads = true;
    final secrets = SourceCredentialStore(memory);
    final network = PicacgNetwork(
      dioFactory: _dioFactory(
        _RecordingAdapter(
          (_) => _jsonResponse(500, {'message': 'must not request'}),
        ),
      ),
    );
    final source = buildPicacgSource(
      credentialStore: secrets,
      network: network,
    );
    source.data.addAll(<String, dynamic>{
      'token': 'prior-token',
      'apiBaseUrl': picacgApiHosts['picacomic'],
      'authenticated': true,
    });

    final login = await source.account!.login!('new-user', 'new-password');

    expect(login.error, isTrue);
    expect(source.data['token'], 'prior-token');
    expect(source.data['authenticated'], isTrue);

    await source.account!.logout!();
    expect(source.data.containsKey('token'), isFalse);
    expect(source.data.containsKey('authenticated'), isFalse);
  });

  test(
    'Pica login rolls back source state when secure persistence fails',
    () async {
      final adapter = _RecordingAdapter((options) {
        if (options.uri.path == '/auth/sign-in') {
          return _jsonResponse(200, {
            'message': 'success',
            'data': {'token': 'new-token'},
          });
        }
        if (options.uri.path == '/users/profile') {
          return _jsonResponse(200, {
            'message': 'success',
            'data': {
              'user': {
                '_id': 'new-profile',
                'name': 'New User',
                'email': 'new@example.com',
              },
            },
          });
        }
        return _jsonResponse(404, {'message': 'not found'});
      });
      final memory = _MemorySecretStore();
      final secrets = SourceCredentialStore(memory);
      await secrets.saveCredentials('picacg', 'prior-user', 'prior-password');
      final network = PicacgNetwork(dioFactory: _dioFactory(adapter));
      final source = buildPicacgSource(
        credentialStore: secrets,
        network: network,
      );
      source.data.addAll(<String, dynamic>{
        'token': 'prior-token',
        'apiBaseUrl': picacgApiHosts['picacomic'],
        'user': <String, dynamic>{'id': 'prior-profile'},
        'authenticated': true,
      });
      ComicSource.sources.add(source);
      await source.initData!(source);
      memory.failWrites = true;

      final result = await source.account!.login!('new-user', 'new-password');

      expect(result.error, isTrue);
      expect(source.data['token'], 'prior-token');
      expect(source.data['apiBaseUrl'], picacgApiHosts['picacomic']);
      expect((source.data['user'] as Map)['id'], 'prior-profile');
      expect(source.data['authenticated'], isTrue);
      memory.failWrites = false;
      expect(await secrets.readCredentials('picacg'), (
        user: 'prior-user',
        password: 'prior-password',
      ));
    },
  );

  test(
    'Pica initialization migrates and removes legacy plaintext account',
    () async {
      final secrets = SourceCredentialStore(_MemorySecretStore());
      final source = buildPicacgSource(credentialStore: secrets);
      source.data['account'] = ['legacy@example.com', 'legacy-password'];
      source.data['token'] = 'existing-token';

      await source.initData!(source);

      expect(await secrets.readCredentials('picacg'), (
        user: 'legacy@example.com',
        password: 'legacy-password',
      ));
      expect(source.data.containsKey('account'), isFalse);
      expect(source.data['authenticated'], isTrue);
      final persisted = await File(
        '${tempDirectory.path}/comic_source/picacg.data',
      ).readAsString();
      expect(persisted, isNot(contains('legacy-password')));
      expect(persisted, isNot(contains('legacy@example.com')));
    },
  );
}

PicacgDioFactory _dioFactory(HttpClientAdapter adapter) => (options) {
  final dio = Dio(options);
  dio.httpClientAdapter = adapter;
  return dio;
};

ResponseBody _jsonResponse(int statusCode, Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.respond);

  final FutureOrResponse respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.copyWith(data: jsonEncode(options.data)));
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

typedef FutureOrResponse = ResponseBody Function(RequestOptions options);

class _FakePicacgState implements PicacgState {
  _FakePicacgState({
    this.token = '',
    this.reLoginResult = false,
    this.onReLogin,
  });

  @override
  String token;
  @override
  String apiBaseUrl = 'https://picaapi.picacomic.com';
  final bool reLoginResult;
  final Future<bool> Function()? onReLogin;
  int reLoginCalls = 0;

  @override
  String get channel => '3';
  @override
  String get imageQuality => 'original';
  @override
  List<String>? getAccount() => null;
  @override
  Future<bool> reLogin() async {
    reLoginCalls++;
    return onReLogin?.call() ?? reLoginResult;
  }

  @override
  void setApiBaseUrl(String url) => apiBaseUrl = url;
}

class _MemorySecretStore implements SecretKeyValueStore {
  final Map<String, String> values = {};
  bool failReads = false;
  bool failWrites = false;

  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('secure read failed');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('secure write failed');
    values[key] = value;
  }
}
