/// Secure, source-keyed credential and session persistence.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecretKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecretKeyValueStore {
  const FlutterSecureKeyValueStore([
    this.storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class SourceCredentialStore {
  SourceCredentialStore([SecretKeyValueStore? store])
    : _store = store ?? const FlutterSecureKeyValueStore();

  final SecretKeyValueStore _store;

  Future<void> saveCredentials(
    String sourceKey,
    String user,
    String password,
  ) async {
    final record = await _readRecord(sourceKey);
    record['user'] = user;
    record['password'] = password;
    await _writeRecord(sourceKey, record);
  }

  Future<({String user, String password})?> readCredentials(
    String sourceKey,
  ) async {
    final record = await _readRecord(sourceKey);
    final user = record['user'];
    final password = record['password'];
    if (user is! String || password is! String) return null;
    if (user.isEmpty || password.isEmpty) return null;
    return (user: user, password: password);
  }

  Future<void> saveSession(String sourceKey, String name, String value) async {
    final record = await _readRecord(sourceKey);
    final sessions = _sessions(record);
    if (value.isEmpty) {
      sessions.remove(name);
    } else {
      sessions[name] = value;
    }
    if (sessions.isEmpty) {
      record.remove('sessions');
    } else {
      record['sessions'] = sessions;
    }
    await _writeRecord(sourceKey, record);
  }

  Future<String?> readSession(String sourceKey, String name) async {
    final value = _sessions(await _readRecord(sourceKey))[name];
    return value is String && value.isNotEmpty ? value : null;
  }

  Future<void> clearSource(String sourceKey) => _store.delete(_key(sourceKey));

  Future<Map<String, dynamic>> _readRecord(String sourceKey) async {
    final raw = await _store.read(_key(sourceKey));
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeRecord(
    String sourceKey,
    Map<String, dynamic> record,
  ) async {
    if (record.isEmpty) {
      await clearSource(sourceKey);
      return;
    }
    await _store.write(_key(sourceKey), jsonEncode(record));
  }

  Map<String, dynamic> _sessions(Map<String, dynamic> record) {
    final value = record['sessions'];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  String _key(String sourceKey) =>
      'joycomic.source.${Uri.encodeComponent(sourceKey)}';
}
