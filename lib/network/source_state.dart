/// 各漫画源运行期状态的读写门面。
///
/// 网络层需要读写源内设置（token、图床域名、图片质量等）与持久化，但不应
/// 直接依赖全局源注册表（后者在阶段4的状态管理中才成型）。通过此接口解耦：
/// 网络层只面向 [SourceState] 抽象，由调用方在源就绪后注入具体实现。
library source_state;

/// 哔咔源状态。
abstract class PicacgState {
  /// 登录后的 JWT，未登录为空串。
  String get token;

  /// app-channel（'1'/'2'/'3'，可由用户选择分流）。
  String get channel;

  /// 图片质量（'low' / 'medium' / 'high' / 'original'）。
  String get imageQuality;

  /// 当前生效的 API 接入域名（'go2778' 中转默认，'picacomic' 直连备用）。
  String get apiBaseUrl;

  /// 写入当前生效的接入域名（持久化）。
  void setApiBaseUrl(String url);

  /// 重新登录（用已保存的账密）。返回是否成功。
  Future<bool> reLogin();

  /// 取得登录账密（["email", "password"]）用于重登。
  List<String>? getAccount();
}

/// 禁漫源状态。
abstract class JmState {
  /// 当前生效的**接口**域名（用于 API 请求）。
  String get apiBaseUrl;

  /// 写入当前生效的**接口**域名。
  void setApiBaseUrl(String url);

  /// 当前生效的**图床**域名（用于封面与内文图 URL 拼接）。
  String get imageBaseUrl;

  /// 写入当前生效的图床域名。
  void setImageBaseUrl(String url);

  /// 用户在源选择器中选中的**接口**域名（优先于兜底轮询使用）。
  ///
  /// 可空：未选时为空串，表示走兜底 CDN 轮询。
  String get preferredDomain;

  /// 写入用户选中的接口域名（持久化）。
  void setPreferredDomain(String domain);

  /// `/setting` 返回的动态分流项（每项含 [key]、[title]）。
  ///
  /// 由 [JmNetwork.fetchSetting] 拉取并写入；express 快速通道（key=0）
  /// 在读出时由网络层补齐，故此处只保存服务端原始项。
  List<JmShunt> get shunts;

  /// 写入动态分流项（持久化）。
  void setShunts(List<JmShunt> shunts);

  /// 用户测速选中并持久化的分流 key（0 为 express 快速通道）。
  int get selectedShuntKey;

  /// 写入选中的分流 key（持久化）。
  void setSelectedShuntKey(int key);

  /// 已登录用户名。
  String? get username;

  /// 重新登录。
  Future<bool> reLogin();

  List<String>? getAccount();
}

/// 禁漫动态分流项（服务端 `/setting` 的 `app_shunts` 元素）。
class JmShunt {
  /// 分流标识：≥1 为常规分流，[jmExpressShuntKey]（0）为 express 快速通道。
  final int key;

  /// 分流展示名（如「线路一」「快速通道」）。
  final String title;

  const JmShunt({required this.key, required this.title});

  @override
  String toString() => 'JmShunt($key:$title)';
}
