/// Secure SauceNAO API-key configuration.
library;

import 'source_credential_store.dart';

class SauceNaoConfigStore {
  SauceNaoConfigStore({
    SecretKeyValueStore? store,
    String environmentApiKey = const String.fromEnvironment('SAUCENAO_API_KEY'),
  }) : _store = store ?? const FlutterSecureKeyValueStore(),
       _environmentApiKey = environmentApiKey;

  static const _storageKey = 'joycomic.saucenao.api-key';

  final SecretKeyValueStore _store;
  final String _environmentApiKey;

  Future<String?> readApiKey() async {
    final secureValue = (await _store.read(_storageKey))?.trim();
    if (secureValue != null && secureValue.isNotEmpty) return secureValue;
    final environmentValue = _environmentApiKey.trim();
    return environmentValue.isEmpty ? null : environmentValue;
  }

  Future<void> saveApiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await clearApiKey();
      return;
    }
    await _store.write(_storageKey, trimmed);
  }

  Future<void> clearApiKey() => _store.delete(_storageKey);
}
