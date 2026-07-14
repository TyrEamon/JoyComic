/// 应用全局设置与数据目录管理。
library app_data;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../comic_source/comic_source.dart';
import 'reader_config.dart';

class AppData {
  AppData._create();
  static final AppData instance = AppData._create();

  late SharedPreferences prefs;
  late String dataPath;

  /// 主题切换通知器。
  final ValueNotifier<bool> themeNotifier = ValueNotifier<bool>(true);

  Set<String> get enabledSources =>
      (prefs.getStringList('enabledSources') ?? defaultEnabledSources.toList()).toSet();
  set enabledSources(Set<String> v) => prefs.setStringList('enabledSources', v.toList());

  bool get enableDynamicColor => prefs.getBool('enableDynamicColor') ?? true;
  set enableDynamicColor(bool v) => prefs.setBool('enableDynamicColor', v);

  bool get enableDarkMode => prefs.getBool('enableDarkMode') ?? true;
  set enableDarkMode(bool v) {
    prefs.setBool('enableDarkMode', v);
    themeNotifier.value = v;
  }

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    final dir = await getApplicationSupportDirectory();
    dataPath = dir.path;
    ComicSource.dataPathProvider = () => dataPath;
    ReaderConf.instance.inject(prefs);
  }
}
