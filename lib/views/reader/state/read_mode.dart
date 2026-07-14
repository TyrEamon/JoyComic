/// 阅读模式枚举。
///
/// 决定内容列表的页面组织方式（单列连续流 / 单页或双页翻页），并由
/// [HorizontalList] 据此选择单/双页与是否反向（RTL）。
library;

/// 禁漫 / 哔咔共用的五种阅读模式。
enum ReadMode {
  /// 连续从上到下（条漫流，[VerticalList]）。
  vertical('连续从上到下'),

  /// 单页从左到右（[HorizontalList] 单页，正向）。
  leftToRight('单页从左到右'),

  /// 单页从右到左（[HorizontalList] 单页，反向 RTL）。
  rightToLeft('单页从右到左'),

  /// 双页从左到右（[HorizontalList] 双页，正向）。
  doubleLeftToRight('双页从左到右'),

  /// 双页从右到左（[HorizontalList] 双页，反向 RTL）。
  doubleRightToLeft('双页从右到左');

  /// 设置面板展示名。
  final String displayName;

  const ReadMode(this.displayName);

  /// 由持久化的名称还原，缺省回 [vertical]。
  static ReadMode fromName(String? name) {
    return ReadMode.values.firstWhere(
      (mode) => mode.name == name,
      orElse: () => vertical,
    );
  }

  /// 是否为竖直连续模式。
  bool get isVertical => this == vertical;

  /// 是否为双页模式。
  bool get isDoublePage =>
      this == doubleLeftToRight || this == doubleRightToLeft;

  /// 是否为反向（右到左）模式——横向列表据此决定翻页方向与顺序。
  bool get isReverse =>
      this == ReadMode.rightToLeft || this == ReadMode.doubleRightToLeft;
}
