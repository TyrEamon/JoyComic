/// Minimal preference access used by settings persistence.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Small, injectable preference contract with fallible asynchronous writes.
abstract interface class PreferencesStore {
  bool containsKey(String key);
  bool? getBool(String key);
  double? getDouble(String key);
  int? getInt(String key);
  String? getString(String key);
  List<String>? getStringList(String key);

  Future<bool> setBool(String key, bool value);
  Future<bool> setDouble(String key, double value);
  Future<bool> setInt(String key, int value);
  Future<bool> setString(String key, String value);
  Future<bool> setStringList(String key, List<String> value);
  Future<bool> remove(String key);
}

/// Production adapter around [SharedPreferences].
final class SharedPreferencesStore implements PreferencesStore {
  const SharedPreferencesStore(this.preferences);

  final SharedPreferences preferences;

  @override
  bool containsKey(String key) => preferences.containsKey(key);
  @override
  bool? getBool(String key) => preferences.getBool(key);
  @override
  double? getDouble(String key) => preferences.getDouble(key);
  @override
  int? getInt(String key) => preferences.getInt(key);
  @override
  String? getString(String key) => preferences.getString(key);
  @override
  List<String>? getStringList(String key) => preferences.getStringList(key);
  @override
  Future<bool> remove(String key) => preferences.remove(key);
  @override
  Future<bool> setBool(String key, bool value) =>
      preferences.setBool(key, value);
  @override
  Future<bool> setDouble(String key, double value) =>
      preferences.setDouble(key, value);
  @override
  Future<bool> setInt(String key, int value) => preferences.setInt(key, value);
  @override
  Future<bool> setString(String key, String value) =>
      preferences.setString(key, value);
  @override
  Future<bool> setStringList(String key, List<String> value) =>
      preferences.setStringList(key, value);
}
