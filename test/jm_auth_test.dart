import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/comic_source/built_in/jm.dart';
import 'package:joycomic/comic_source/comic_source.dart';
import 'package:joycomic/foundation/source_credential_store.dart';
import 'package:joycomic/network/jm/jm_headers.dart';
import 'package:joycomic/network/jm/jm_network.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/network/source_state.dart';
import 'package:joycomic/views/auth/login_page.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('joycomic-jm-auth-');
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

  test('JM API headers include AVS cookie only for a nonempty session', () {
    final withoutAvs = buildApiOptions(1700000000);
    final withAvs = buildApiOptions(1700000000, avs: 'session-value');

    expect(withoutAvs.headers.containsKey('Cookie'), isFalse);
    expect(withAvs.headers['Cookie'], 'AVS=session-value');
  });

  test(
    'JM login requires s and securely persists credentials and AVS',
    () async {
      final secrets = SourceCredentialStore(_MemorySecretStore());
      final state = _FakeJmState();
      final network = JmNetwork(
        credentialStore: secrets,
        postRequest: (_, __) async =>
            const Res<dynamic>(<String, dynamic>{'s': 'returned-avs'}),
      )..state = state;

      final result = await network.login('entered-user', 'entered-password');

      expect(result.error, isFalse);
      expect(state.avs, 'returned-avs');
      expect(await secrets.readCredentials('jm'), (
        user: 'entered-user',
        password: 'entered-password',
      ));
      expect(await secrets.readSession('jm', 'avs'), 'returned-avs');
    },
  );

  test('JM login rejects missing s and clears stale AVS', () async {
    final secrets = SourceCredentialStore(_MemorySecretStore());
    await secrets.saveCredentials('jm', 'old-user', 'old-password');
    await secrets.saveSession('jm', 'avs', 'stale-avs');
    final state = _FakeJmState(avs: 'stale-avs');
    final network = JmNetwork(
      credentialStore: secrets,
      postRequest: (_, __) async =>
          const Res<dynamic>(<String, dynamic>{'username': 'not-a-session'}),
    )..state = state;

    final result = await network.login('new-user', 'new-password');

    expect(result.error, isTrue);
    expect(state.avs, isEmpty);
    expect(await secrets.readSession('jm', 'avs'), isNull);
    expect(await secrets.readCredentials('jm'), (
      user: 'old-user',
      password: 'old-password',
    ));
  });

  test('JM initialization migrates legacy account and restores AVS', () async {
    final secrets = SourceCredentialStore(_MemorySecretStore());
    await secrets.saveSession('jm', 'avs', 'restored-avs');
    final network = JmNetwork(credentialStore: secrets);
    final source = buildJmSource(credentialStore: secrets, network: network);
    source.data['account'] = <String>['legacy-user', 'legacy-password'];
    source.data['name'] = 'legacy-user';

    await source.initData!(source);

    expect(await secrets.readCredentials('jm'), (
      user: 'legacy-user',
      password: 'legacy-password',
    ));
    expect(source.data.containsKey('account'), isFalse);
    expect(source.data.containsKey('name'), isFalse);
    expect(source.isLogin, isTrue);
    expect(network.state!.avs, 'restored-avs');

    final persisted =
        jsonDecode(
              await File(
                '${tempDirectory.path}/comic_source/jm.data',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    expect(persisted.containsKey('account'), isFalse);
    expect(jsonEncode(persisted), isNot(contains('legacy-password')));
    expect(jsonEncode(persisted), isNot(contains('legacy-user')));
    expect(jsonEncode(persisted), isNot(contains('restored-avs')));
  });

  test(
    'JM initialization clears AVS when credentials cannot be restored',
    () async {
      final secrets = SourceCredentialStore(_MemorySecretStore());
      await secrets.saveSession('jm', 'avs', 'orphaned-avs');
      final network = JmNetwork(credentialStore: secrets);
      final source = buildJmSource(credentialStore: secrets, network: network);

      await source.initData!(source);

      expect(network.state!.avs, isEmpty);
      expect(await secrets.readSession('jm', 'avs'), isNull);
      expect(source.isLogin, isFalse);
    },
  );

  test(
    'buildJmSource shares a supplied credential store with its network',
    () async {
      final secrets = SourceCredentialStore(_MemorySecretStore());
      late JmNetwork capturedNetwork;

      final source = buildJmSource(
        credentialStore: secrets,
        onNetworkReady: (network) => capturedNetwork = network,
      );

      expect(identical(source.credentialStore, secrets), isTrue);
      expect(identical(capturedNetwork.credentialStore, secrets), isTrue);

      await secrets.saveCredentials('jm', 'stored-user', 'stored-password');
      await secrets.saveSession('jm', 'avs', 'stored-avs');
      await capturedNetwork.logout();

      expect(await secrets.readCredentials('jm'), isNull);
      expect(await secrets.readSession('jm', 'avs'), isNull);
    },
  );

  test('buildJmSource rejects mismatched explicit credential stores', () {
    final sourceStore = SourceCredentialStore(_MemorySecretStore());
    final networkStore = SourceCredentialStore(_MemorySecretStore());
    final network = JmNetwork(credentialStore: networkStore);

    expect(
      () => buildJmSource(credentialStore: sourceStore, network: network),
      throwsArgumentError,
    );
  });

  test('a JM 401 re-logs and retries at most once, then clears AVS', () async {
    final adapter = _SequenceAdapter(<int>[401, 401]);
    final state = _FakeJmState(avs: 'expired-avs', reLoginResult: true);
    final network = JmNetwork(
      dioFactory: (options) {
        final dio = Dio(options);
        dio.httpClientAdapter = adapter;
        return dio;
      },
    )..state = state;

    final result = await network.get('https://auth.example/protected');

    expect(result.error, isTrue);
    expect(adapter.requestCount, 2);
    expect(state.reLoginCount, 1);
    expect(state.avs, isEmpty);
  });

  test(
    'a failed JM re-login clears AVS without retrying the request',
    () async {
      final adapter = _SequenceAdapter(<int>[401]);
      final state = _FakeJmState(avs: 'expired-avs', reLoginResult: false);
      final network = JmNetwork(
        dioFactory: (options) {
          final dio = Dio(options);
          dio.httpClientAdapter = adapter;
          return dio;
        },
      )..state = state;

      final result = await network.get('https://auth.example/protected');

      expect(result.error, isTrue);
      expect(adapter.requestCount, 1);
      expect(state.reLoginCount, 1);
      expect(state.avs, isEmpty);
    },
  );

  test(
    'a throwing JM GET re-login clears AVS and stops domain failover',
    () async {
      final adapter = _SequenceAdapter(<int>[401]);
      final state = _FakeJmState(
        avs: 'expired-avs',
        reLoginError: StateError('secure storage unavailable'),
      );
      final network = JmNetwork(
        dioFactory: (options) {
          final dio = Dio(options);
          dio.httpClientAdapter = adapter;
          return dio;
        },
      )..state = state;

      final result = await network.get('https://auth.example/protected');

      expect(result.error, isTrue);
      expect(adapter.requestCount, 1);
      expect(state.reLoginCount, 1);
      expect(state.avs, isEmpty);
    },
  );

  test('JM auth requests never recursively trigger re-login', () async {
    final adapter = _SequenceAdapter(<int>[401]);
    final state = _FakeJmState(
      avs: 'current-avs',
      reLoginError: StateError('must not be called'),
    );
    final network = JmNetwork(
      dioFactory: (options) {
        final dio = Dio(options);
        dio.httpClientAdapter = adapter;
        return dio;
      },
    )..state = state;

    await network.get('https://auth.example/login');

    expect(adapter.requestCount, 1);
    expect(state.reLoginCount, 0);
  });

  test('a protected JM POST 401 re-logs and retries at most once', () async {
    final adapter = _SequenceAdapter(<int>[401, 200]);
    final state = _FakeJmState(avs: 'expired-avs', reLoginResult: true);
    final network = JmNetwork(
      dioFactory: (options) {
        final dio = Dio(options);
        dio.httpClientAdapter = adapter;
        return dio;
      },
    )..state = state;

    final result = await network.post(
      'https://auth.example/comment',
      'comment=hello',
    );

    expect(result.error, isFalse);
    expect(adapter.requestCount, 2);
    expect(state.reLoginCount, 1);
    expect(state.avs, isNotEmpty);
  });

  test('a protected JM POST retries only once and then clears AVS', () async {
    final adapter = _SequenceAdapter(<int>[401, 401]);
    final state = _FakeJmState(avs: 'expired-avs', reLoginResult: true);
    final network = JmNetwork(
      dioFactory: (options) {
        final dio = Dio(options);
        dio.httpClientAdapter = adapter;
        return dio;
      },
    )..state = state;

    final result = await network.post('https://auth.example/like', 'id=123');

    expect(result.error, isTrue);
    expect(adapter.requestCount, 2);
    expect(state.reLoginCount, 1);
    expect(state.avs, isEmpty);
  });

  test('a failed JM POST re-login clears AVS without retrying', () async {
    final adapter = _SequenceAdapter(<int>[401]);
    final state = _FakeJmState(avs: 'expired-avs', reLoginResult: false);
    final network = JmNetwork(
      dioFactory: (options) {
        final dio = Dio(options);
        dio.httpClientAdapter = adapter;
        return dio;
      },
    )..state = state;

    final result = await network.post(
      'https://auth.example/comment',
      'comment=hello',
    );

    expect(result.error, isTrue);
    expect(adapter.requestCount, 1);
    expect(state.reLoginCount, 1);
    expect(state.avs, isEmpty);
  });

  test(
    'a throwing JM POST re-login clears AVS and stops domain failover',
    () async {
      final adapter = _SequenceAdapter(<int>[401]);
      final state = _FakeJmState(
        avs: 'expired-avs',
        reLoginError: StateError('secure storage unavailable'),
      );
      final network = JmNetwork(
        dioFactory: (options) {
          final dio = Dio(options);
          dio.httpClientAdapter = adapter;
          return dio;
        },
      )..state = state;

      final result = await network.post(
        'https://auth.example/comment',
        'comment=hello',
      );

      expect(result.error, isTrue);
      expect(adapter.requestCount, 1);
      expect(state.reLoginCount, 1);
      expect(state.avs, isEmpty);
    },
  );

  test('JM auth POST requests never recursively trigger re-login', () async {
    final adapter = _SequenceAdapter(<int>[401]);
    final state = _FakeJmState(
      avs: 'current-avs',
      reLoginError: StateError('must not be called'),
    );
    final network = JmNetwork(
      dioFactory: (options) {
        final dio = Dio(options);
        dio.httpClientAdapter = adapter;
        return dio;
      },
    )..state = state;

    final result = await network.post(
      'https://auth.example/login',
      'username=user&password=wrong',
      includeAvs: false,
    );

    expect(result.error, isTrue);
    expect(adapter.requestCount, 1);
    expect(state.reLoginCount, 0);
  });

  test(
    'JM login restores prior credentials when session persistence fails',
    () async {
      final backend = _FailingWriteSecretStore();
      final secrets = SourceCredentialStore(backend);
      await secrets.saveCredentials('jm', 'old-user', 'old-password');
      backend.failOnWrite = backend.writeCount + 2;
      final network = JmNetwork(
        credentialStore: secrets,
        postRequest: (_, __) async =>
            const Res<dynamic>(<String, dynamic>{'s': 'new-avs'}),
      )..state = _FakeJmState();

      final result = await network.login('new-user', 'new-password');

      expect(result.error, isTrue);
      expect(await secrets.readCredentials('jm'), (
        user: 'old-user',
        password: 'old-password',
      ));
      expect(await secrets.readSession('jm', 'avs'), isNull);
    },
  );

  test(
    'JM login preserves its business error when AVS cleanup fails',
    () async {
      final backend = _FailingWriteSecretStore();
      final secrets = SourceCredentialStore(backend);
      await secrets.saveCredentials('jm', 'old-user', 'old-password');
      await secrets.saveSession('jm', 'avs', 'stale-avs');
      backend.failAllWrites = true;
      final state = _FakeJmState(avs: 'stale-avs');
      final network = JmNetwork(
        credentialStore: secrets,
        postRequest: (_, __) async =>
            const Res<dynamic>(null, errorMessage: 'invalid credentials'),
      )..state = state;

      final result = await network.login('new-user', 'wrong-password');

      expect(result.error, isTrue);
      expect(result.errorMessage, 'invalid credentials');
      expect(state.avs, isEmpty);
    },
  );

  test(
    'JM state invalidates local auth before secure AVS deletion completes',
    () async {
      final backend = _FailingWriteSecretStore();
      final secrets = SourceCredentialStore(backend);
      final network = JmNetwork(credentialStore: secrets);
      final source = buildJmSource(credentialStore: secrets, network: network);
      final state = network.state!;
      await state.setAvs('stale-avs');
      expect(source.isLogin, isTrue);
      backend.failAllWrites = true;
      backend.failAllDeletes = true;

      await expectLater(state.clearAvs(), throwsStateError);

      expect(state.avs, isEmpty);
      expect(source.isLogin, isFalse);
    },
  );

  test(
    'concurrent protected GET and POST share one re-login operation',
    () async {
      final adapter = _PerPathAuthAdapter();
      final reLoginGate = Completer<bool>();
      final state = _FakeJmState(
        avs: 'expired-avs',
        reLoginCompleter: reLoginGate,
      );
      final network = JmNetwork(
        dioFactory: (options) {
          final dio = Dio(options);
          dio.httpClientAdapter = adapter;
          return dio;
        },
      )..state = state;

      final getFuture = network.get('https://auth.example/protected-get');
      final postFuture = network.post(
        'https://auth.example/protected-post',
        'value=1',
      );
      while (state.reLoginCount == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(Duration.zero);
      reLoginGate.complete(true);
      final results = await Future.wait(<Future<Res<dynamic>>>[
        getFuture,
        postFuture,
      ]);

      expect(results.every((result) => !result.error), isTrue);
      expect(state.reLoginCount, 1);
      expect(adapter.attemptsFor('/protected-get'), 2);
      expect(adapter.attemptsFor('/protected-post'), 2);
    },
  );

  test('JM logout waits for in-flight login before clearing auth', () async {
    final secrets = SourceCredentialStore(_MemorySecretStore());
    final loginResponse = Completer<Res<dynamic>>();
    final state = _FakeJmState();
    final network = JmNetwork(
      credentialStore: secrets,
      postRequest: (_, __) => loginResponse.future,
    )..state = state;

    final loginFuture = network.login('user', 'password');
    var logoutCompleted = false;
    final logoutFuture = network.logout().then((_) => logoutCompleted = true);
    await Future<void>.delayed(Duration.zero);

    expect(logoutCompleted, isFalse);

    loginResponse.complete(
      const Res<dynamic>(<String, dynamic>{'s': 'logged-in-avs'}),
    );
    expect((await loginFuture).error, isFalse);
    await logoutFuture;

    expect(await secrets.readCredentials('jm'), isNull);
    expect(await secrets.readSession('jm', 'avs'), isNull);
    expect(state.avs, isEmpty);
  });

  test(
    'source re-login setting 401 terminates without nested re-login',
    () async {
      final secrets = SourceCredentialStore(_MemorySecretStore());
      await secrets.saveCredentials('jm', 'stored-user', 'stored-password');
      await secrets.saveSession('jm', 'avs', 'old-avs');
      final adapter = _AlwaysUnauthorizedAdapter();
      var loginPostCount = 0;
      final network = JmNetwork(
        credentialStore: secrets,
        dioFactory: (options) {
          final dio = Dio(options);
          dio.httpClientAdapter = adapter;
          return dio;
        },
        postRequest: (_, __) async {
          loginPostCount++;
          return const Res<dynamic>(<String, dynamic>{'s': 'new-avs'});
        },
      );
      final source = buildJmSource(
        credentialStore: secrets,
        network: network,
        domainSelector: (_) async => null,
      );
      ComicSource.sources.add(source);
      await source.initData!(source);
      var timedOut = false;

      final result = await network
          .get('https://auth.example/protected')
          .timeout(
            const Duration(milliseconds: 300),
            onTimeout: () {
              timedOut = true;
              return const Res<dynamic>(null, errorMessage: 'timeout');
            },
          );

      expect(timedOut, isFalse);
      expect(result.error, isTrue);
      expect(loginPostCount, 1);
      expect(adapter.attemptsFor('/setting'), 1);
      expect(await secrets.readCredentials('jm'), (
        user: 'stored-user',
        password: 'stored-password',
      ));
      expect(await secrets.readSession('jm', 'avs'), isNull);
      expect(network.state!.avs, isEmpty);
      expect(source.isLogin, isFalse);
    },
  );

  test(
    'source login setting 401 rolls back newly entered credentials',
    () async {
      final secrets = SourceCredentialStore(_MemorySecretStore());
      await secrets.saveCredentials('jm', 'prior-user', 'prior-password');
      await secrets.saveSession('jm', 'avs', 'prior-avs');
      final adapter = _AlwaysUnauthorizedAdapter();
      final network = JmNetwork(
        credentialStore: secrets,
        dioFactory: (options) {
          final dio = Dio(options);
          dio.httpClientAdapter = adapter;
          return dio;
        },
        postRequest: (_, __) async =>
            const Res<dynamic>(<String, dynamic>{'s': 'failed-new-avs'}),
      );
      final source = buildJmSource(
        credentialStore: secrets,
        network: network,
        domainSelector: (_) async => null,
      );
      ComicSource.sources.add(source);
      await source.initData!(source);

      final result = await source.account!.login!(
        'failed-new-user',
        'failed-new-password',
      );

      expect(result.error, isTrue);
      expect(await secrets.readCredentials('jm'), (
        user: 'prior-user',
        password: 'prior-password',
      ));
      expect(await secrets.readSession('jm', 'avs'), isNull);
      expect(network.state!.avs, isEmpty);
      expect(source.isLogin, isFalse);
    },
  );

  test(
    'staggered old-session 401 retries with new auth without second re-login',
    () async {
      final adapter = _StaggeredUnauthorizedAdapter();
      final reLoginGate = Completer<bool>();
      final state = _FakeJmState(avs: 'old-avs', reLoginCompleter: reLoginGate);
      final network = JmNetwork(
        dioFactory: (options) {
          final dio = Dio(options);
          dio.httpClientAdapter = adapter;
          return dio;
        },
      )..state = state;

      final firstFuture = network.get('https://auth.example/first');
      final secondFuture = network.get('https://auth.example/second');
      await adapter.secondRequestStarted.future;
      while (state.reLoginCount == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      reLoginGate.complete(true);
      expect((await firstFuture).error, isFalse);
      adapter.releaseSecond401.complete();
      final secondResult = await secondFuture;

      expect(secondResult.error, isFalse);
      expect(state.reLoginCount, 1);
      expect(adapter.attemptsFor('/first'), 2);
      expect(adapter.attemptsFor('/second'), 2);
    },
  );

  test('stale retried GET 401 does not clear a newer authentication', () async {
    final adapter = _DelayedRetry401Adapter('/stale-get');
    final state = _FakeJmState(avs: 'old-avs');
    final network = JmNetwork(
      credentialStore: SourceCredentialStore(_MemorySecretStore()),
      dioFactory: (options) {
        final dio = Dio(options);
        dio.httpClientAdapter = adapter;
        return dio;
      },
    )..state = state;

    final requestFuture = network.get('https://auth.example/stale-get');
    await adapter.retryStarted.future;
    final newerLogin = await network.login('new-user', 'new-password');
    expect(newerLogin.error, isFalse);
    expect(state.avs, 'newer-avs');
    adapter.releaseRetry401.complete();
    final result = await requestFuture;

    expect(result.error, isTrue);
    expect(state.reLoginCount, 1);
    expect(state.avs, 'newer-avs');
    expect(adapter.attemptsFor('/stale-get'), 2);
  });

  test(
    'stale retried POST 401 does not clear a newer authentication',
    () async {
      final adapter = _DelayedRetry401Adapter('/stale-post');
      final state = _FakeJmState(avs: 'old-avs');
      final network = JmNetwork(
        credentialStore: SourceCredentialStore(_MemorySecretStore()),
        dioFactory: (options) {
          final dio = Dio(options);
          dio.httpClientAdapter = adapter;
          return dio;
        },
      )..state = state;

      final requestFuture = network.post(
        'https://auth.example/stale-post',
        'value=1',
      );
      await adapter.retryStarted.future;
      final newerLogin = await network.login('new-user', 'new-password');
      expect(newerLogin.error, isFalse);
      expect(state.avs, 'newer-avs');
      adapter.releaseRetry401.complete();
      final result = await requestFuture;

      expect(result.error, isTrue);
      expect(state.reLoginCount, 1);
      expect(state.avs, 'newer-avs');
      expect(adapter.attemptsFor('/stale-post'), 2);
    },
  );

  test(
    'failed domain probes return null and release queued auth operations',
    () async {
      final adapter = _ProbeFailureAdapter();
      final secrets = SourceCredentialStore(_MemorySecretStore());
      final state = _FakeJmState();
      final network = JmNetwork(
        credentialStore: secrets,
        dioFactory: (options) {
          final dio = Dio(options);
          dio.httpClientAdapter = adapter;
          return dio;
        },
      )..state = state;

      final selectionFuture = network.runAuthenticationOperation(
        () => network.selectDomain(const <String>[
          'probe-fail.example',
          'probe-hang.example',
        ], timeout: const Duration(milliseconds: 50)),
      );
      final logoutFuture = network.logout();
      final loginFuture = network.login('queued-user', 'queued-password');

      expect(
        await selectionFuture.timeout(const Duration(milliseconds: 300)),
        isNull,
      );
      await logoutFuture.timeout(const Duration(milliseconds: 300));
      final loginResult = await loginFuture.timeout(
        const Duration(milliseconds: 300),
      );

      expect(loginResult.error, isFalse);
      expect(state.avs, 'probe-login-avs');
      expect(adapter.closed, isTrue);
    },
  );

  test(
    'a login started after logout waits and then runs predictably',
    () async {
      final backend = _GatedDeleteSecretStore();
      final secrets = SourceCredentialStore(backend);
      await secrets.saveCredentials('jm', 'old-user', 'old-password');
      final state = _FakeJmState(avs: 'old-avs');
      var loginPostCount = 0;
      final network = JmNetwork(
        credentialStore: secrets,
        postRequest: (_, __) async {
          loginPostCount++;
          return const Res<dynamic>(<String, dynamic>{'s': 'new-avs'});
        },
      )..state = state;

      final logoutFuture = network.logout();
      await backend.deleteStarted.future;
      final loginFuture = network.login('new-user', 'new-password');
      await Future<void>.delayed(Duration.zero);

      expect(loginPostCount, 0);

      backend.releaseDelete.complete();
      await logoutFuture;
      expect((await loginFuture).error, isFalse);
      expect(loginPostCount, 1);
      expect(await secrets.readCredentials('jm'), (
        user: 'new-user',
        password: 'new-password',
      ));
    },
  );

  test('overlapping direct JM logins execute one at a time', () async {
    final firstResponse = Completer<Res<dynamic>>();
    final secondResponse = Completer<Res<dynamic>>();
    var postCount = 0;
    var activePosts = 0;
    var maxActivePosts = 0;
    final network = JmNetwork(
      credentialStore: SourceCredentialStore(_MemorySecretStore()),
      postRequest: (_, __) async {
        postCount++;
        activePosts++;
        if (activePosts > maxActivePosts) maxActivePosts = activePosts;
        final response = await (postCount == 1
            ? firstResponse.future
            : secondResponse.future);
        activePosts--;
        return response;
      },
    )..state = _FakeJmState();

    final firstLogin = network.login('first-user', 'first-password');
    final secondLogin = network.login('second-user', 'second-password');
    await Future<void>.delayed(Duration.zero);

    expect(postCount, 1);
    expect(maxActivePosts, 1);

    firstResponse.complete(
      const Res<dynamic>(<String, dynamic>{'s': 'first-avs'}),
    );
    expect((await firstLogin).error, isFalse);
    while (postCount < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    secondResponse.complete(
      const Res<dynamic>(<String, dynamic>{'s': 'second-avs'}),
    );
    expect((await secondLogin).error, isFalse);
    expect(maxActivePosts, 1);
  });

  test(
    'source account logout waits for the complete source login workflow',
    () async {
      final secrets = SourceCredentialStore(_MemorySecretStore());
      final settingResponse = Completer<Res<dynamic>>();
      final network = JmNetwork(
        credentialStore: secrets,
        postRequest: (_, __) async =>
            const Res<dynamic>(<String, dynamic>{'s': 'source-avs'}),
        getRequest: (_) => settingResponse.future,
      );
      final source = buildJmSource(
        credentialStore: secrets,
        network: network,
        domainSelector: (_) async => null,
      );
      ComicSource.sources.add(source);

      final loginFuture = source.account!.login!('source-user', 'source-pass');
      await Future<void>.delayed(Duration.zero);
      var logoutCompleted = false;
      final logoutFuture = Future<void>.sync(
        () => source.account!.logout!(),
      ).then((_) => logoutCompleted = true);
      await Future<void>.delayed(Duration.zero);

      expect(logoutCompleted, isFalse);

      settingResponse.complete(const Res<dynamic>(<String, dynamic>{}));
      expect((await loginFuture).error, isFalse);
      await logoutFuture;
      expect(await secrets.readCredentials('jm'), isNull);
      expect(source.isLogin, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );

  test('JM login output never logs credentials or AVS values', () async {
    const user = 'secret-user-for-redaction';
    const password = 'secret-password-for-redaction';
    const avs = 'secret-avs-for-redaction';
    final printed = <String>[];
    final network = JmNetwork(
      credentialStore: SourceCredentialStore(_MemorySecretStore()),
      postRequest: (_, __) async =>
          const Res<dynamic>(<String, dynamic>{'s': avs}),
    )..state = _FakeJmState();

    final result = await runZoned(
      () => network.login(user, password),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );

    expect(result.error, isFalse);
    final output = printed.join('\n');
    expect(output, isNot(contains(user)));
    expect(output, isNot(contains(password)));
    expect(output, isNot(contains(avs)));
  });

  testWidgets('successful login pops true to its caller', (tester) async {
    final source = ComicSource.named(
      name: '禁漫',
      key: 'jm',
      filePath: 'test',
      account: AccountConfig.named(
        login: (_, __) async => const Res<bool>(true),
      ),
    );
    ComicSource.sources.add(source);
    bool? loginResult;
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                loginResult = await context.push<bool>('/login');
              },
              child: const Text('open login'),
            ),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginPage(initialSourceKey: 'jm'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('open login'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'user');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();

    expect(loginResult, isTrue);
  });
}

class _MemorySecretStore implements SecretKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeJmState implements JmState {
  _FakeJmState({
    this.avs = '',
    this.reLoginResult = true,
    this.reLoginError,
    this.reLoginCompleter,
  });

  @override
  String apiBaseUrl = 'https://auth.example';
  @override
  String imageBaseUrl = '';
  @override
  String preferredDomain = '';
  @override
  List<JmShunt> shunts = const <JmShunt>[];
  @override
  int selectedShuntKey = 0;
  @override
  String? username = 'signed-in';
  @override
  String avs;

  final bool reLoginResult;
  final Object? reLoginError;
  final Completer<bool>? reLoginCompleter;
  int reLoginCount = 0;

  @override
  Future<void> clearAvs() async => avs = '';

  @override
  List<String>? getAccount() => null;

  @override
  Future<bool> reLogin() async {
    reLoginCount++;
    final error = reLoginError;
    if (error != null) throw error;
    final completer = reLoginCompleter;
    if (completer != null) return completer.future;
    return reLoginResult;
  }

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

class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.statuses);

  final List<int> statuses;
  int requestCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = requestCount < statuses.length
        ? requestCount
        : statuses.length - 1;
    final status = statuses[index];
    requestCount++;
    final body = status == 401
        ? jsonEncode(<String, dynamic>{'errorMsg': '請先登入會員'})
        : jsonEncode(<String, dynamic>{'data': <String, dynamic>{}});
    return ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FailingWriteSecretStore implements SecretKeyValueStore {
  final Map<String, String> values = <String, String>{};
  int writeCount = 0;
  int? failOnWrite;
  bool failAllWrites = false;
  bool failAllDeletes = false;

  @override
  Future<void> delete(String key) async {
    if (failAllDeletes) throw StateError('secure delete failed');
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    if (failAllWrites || writeCount == failOnWrite) {
      throw StateError('secure write failed');
    }
    values[key] = value;
  }
}

class _PerPathAuthAdapter implements HttpClientAdapter {
  final Map<String, int> _attempts = <String, int>{};

  int attemptsFor(String path) => _attempts[path] ?? 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    final attempt = (_attempts[path] ?? 0) + 1;
    _attempts[path] = attempt;
    final status = attempt == 1 ? 401 : 200;
    final body = status == 401
        ? jsonEncode(<String, dynamic>{'errorMsg': '請先登入會員'})
        : jsonEncode(<String, dynamic>{'data': <String, dynamic>{}});
    return ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _AlwaysUnauthorizedAdapter implements HttpClientAdapter {
  final Map<String, int> _attempts = <String, int>{};

  int attemptsFor(String path) => _attempts[path] ?? 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    _attempts[path] = (_attempts[path] ?? 0) + 1;
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{'errorMsg': '請先登入會員'}),
      401,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StaggeredUnauthorizedAdapter implements HttpClientAdapter {
  final Map<String, int> _attempts = <String, int>{};
  final Completer<void> secondRequestStarted = Completer<void>();
  final Completer<void> releaseSecond401 = Completer<void>();

  int attemptsFor(String path) => _attempts[path] ?? 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    final attempt = (_attempts[path] ?? 0) + 1;
    _attempts[path] = attempt;
    if (path == '/second' && attempt == 1) {
      secondRequestStarted.complete();
      await releaseSecond401.future;
    }
    final status = attempt == 1 ? 401 : 200;
    final body = status == 401
        ? jsonEncode(<String, dynamic>{'errorMsg': '請先登入會員'})
        : jsonEncode(<String, dynamic>{'data': <String, dynamic>{}});
    return ResponseBody.fromString(
      body,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _GatedDeleteSecretStore implements SecretKeyValueStore {
  final Map<String, String> values = <String, String>{};
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> releaseDelete = Completer<void>();

  @override
  Future<void> delete(String key) async {
    if (!deleteStarted.isCompleted) deleteStarted.complete();
    await releaseDelete.future;
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _DelayedRetry401Adapter implements HttpClientAdapter {
  _DelayedRetry401Adapter(this.protectedPath);

  final String protectedPath;
  final Map<String, int> _attempts = <String, int>{};
  final Completer<void> retryStarted = Completer<void>();
  final Completer<void> releaseRetry401 = Completer<void>();

  int attemptsFor(String path) => _attempts[path] ?? 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    final attempt = (_attempts[path] ?? 0) + 1;
    _attempts[path] = attempt;
    if (path == '/login') {
      return ResponseBody.fromString(
        jsonEncode(<String, dynamic>{'s': 'newer-avs'}),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
    }
    if (path == protectedPath && attempt == 2) {
      retryStarted.complete();
      await releaseRetry401.future;
    }
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{'errorMsg': '請先登入會員'}),
      401,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ProbeFailureAdapter implements HttpClientAdapter {
  final Completer<void> _neverCompletes = Completer<void>();
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path == '/login' && options.uri.host == 'auth.example') {
      return ResponseBody.fromString(
        jsonEncode(<String, dynamic>{'s': 'probe-login-avs'}),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
    }
    if (options.uri.host == 'probe-hang.example') {
      await _neverCompletes.future;
    }
    return ResponseBody.fromString('', 500);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}
