# 以图搜图功能设计

> 阶段3 功能集成参考文档。UI 已落地（以图搜图页：上传/拍照 → 结果网格），
> 数据来源参考 `clone/joycomic-ios` 的 `ImageSearchScreen.tsx`（SauceNAO API + soutubot WebView）。

## 功能定位

上传漫画截图 / 拍照，通过反向图片搜索找到相似或同源漫画，跳转详情页。

## 技术方案（参考 joycomic-ios）

joycomic-ios 用 **SauceNAO API** 作为主搜索引擎，**soutubot WebView** 作为备选。
两源（禁漫/哔咔）均无原生以图搜图 API，故走第三方。

### SauceNAO（主）

参考 ios `doSauceNAO`：

```
POST https://saucenao.com/search.php
  ?output_type=2       // JSON
  &numres=6            // 返回 6 条
  &api_key=<API_KEY>
Body: multipart/form-data, file=<图片字节>
```

返回 `SauceResult[]`，每项含：
- `header.similarity` —— 相似度（0~100，越高越准）
- `header.thumbnail` —— 匹配结果缩略图
- `header.index_name` —— 来源索引（如 Pixiv / MangaDex）
- `data.ext_urls` —— 外部链接
- `data.title` / `data.author_name` —— 作品名 / 作者

### soutubot（备）

WebView 打开 `https://soutubot.moe/`，由用户手动上传搜索。joycomic-ios 仅提供入口，
不自动化（soutubot 无公开 API）。

## API Key 管理

参考 ios：
- 测试 key：`1f8fbe5632d20f8e025c610aef9e66c06ed39986`（ios 内置，可共用）
- 用户自定义 key：存 `shared_preferences`（key: `saucenao_api_key`）
- 设置页提供"以图搜图 API Key"入口，让用户注册 SauceNAO 免费账号获取

## joycomic 集成方式

### 新增依赖

```yaml
# pubspec.yaml 待加
image_picker: ^1.1.x    # 相册/相机选图
```

（joycomic 当前无 image_picker，阶段3 功能集成时加。纯 Flutter 包，无 native 复杂度。）

### SauceNAO 搜索服务

```dart
// lib/foundation/sauce_nao_search.dart 待新增
class SauceNaoSearch {
  static Future<List<SauceResult>> search(File image, {String? apiKey}) async {
    final dio = Dio();
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(image.path),
    });
    final res = await dio.post(
      'https://saucenao.com/search.php?output_type=2&numres=6&api_key=${apiKey ?? kTestKey}',
      data: form,
    );
    return _parse(res.data['results']);
  }
}

class SauceResult {
  final double similarity;
  final String thumbnail;
  final String source;     // index_name
  final String? title;
  final String? author;
  final List<String> extUrls;
}
```

### 结果 → 漫画匹配

SauceNAO 结果多来自 Pixiv / 外部站点，**不直接是禁漫/哔咔作品**。需二次匹配：

1. 拿 SauceNAO 的 title/author 在两源 search：
   `ComicSource.sources.forEach((s) => s.searchPageData.loadPage(title, 1, []))`
2. 找到匹配的 BaseComic → 跳详情页
3. 未匹配的 SauceNAO 结果展示外部链接（ext_urls），让用户手动打开

## 集成点

| UI 位置 | 组件 | 调用 |
|---------|------|------|
| 首页工具栏"以图搜图" | → push `/image-search` | 以图搜图页 |
| 以图搜图页选图后 | `ComicGrid` | SauceNaoSearch.search → 两源 search 二次匹配 |

## ViewModel

```dart
class ImageSearchViewModel extends ChangeNotifier {
  File? _picked;
  List<SauceResult> _sauceResults = [];
  List<ComicGridItem> _matchedComics = []; // 二次匹配结果

  Future<void> search(File image) async {
    _sauceResults = await SauceNaoSearch.search(image);
    // 并行在两源搜 title
    for (final r in _sauceResults) {
      if (r.title != null) {
        final matched = await _searchAcrossSources(r.title!);
        _matchedComics.addAll(matched);
      }
    }
    notifyListeners();
  }
}
```

## UI 补充（当前 mock 缺失项）

当前以图搜图页只显示 ComicGrid 结果。集成时应补：
- SauceNAO 结果卡（相似度 + 缩略 + 来源索引），点击展开 ext_urls
- "用 soutubot 搜索"备选入口（WebView / url_launcher 打开 soutubot.moe）
- API Key 设置入口（未配置时引导）

## 待定问题

- SauceNAO 免费额度限制（每 30 秒 6 次，每天 200 次），需提示用户。
- 二次匹配命中率取决于 SauceNAO 结果的 title 准确度，可能偏低。
- image_picker 在 iOS 需配 Info.plist 权限描述（NSPhotoLibraryUsageDescription / NSCameraUsageDescription）。
