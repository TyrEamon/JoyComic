/// 内置源注册入口。
///
/// 在 app 启动早期、源初始化之前调用 [registerBuiltInSources]，把哔咔与禁漫
/// 的构造器注入到 [ComicSource.builtInMap]，供 [ComicSource.init] 按启用项加载。
library;

import '../comic_source.dart';
import 'jm.dart';
import 'picacg.dart';

/// 登记所有内置源。必须在 [ComicSource.init] 之前调用。
void registerBuiltInSources() {
  ComicSource.builtInMap
    ..['picacg'] = buildPicacgSource
    ..['jm'] = buildJmSource;
}

/// 默认启用的内置源 key 列表。
const defaultEnabledSources = <String>{'picacg', 'jm'};
