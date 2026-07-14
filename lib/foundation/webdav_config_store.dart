import 'package:shared_preferences/shared_preferences.dart';

import 'webdav_client.dart';

/// Persists the user-entered WebDAV endpoint and credentials.
///
/// The password is never rendered as plain text by the UI. SharedPreferences is
/// used because the project currently has no secure-storage dependency.
class WebDavConfigStore {
  const WebDavConfigStore(this.preferences);

  static const urlKey = 'webdav.url';
  static const usernameKey = 'webdav.username';
  static const passwordKey = 'webdav.password';

  final SharedPreferences preferences;

  static Future<WebDavConfigStore> create() async =>
      WebDavConfigStore(await SharedPreferences.getInstance());

  WebDavConfig? read() {
    final url = preferences.getString(urlKey)?.trim() ?? '';
    if (url.isEmpty) return null;
    return WebDavConfig(
      url: url,
      username: preferences.getString(usernameKey) ?? '',
      password: preferences.getString(passwordKey) ?? '',
    );
  }

  Future<bool> save(WebDavConfig config) async {
    final urlSaved = await preferences.setString(urlKey, config.url.trim());
    final usernameSaved = await preferences.setString(
      usernameKey,
      config.username,
    );
    final passwordSaved = await preferences.setString(
      passwordKey,
      config.password,
    );
    return urlSaved && usernameSaved && passwordSaved;
  }

  Future<bool> clear() async {
    final urlRemoved = await preferences.remove(urlKey);
    final usernameRemoved = await preferences.remove(usernameKey);
    final passwordRemoved = await preferences.remove(passwordKey);
    return urlRemoved || usernameRemoved || passwordRemoved;
  }

  String get statusLabel {
    final config = read();
    if (config == null) return '未配置';
    final uri = Uri.tryParse(config.url);
    return uri?.host.isNotEmpty == true ? uri!.host : '已配置';
  }
}
