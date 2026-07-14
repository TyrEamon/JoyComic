/// 应用全局设置与数据目录管理。
library app_data;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../comic_source/built_in/registrar.dart';
import '../comic_source/comic_source.dart';
import 'preferences_store.dart';
import 'reader_config.dart';

class AppData {
  AppData._create();
  static final AppData instance = AppData._create();

  static const _themeModeKey = 'themeMode';
  static const _legacyDarkModeKey = 'enableDarkMode';

  late SharedPreferences prefs;
  late PreferencesStore _preferenceStore;
  late String dataPath;
  ThemeMode _themeMode = ThemeMode.system;

  /// 当前主题及其持久化成功后的变更通知。
  final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  Set<String> get enabledSources =>
      (prefs.getStringList('enabledSources') ?? defaultEnabledSources.toList())
          .toSet();
  set enabledSources(Set<String> v) =>
      prefs.setStringList('enabledSources', v.toList());

  bool get enableDynamicColor => prefs.getBool('enableDynamicColor') ?? true;
  set enableDynamicColor(bool v) => prefs.setBool('enableDynamicColor', v);

  ThemeMode get themeMode => _themeMode;

  /// Persists [mode] before publishing it to listeners.
  Future<bool> setThemeMode(ThemeMode mode) async {
    final persisted = await _safeWrite(
      () => _preferenceStore.setString(_themeModeKey, mode.name),
    );
    if (!persisted) return false;
    _setRuntimeThemeMode(mode);
    return true;
  }

  /// 旧布尔读取接口兼容层；system 在布尔语义下视为非强制深色。
  bool get enableDarkMode => themeMode == ThemeMode.dark;

  /// 旧布尔写入语义的异步兼容入口。
  Future<bool> setDarkMode(bool value) =>
      setThemeMode(value ? ThemeMode.dark : ThemeMode.light);

  Future<void> init({PreferencesStore? preferenceStore}) async {
    prefs = await SharedPreferences.getInstance();
    _preferenceStore = preferenceStore ?? SharedPreferencesStore(prefs);
    await _restoreThemeMode();
    final dir = await getApplicationSupportDirectory();
    dataPath = dir.path;
    ComicSource.dataPathProvider = () => dataPath;
    ReaderConf.instance.inject(prefs);
  }

  Future<void> _restoreThemeMode() async {
    ThemeMode mode;
    if (_preferenceStore.containsKey(_themeModeKey)) {
      mode = _modeFromName(_preferenceStore.getString(_themeModeKey));
    } else if (_preferenceStore.containsKey(_legacyDarkModeKey)) {
      mode = _preferenceStore.getBool(_legacyDarkModeKey) == true
          ? ThemeMode.dark
          : ThemeMode.light;
      final migrated = await _safeWrite(
        () => _preferenceStore.setString(_themeModeKey, mode.name),
      );
      if (migrated) {
        await _safeWrite(() => _preferenceStore.remove(_legacyDarkModeKey));
      }
    } else {
      mode = ThemeMode.system;
    }
    _setRuntimeThemeMode(mode);
  }

  ThemeMode _modeFromName(String? name) => ThemeMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => ThemeMode.system,
  );

  void _setRuntimeThemeMode(ThemeMode mode) {
    _themeMode = mode;
    themeNotifier.value = mode;
  }

  Future<bool> _safeWrite(Future<bool> Function() write) async {
    try {
      return await write();
    } catch (_) {
      return false;
    }
  }
}
