import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/foundation/cache_manager.dart';
import 'package:joycomic/foundation/webdav_config_store.dart';
import 'package:joycomic/foundation/webdav_client.dart';
import 'package:joycomic/views/settings/settings_page.dart';
import 'package:joycomic/views/settings/webdav_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'WebDAV page loads and persists URL, user and obscured password',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = WebDavConfigStore(prefs);
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
      await tester.pump();

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
      await tester.pump();

      final saved = store.read();
      expect(saved!.url, 'https://new.example/remote');
      expect(saved.username, 'new-user');
      expect(saved.password, 'new-secret');
      expect(store.statusLabel, 'new.example');
    },
  );

  testWidgets(
    'Settings shows configured WebDAV host and refreshes after return',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = WebDavConfigStore(prefs);
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
