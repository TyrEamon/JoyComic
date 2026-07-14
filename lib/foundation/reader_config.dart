/// 阅读器配置（应用偏好中阅读器相关字段的持久化实现）。
library reader_config;

import 'package:shared_preferences/shared_preferences.dart';

import '../views/reader/state/read_mode.dart';
import 'preferences_store.dart';

/// 阅读器配置单例。
class ReaderConf {
  ReaderConf._internal();
  static final ReaderConf instance = ReaderConf._internal();

  PreferencesStore? _store;
  final Set<Future<bool>> _pendingWrites = <Future<bool>>{};

  /// 在应用初始化阶段注入已就绪的 [SharedPreferences] 实例。
  void inject(SharedPreferences prefs) =>
      injectStore(SharedPreferencesStore(prefs));

  /// 注入最小偏好接口，供生产适配器和失败/延迟写测试共用。
  void injectStore(PreferencesStore store) {
    _store = store;
    _pendingWrites.clear();
  }

  bool _getBool(String key, bool fallback) => _store?.getBool(key) ?? fallback;
  double _getDouble(String key, double fallback) =>
      _store?.getDouble(key) ?? fallback;
  int _getInt(String key, int fallback) => _store?.getInt(key) ?? fallback;

  void _queue(Future<bool> Function() write) {
    late Future<bool> tracked;
    tracked = Future<bool>.sync(write)
        .then((value) => value, onError: (_) => false)
        .whenComplete(() => _pendingWrites.remove(tracked));
    _pendingWrites.add(tracked);
  }

  void _setBool(String key, bool value) {
    final store = _store;
    if (store != null) _queue(() => store.setBool(key, value));
  }

  void _setDouble(String key, double value) {
    final store = _store;
    if (store != null) _queue(() => store.setDouble(key, value));
  }

  void _setInt(String key, int value) {
    final store = _store;
    if (store != null) _queue(() => store.setInt(key, value));
  }

  void _setString(String key, String value) {
    final store = _store;
    if (store != null) _queue(() => store.setString(key, value));
  }

  /// Waits for all writes queued before or during the flush.
  Future<bool> flushPendingWrites() async {
    var succeeded = true;
    while (_pendingWrites.isNotEmpty) {
      final results = await Future.wait(List<Future<bool>>.of(_pendingWrites));
      succeeded = succeeded && results.every((result) => result);
    }
    return succeeded;
  }

  /// 当前阅读模式。缺省竖直连续。
  ReadMode get readMode => ReadMode.fromName(_store?.getString('readMode'));
  set readMode(ReadMode v) => _setString('readMode', v.name);

  double get slipFactor => _getDouble('slipFactor', 0.5);
  set slipFactor(double v) => _setDouble('slipFactor', v);

  bool get enableGesture => _getBool('enableGesture', true);
  set enableGesture(bool v) => _setBool('enableGesture', v);

  bool get enablePageAnimation => _getBool('enablePageAnimation', true);
  set enablePageAnimation(bool v) => _setBool('enablePageAnimation', v);

  bool get enableVolume => _getBool('enableVolume', true);
  set enableVolume(bool v) => _setBool('enableVolume', v);

  double get scrollSpeed => _getDouble('scrollSpeed', 2.0);
  set scrollSpeed(double v) => _setDouble('scrollSpeed', v);

  int get interval => _getInt('interval', 5);
  set interval(int v) => _setInt('interval', v);

  double get verticalCenterFraction =>
      _getDouble('verticalCenterFraction', 0.3);
  set verticalCenterFraction(double v) =>
      _setDouble('verticalCenterFraction', v);

  double get horizontalCenterFraction =>
      _getDouble('horizontalCenterFraction', 0.4);
  set horizontalCenterFraction(double v) =>
      _setDouble('horizontalCenterFraction', v);

  double get verticalListWidthRatio =>
      _getDouble('verticalListWidthRatio', 1.0);
  set verticalListWidthRatio(double v) =>
      _setDouble('verticalListWidthRatio', v);

  bool get showPageNumbers => _getBool('showPageNumbers', true);
  set showPageNumbers(bool v) => _setBool('showPageNumbers', v);

  bool get menuLocked => _getBool('menuLocked', false);
  set menuLocked(bool v) => _setBool('menuLocked', v);

  bool get autoHideToolbar => !menuLocked;
  set autoHideToolbar(bool v) => menuLocked = !v;

  /// 预加载图片数量（阅读器设置可调 2~8）。缺省 4。
  int get preloadImageCount => _getInt('preloadImageCount', 4);
  set preloadImageCount(int v) => _setInt('preloadImageCount', v);
}
