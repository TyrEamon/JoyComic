/// 漫画基类抽象。
///
/// 所有漫画源的列表项都实现此契约，使 UI 层可以用统一方式渲染卡片，
/// 无需关心具体来自哔咔还是禁漫。
abstract class BaseComic {
  String get title;

  String get subTitle;

  String get cover;

  String get id;

  List<String> get tags;

  String get description;

  /// 是否对标签进行中文翻译（哔咔/禁漫默认开启）。
  bool get enableTagsTranslation => true;

  const BaseComic();
}

/// 源识别类型。用于历史记录、收藏、下载等本地数据的源归属判定。
///
/// 注：保留扩展性，未来新增源只需在此枚举追加。
enum ComicType {
  picacg,
  jm,
  other;

  @override
  String toString() => name;
}
