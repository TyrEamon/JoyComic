/// 历史记录契约 mixin 的最小定义。
///
/// [ComicInfoData] 与各源的详情模型混入此 mixin，以便历史/阅读进度系统
/// 用统一方式获取源标识与目标 id。完整历史 DB 在阶段4实现。
import '../network/base_comic.dart';

/// 历史类型：以源 key 构造，避免硬编码枚举扩散。
class HistoryType {
  final int value;
  const HistoryType(this.value);

  factory HistoryType.fromKey(String sourceKey) => HistoryType(sourceKey.hashCode);

  @override
  bool operator ==(Object other) =>
      other is HistoryType && other.value == value;

  @override
  int get hashCode => value;

  @override
  String toString() => value.toString();
}

mixin HistoryMixin {
  String get title;
  String? get subTitle => null;
  String? get description => null;

  HistoryType get historyType;

  String get target;
}
