/// 应用全局设置与数据目录管理。
library app_data;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../comic_source/built_in/registrar.dart';
import '../comic_source/comic_source.dart';
import 'reader_config.dart';

class AppData {
  AppData._create();
  static final AppData instance = AppData._create();

  static const _themeModeKey = 'themeMode';
  static const _legacyDarkModeKey = 'enableDarkMode';

  late SharedPreferences prefs;
  late String dataPath;

  /// 当前主题及其即时变更通知。
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

  ThemeMode get themeMode {
    final name = prefs.getString(_themeModeKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  set themeMode(ThemeMode mode) {
    prefs.setString(_themeModeKey, mode.name);
    themeNotifier.value = mode;
  }

  /// 旧布尔接口兼容层；system 在布尔语义下视为非强制深色。
  bool get enableDarkMode => themeMode == ThemeMode.dark;
  set enableDarkMode(bool value) =>
      themeMode = value ? ThemeMode.dark : ThemeMode.light;

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    await _restoreThemeMode();
    final dir = await getApplicationSupportDirectory();
    dataPath = dir.path;
    ComicSource.dataPathProvider = () => dataPath;
    ReaderConf.instance.inject(prefs);
  }

  Future<void> _restoreThemeMode() async {
    ThemeMode mode;
    if (prefs.containsKey(_themeModeKey)) {
      mode = themeMode;
    } else if (prefs.containsKey(_legacyDarkModeKey)) {
      mode = prefs.getBool(_legacyDarkModeKey) == true
          ? ThemeMode.dark
          : ThemeMode.light;
      await prefs.setString(_themeModeKey, mode.name);
      await prefs.remove(_legacyDarkModeKey);
    } else {
      mode = ThemeMode.system;
    }
    themeNotifier.value = mode;
  }
}
