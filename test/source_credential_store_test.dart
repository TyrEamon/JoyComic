import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/foundation/source_credential_store.dart';

void main() {
  group('SourceCredentialStore', () {
    test('keeps credentials and sessions isolated by source key', () async {
      final backend = MemorySecretKeyValueStore();
      final store = SourceCredentialStore(backend);

      await store.saveCredentials('jm', 'jm-user', 'jm-password');
      await store.saveSession('jm', 'avs', 'jm-avs');
      await store.saveCredentials('picacg', 'pica-user', 'pica-password');
      await store.saveSession('picacg', 'token', 'pica-token');

      expect(await store.readCredentials('jm'), (
        user: 'jm-user',
        password: 'jm-password',
      ));
      expect(await store.readSession('jm', 'avs'), 'jm-avs');
      expect(await store.readSession('jm', 'token'), isNull);
      expect(await store.readCredentials('picacg'), (
        user: 'pica-user',
        password: 'pica-password',
      ));
      expect(await store.readSession('picacg', 'token'), 'pica-token');
      expect(await store.readSession('picacg', 'avs'), isNull);

      expect(backend.values.length, 2);
      expect(jsonEncode(backend.values), isNot(contains('unrelated-source')));
    });

    test('clearSource removes only the selected source secrets', () async {
      final store = SourceCredentialStore(MemorySecretKeyValueStore());
      await store.saveCredentials('jm', 'jm-user', 'jm-password');
      await store.saveSession('jm', 'avs', 'jm-avs');
      await store.saveCredentials('picacg', 'pica-user', 'pica-password');

      await store.clearSource('jm');

      expect(await store.readCredentials('jm'), isNull);
      expect(await store.readSession('jm', 'avs'), isNull);
      expect(await store.readCredentials('picacg'), (
        user: 'pica-user',
        password: 'pica-password',
      ));
    });

    test(
      'empty session values remove the session without credentials',
      () async {
        final store = SourceCredentialStore(MemorySecretKeyValueStore());
        await store.saveCredentials('jm', 'user', 'password');
        await store.saveSession('jm', 'avs', 'session');

        await store.saveSession('jm', 'avs', '');

        expect(await store.readSession('jm', 'avs'), isNull);
        expect(await store.readCredentials('jm'), (
          user: 'user',
          password: 'password',
        ));
      },
    );
  });
}

class MemorySecretKeyValueStore implements SecretKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
