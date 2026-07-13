/// 禁漫图片 URL 构造辅助函数。
///
/// 禁漫的封面图、章节内文图、用户头像都挂在可切换的图床域名下，
/// 由业务层选择当前 baseUrl 后，按固定路径规则拼接 URL。
library jm_image_url;

/// 当前生效的禁漫图床/接口 baseUrl。运行期由禁漫网络层在选域名后写入。
/// 默认指向常用图床之一，实际会在请求时被刷新。
String jmBaseUrl = 'https://cdn-msp3.jmapiproxy1.cc';

/// 禁漫单曲漫画封面 URL（3:4 缩略，质量足够作为列表卡片封面）。
String getJmCoverUrl(String id) => '$jmBaseUrl/media/albums/${id}_3x4.jpg';

/// 禁漫章节内文图 URL。
///
/// [imageName] 章节接口返回的图片文件名；[chapterId] 章节id，用于路径定位。
String getJmImageUrl(String imageName, String chapterId) =>
    '$jmBaseUrl/media/photos/$chapterId/$imageName';

/// 禁漫用户头像 URL。
String getJmAvatarUrl(String imageName) => '$jmBaseUrl/media/users/$imageName';
