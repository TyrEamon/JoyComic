import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/foundation/cache_manager.dart';
import 'package:joycomic/foundation/webdav_client.dart';
import 'package:joycomic/foundation/webdav_config_store.dart';
import 'package:joycomic/views/settings/settings_page.dart';
import 'package:joycomic/views/settings/webdav_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('WebDAV password is saved only in secure storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final secureStore = _MemorySecureStore();
    final store = WebDavConfigStore(prefs, secureStore: secureStore);

    expect(
      await store.save(
        const WebDavConfig(
          url: 'https://secure.example/dav',
          username: 'reader',
          password: 'app-secret',
        ),
      ),
      isTrue,
    );

    expect(
      prefs.getString(WebDavConfigStore.urlKey),
      'https://secure.example/dav',
    );
    expect(prefs.getString(WebDavConfigStore.usernameKey), 'reader');
    expect(prefs.containsKey(WebDavConfigStore.passwordKey), isFalse);
    expect(secureStore.values[WebDavConfigStore.passwordKey], 'app-secret');
    expect((await store.read())?.password, 'app-secret');
  });

  test('WebDAV migrates a legacy prefs password then removes it', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      WebDavConfigStore.urlKey: 'https://legacy.example/dav',
      WebDavConfigStore.usernameKey: 'legacy-user',
      WebDavConfigStore.passwordKey: 'legacy-secret',
    });
    final prefs = await SharedPreferences.getInstance();
    final secureStore = _MemorySecureStore();
    final store = WebDavConfigStore(prefs, secureStore: secureStore);

    final config = await store.read();

    expect(config?.password, 'legacy-secret');
    expect(secureStore.values[WebDavConfigStore.passwordKey], 'legacy-secret');
    expect(prefs.containsKey(WebDavConfigStore.passwordKey), isFalse);
  });

  test('WebDAV migrates a legacy password even without a saved URL', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      WebDavConfigStore.passwordKey: 'orphaned-secret',
    });
    final prefs = await SharedPreferences.getInstance();
    final secureStore = _MemorySecureStore();
    final store = WebDavConfigStore(prefs, secureStore: secureStore);

    expect(await store.read(), isNull);
    expect(
      secureStore.values[WebDavConfigStore.passwordKey],
      'orphaned-secret',
    );
    expect(prefs.containsKey(WebDavConfigStore.passwordKey), isFalse);
  });

  test(
    'WebDAV keeps a legacy prefs password when secure migration fails',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        WebDavConfigStore.urlKey: 'https://legacy.example/dav',
        WebDavConfigStore.passwordKey: 'legacy-secret',
      });
      final prefs = await SharedPreferences.getInstance();
      final secureStore = _MemorySecureStore(failWrites: true);
      final store = WebDavConfigStore(prefs, secureStore: secureStore);

      final config = await store.read();

      expect(config?.password, 'legacy-secret');
      expect(prefs.getString(WebDavConfigStore.passwordKey), 'legacy-secret');
    },
  );

  testWidgets(
    'WebDAV page loads and persists URL, user and obscured password',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = WebDavConfigStore(prefs, secureStore: _MemorySecureStore());
      await store.save(
        const WebDavConfig(
          url: 'https://old.example/dav',
          username: 'old-user',
          password: 'old-secret',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(home: WebDavSettingsPage(configStore: store)),
      );
      await tester.pumpAndSettle();

      final passwordField = tester.widget<TextField>(
        find.byKey(const Key('webdav-password')),
      );
      expect(passwordField.obscureText, isTrue);
      expect(passwordField.controller!.text, 'old-secret');
      expect(find.widgetWithText(Text, 'old-secret'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('webdav-url')),
        'https://new.example/remote',
      );
      await tester.enterText(find.byKey(const Key('webdav-user')), 'new-user');
      await tester.enterText(
        find.byKey(const Key('webdav-password')),
        'new-secret',
      );
      await tester.tap(find.byKey(const Key('webdav-save')));
      await tester.pumpAndSettle();

      final saved = await store.read();
      expect(saved!.url, 'https://new.example/remote');
      expect(saved.username, 'new-user');
      expect(saved.password, 'new-secret');
      expect(store.statusLabel, 'new.example');
    },
  );

  testWidgets('WebDAV config load can finish after the page is disposed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      WebDavConfigStore.urlKey: 'https://slow.example/dav',
    });
    final prefs = await SharedPreferences.getInstance();
    final secureStore = _BlockingSecureStore();
    final store = WebDavConfigStore(prefs, secureStore: secureStore);

    await tester.pumpWidget(
      MaterialApp(home: WebDavSettingsPage(configStore: store)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    secureStore.readCompleter.complete('late-secret');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Settings shows configured WebDAV host and refreshes after return',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = WebDavConfigStore(prefs, secureStore: _MemorySecureStore());
      await store.save(
        const WebDavConfig(
          url: 'https://before.example/dav',
          username: 'user',
          password: 'secret',
        ),
      );
      final cache = _ImmediateCacheManager();
      late final GoRouter router;
      router = GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (_, __) =>
                SettingsPage(cacheManager: cache, webDavConfigStore: store),
          ),
          GoRoute(
            path: '/webdav',
            builder: (context, state) => Scaffold(
              body: TextButton(
                key: const Key('update-webdav'),
                onPressed: () async {
                  await store.save(
                    const WebDavConfig(
                      url: 'https://after.example/dav',
                      username: 'user',
                      password: 'secret',
                    ),
                  );
                  if (context.mounted) context.pop();
                },
                child: const Text('更新并返回'),
              ),
            ),
          ),
          GoRoute(
            path: '/settings/reader',
            builder: (_, __) => const SizedBox(),
          ),
          GoRoute(path: '/login', builder: (_, __) => const SizedBox()),
          GoRoute(
            path: '/settings/source',
            builder: (_, __) => const SizedBox(),
          ),
          GoRoute(path: '/about', builder: (_, __) => const SizedBox()),
          GoRoute(path: '/logs', builder: (_, __) => const SizedBox()),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      expect(find.text('before.example'), findsOneWidget);

      await tester.tap(find.text('WebDAV 同步'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('update-webdav')));
      await tester.pumpAndSettle();

      expect(find.text('after.example'), findsOneWidget);
    },
  );
}

class _MemorySecureStore implements WebDavSecureStore {
  _MemorySecureStore({
    Map<String, String>? initialValues,
    this.failWrites = false,
  }) : values = <String, String>{...?initialValues};

  final Map<String, String> values;
  final bool failWrites;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('secure storage unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _BlockingSecureStore implements WebDavSecureStore {
  final Completer<String?> readCompleter = Completer<String?>();

  @override
  Future<String?> read(String key) => readCompleter.future;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

class _ImmediateCacheManager extends CacheManager {
  _ImmediateCacheManager()
    : super(
        rootDirectory: Directory.systemTemp,
        cacheDirectory: Directory.systemTemp,
        temporaryDirectory: Directory.systemTemp,
        logDirectory: Directory.systemTemp,
        downloadTemporaryDirectory: Directory.systemTemp,
      );

  @override
  Future<CacheSize> calculateSize({
    int? imageCacheBytes,
    Iterable<String> extraPaths = const <String>[],
  }) async => const CacheSize(diskBytes: 0, imageCacheBytes: 0);
}
