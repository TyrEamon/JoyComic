import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'webdav_client.dart';

/// Minimal secure key/value API used by [WebDavConfigStore].
///
/// Keeping this boundary injectable lets tests avoid platform channels while
/// production uses the operating system credential store.
abstract interface class WebDavSecureStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterWebDavSecureStore implements WebDavSecureStore {
  const FlutterWebDavSecureStore([this.storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

/// Persists the user-entered WebDAV endpoint and credentials.
///
/// URL and username are non-sensitive preferences. Passwords are stored only
/// in secure storage; [read] migrates the legacy SharedPreferences password
/// and removes it only after the secure write succeeds.
class WebDavConfigStore {
  const WebDavConfigStore(
    this.preferences, {
    this.secureStore = const FlutterWebDavSecureStore(),
  });

  static const urlKey = 'webdav.url';
  static const usernameKey = 'webdav.username';
  static const passwordKey = 'webdav.password';

  final SharedPreferences preferences;
  final WebDavSecureStore secureStore;

  static Future<WebDavConfigStore> create() async =>
      WebDavConfigStore(await SharedPreferences.getInstance());

  Future<WebDavConfig?> read() async {
    final url = preferences.getString(urlKey)?.trim() ?? '';
    final legacyPassword = preferences.getString(passwordKey);
    String? password;
    try {
      password = await secureStore.read(passwordKey);
    } catch (_) {
      password = null;
    }

    if (password == null && legacyPassword != null) {
      password = legacyPassword;
      try {
        await secureStore.write(passwordKey, legacyPassword);
        await preferences.remove(passwordKey);
      } catch (_) {
        // Keep the legacy value until a later read can migrate it safely.
      }
    } else if (password != null && legacyPassword != null) {
      // A secure value already exists, so the plaintext legacy copy is stale.
      await preferences.remove(passwordKey);
    }

    if (url.isEmpty) return null;
    return WebDavConfig(
      url: url,
      username: preferences.getString(usernameKey) ?? '',
      password: password ?? '',
    );
  }

  Future<bool> save(WebDavConfig config) async {
    try {
      await secureStore.write(passwordKey, config.password);
    } catch (_) {
      return false;
    }

    final urlSaved = await preferences.setString(urlKey, config.url.trim());
    final usernameSaved = await preferences.setString(
      usernameKey,
      config.username,
    );
    await preferences.remove(passwordKey);
    return urlSaved && usernameSaved;
  }

  Future<bool> clear() async {
    var securePasswordExisted = false;
    try {
      securePasswordExisted = await secureStore.read(passwordKey) != null;
      await secureStore.delete(passwordKey);
    } catch (_) {
      return false;
    }

    final urlRemoved = await preferences.remove(urlKey);
    final usernameRemoved = await preferences.remove(usernameKey);
    final legacyPasswordRemoved = await preferences.remove(passwordKey);
    return urlRemoved ||
        usernameRemoved ||
        legacyPasswordRemoved ||
        securePasswordExisted;
  }

  String get statusLabel {
    final url = preferences.getString(urlKey)?.trim() ?? '';
    if (url.isEmpty) return '未配置';
    final uri = Uri.tryParse(url);
    return uri?.host.isNotEmpty == true ? uri!.host : '已配置';
  }
}
