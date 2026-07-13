import 'package:flutter/foundation.dart';

/// 通用网络结果封装。
///
/// 设计要点：
/// - [errorMessage] 非 null 即代表出错，[error] / [success] 据此判断。
/// - [data] 在无错误时才可安全访问；[dataOrNull] 在出错时返回 null。
/// - [subData] 用于承载分页元信息（如 maxPage）等附加数据，约定俗成。
@immutable
class Res<T> {
  final String? errorMessage;

  String get errorMessageWithoutNull => errorMessage ?? "Unknown Error";

  final T? _data;

  bool get error => errorMessage != null;

  bool get success => !error;

  /// 无错误时调用，否则抛出携带错误信息的异常。
  T get data => _data ?? (throw Exception(errorMessage));

  T? get dataOrNull => _data;

  final dynamic subData;

  @override
  String toString() => _data.toString();

  const Res(this._data, {this.errorMessage, this.subData});

  const Res.error(String err)
      : _data = null,
        subData = null,
        errorMessage = err;

  /// 由另一个 [Res] 的错误构造，省去重复取错误信息。
  Res.fromErrorRes(Res another, {this.subData})
      : _data = null,
        errorMessage = another.errorMessageWithoutNull;
}
