/// 阅读器配置（应用偏好中阅读器相关字段的持久化实现）。
///
/// 用 [SharedPreferences] 落盘，不接 DB（阶段4 才接），阅读记录由
/// ReaderProvider 以内存 + prefs 兜底处理。按需收纳，未包含 WebDAV/
/// 代理/下载排序等非阅读器字段。
///
/// 使用：阅读器与设置面板通过 [ReaderConf.instance] 读写，所有 setter
/// 即时落盘。
library reader_config;

import 'package:shared_preferences/shared_preferences.dart';

import '../views/reader/state/read_mode.dart';

/// 阅读器配置单例。
class ReaderConf {
  ReaderConf._internal();
  static final ReaderConf instance = ReaderConf._internal();

  /// 惰性持有的 prefs 句柄，由 [init] 注入。
  SharedPreferences? _prefs;

  /// 在应用初始化阶段注入已就绪的 [SharedPreferences] 实例。
  ///
  /// 由 [AppData.init] 在获取到 prefs 后调用，使后续读取立即可用。
  void inject(SharedPreferences prefs) => _prefs = prefs;

  // ============================ 读取方在此之前应确保已 init ============================

  bool _getBool(String key, bool fallback) =>
      _prefs?.getBool(key) ?? fallback;
  double _getDouble(String key, double fallback) =>
      _prefs?.getDouble(key) ?? fallback;
  int _getInt(String key, int fallback) =>
      _prefs?.getInt(key) ?? fallback;

  void _setBool(String key, bool v) => _prefs?.setBool(key, v);
  void _setDouble(String key, double v) => _prefs?.setDouble(key, v);
  void _setInt(String key, int v) => _prefs?.setInt(key, v);

  // ============================ 阅读模式 ============================

  /// 当前阅读模式。缺省竖直连续。
  ReadMode get readMode => ReadMode.fromName(_prefs?.getString('readMode'));
  set readMode(ReadMode v) => _prefs?.setString('readMode', v.name);

  // ============================ 翻页与滚动 ============================

  /// 条漫模式下一次翻页的滑动距离倍率（× 屏高）。缺省 0.5。
  double get slipFactor => _getDouble('slipFactor', 0.5);
  set slipFactor(double v) => _setDouble('slipFactor', v);

  /// 是否启用手势翻页。缺省 true。
  bool get enableGesture => _getBool('enableGesture', true);
  set enableGesture(bool v) => _setBool('enableGesture', v);

  /// 是否启用翻页动画。缺省 true。
  bool get enablePageAnimation => _getBool('enablePageAnimation', true);
  set enablePageAnimation(bool v) => _setBool('enablePageAnimation', v);

  /// 是否启用音量键翻页。缺省 true。
  ///
  /// iOS 端通常不拦截音量键，保留开关但运行期平台差异由设置 UI 决定是否暴露。
  bool get enableVolume => _getBool('enableVolume', true);
  set enableVolume(bool v) => _setBool('enableVolume', v);

  /// 平滑滚动速度（每帧像素数）。缺省 2.0。
  double get scrollSpeed => _getDouble('scrollSpeed', 2.0);
  set scrollSpeed(double v) => _setDouble('scrollSpeed', v);

  /// 翻页间隔（相关于平滑滚动节流，单位帧）。缺省 5。
  int get interval => _getInt('interval', 5);
  set interval(int v) => _setInt('interval', v);

  // ============================ 菜单与显示 ============================

  /// 竖向阅读菜单呼出区占屏高比例。缺省 0.3。
  double get verticalCenterFraction =>
      _getDouble('verticalCenterFraction', 0.3);
  set verticalCenterFraction(double v) =>
      _setDouble('verticalCenterFraction', v);

  /// 横向阅读菜单呼出区占屏宽比例。缺省 0.4。
  double get horizontalCenterFraction =>
      _getDouble('horizontalCenterFraction', 0.4);
  set horizontalCenterFraction(double v) =>
      _setDouble('horizontalCenterFraction', v);

  /// 条漫模式列表宽占屏宽比例。缺省 1.0。
  double get verticalListWidthRatio =>
      _getDouble('verticalListWidthRatio', 1.0);
  set verticalListWidthRatio(double v) =>
      _setDouble('verticalListWidthRatio', v);

  /// 是否显示阅读器页码标签。缺省 true。
  bool get showPageNumbers => _getBool('showPageNumbers', true);
  set showPageNumbers(bool v) => _setBool('showPageNumbers', v);

  /// 菜单是否已锁定（锁定后滚动不隐藏工具栏）。缺省 false。
  bool get menuLocked => _getBool('menuLocked', false);
  set menuLocked(bool v) => _setBool('menuLocked', v);

  // ============================ 预加载 ============================

  /// 预加载图片数量（阅读器设置可调 2~8）。缺省 4。
  int get preloadImageCount => _getInt('preloadImageCount', 4);
  set preloadImageCount(int v) => _setInt('preloadImageCount', v);
}
