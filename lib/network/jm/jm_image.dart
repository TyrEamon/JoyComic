/// 禁漫图片 URL 构造辅助函数。
///
/// 禁漫的封面图、章节内文图、用户头像都挂在可切换的图床域名下，
/// 由业务层选择当前 baseUrl 后，按固定路径规则拼接 URL。
library;

/// 当前生效的禁漫图床/接口 baseUrl。运行期由禁漫网络层在选域名后写入。
/// 默认指向常用图床之一，实际会在请求时被刷新。
String jmBaseUrl = 'https://cdn-msp3.jmapiproxy1.cc';

/// 默认图床（与 [jmBuiltInImgUrls] 首项对齐，避免循环 import 时使用字面量）。
const jmDefaultImageBaseUrl = 'https://cdn-msp3.jmapiproxy1.cc';

/// 归一化图床 base：空串 / 非法 host 回退到默认，避免拼出
/// `//media/photos/...` 或相对路径导致阅读器永远加载失败。
String resolveJmImageBaseUrl(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) {
    final current = jmBaseUrl.trim();
    if (current.isNotEmpty) {
      final cur = Uri.tryParse(current);
      if (cur != null &&
          (cur.scheme == 'http' || cur.scheme == 'https') &&
          cur.host.isNotEmpty) {
        return current.endsWith('/')
            ? current.substring(0, current.length - 1)
            : current;
      }
    }
    return jmDefaultImageBaseUrl;
  }
  final parsed = Uri.tryParse(value);
  if (parsed == null ||
      !(parsed.scheme == 'http' || parsed.scheme == 'https') ||
      parsed.host.isEmpty) {
    return jmDefaultImageBaseUrl;
  }
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

/// 禁漫单曲漫画封面 URL（3:4 缩略，质量足够作为列表卡片封面）。
String getJmCoverUrl(String id) =>
    '${resolveJmImageBaseUrl(jmBaseUrl)}/media/albums/${id}_3x4.jpg';

/// 禁漫章节内文图 URL。
///
/// [imageName] 章节接口返回的图片文件名；[chapterId] 章节id，用于路径定位。
String getJmImageUrl(String imageName, String chapterId) =>
    '${resolveJmImageBaseUrl(jmBaseUrl)}/media/photos/$chapterId/$imageName';

/// 按页序生成 JM 标准文件名（`00001.webp` …）。
///
/// 用于章节接口未返回 images、但已知总页数（如 album.total_photos）时，
/// 直接按 CDN 约定路径拼出可读页列表，避免未购买精品因空 images 无法阅读。
List<String> buildJmSequentialPageNames(
  int count, {
  String extension = 'webp',
}) {
  if (count <= 0) return const <String>[];
  final ext = extension.startsWith('.')
      ? extension.substring(1)
      : (extension.isEmpty ? 'webp' : extension);
  return List<String>.unmodifiable([
    for (var i = 1; i <= count; i++)
      '${i.toString().padLeft(5, '0')}.$ext',
  ]);
}

/// 禁漫用户头像 URL。
String getJmAvatarUrl(String imageName) => '$jmBaseUrl/media/users/$imageName';
