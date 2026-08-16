/// 列表/UI 态 Provider。
///
/// 管理 UI 层状态：Ctrl 键状态、ScrollPhysics、条漫列宽、工具栏锁定、页码显隐。
/// 与 [ReaderProvider]（内容态）分离，单一职责。持久化字段写入 [ReaderConf]。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../foundation/reader_config.dart';
import '../widgets/toast.dart';

/// 访问 [ListStateProvider] 的便捷扩展。
extension BuildContextListState on BuildContext {
  ListStateProvider get stateReader => read<ListStateProvider>();
  ListStateProvider get stateWatcher => watch<ListStateProvider>();
  T stateSelector<T>(T Function(ListStateProvider) s) =>
      select<ListStateProvider, T>(s);
}

class ListStateProvider extends ChangeNotifier {
  /// 是否按下了 Ctrl（桌面端翻页/选择切换 physics 用）。
  bool _isCtrlPressed = false;
  bool get isCtrlPressed => _isCtrlPressed;
  set isCtrlPressed(bool value) {
    _isCtrlPressed = value;
    notifyListeners();
  }

  /// 列表 ScrollPhysics（默认弹性回弹，Ctrl 下可切 NeverScrollable 锁滚动）。
  ScrollPhysics _physics = const BouncingScrollPhysics();
  ScrollPhysics get physics => _physics;
  set physics(ScrollPhysics physics) {
    _physics = physics;
    notifyListeners();
  }

  /// 条漫模式列表宽占屏宽比例（持久化）。
  late double _verticalListWidthRatio;
  double get verticalListWidthRatio => _verticalListWidthRatio;
  set verticalListWidthRatio(double width) {
    _verticalListWidthRatio = width;
    ReaderConf.instance.verticalListWidthRatio = width;
    notifyListeners();
  }

  /// 锁定工具栏（持久化 + Toast）。锁定后翻页或滚动不会自动隐藏工具栏。
  late bool _lockMenu;
  bool get lockMenu => _lockMenu;
  void toggleLockMenu() {
    _lockMenu = !_lockMenu;
    ReaderConf.instance.menuLocked = _lockMenu;
    notifyListeners();
    Toast.show(message: _lockMenu ? '工具栏已锁定' : '工具栏已解锁');
  }

  /// 页码显隐（持久化，仅切内存态不弹 Toast）。
  late bool _showPageNumbers;
  bool get showPageNumbers => _showPageNumbers;
  void toggleShowPageNumbers() {
    _showPageNumbers = !_showPageNumbers;
    ReaderConf.instance.showPageNumbers = _showPageNumbers;
    notifyListeners();
  }

  ListStateProvider() {
    _verticalListWidthRatio = ReaderConf.instance.verticalListWidthRatio;
    _lockMenu = ReaderConf.instance.menuLocked;
    _showPageNumbers = ReaderConf.instance.showPageNumbers;
  }
}
