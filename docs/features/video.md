# 影视功能设计

> 阶段3 功能集成参考文档。UI 已落地（影视页：全部/动画/真人/广播剧 4 Tab + 网格），
> 数据来源参考 `clone/joycomic-ios` 的 `MoviesScreen.tsx`。

## 功能定位

展示禁漫的影视化作品（小电影 / H 动漫 / Cos 等视频内容），支持分类筛选与搜索。
**此功能为禁漫专属**，哔咔无对应端点。

## 数据来源（禁漫 `videos` 端点）

参考 joycomic-ios `api/endpoints.ts`：

```ts
// 视频列表
fetchMovies({ page, videoType, searchQuery })
  → encryptedGet('videos', { page, video_type, search_query })

// 视频详情
fetchVideoDetail(vid)
  → encryptedGet('videos/' + vid)
```

### videoType 映射（参考 ios VIDEO_TABS）

| ios tab key | ios label | videoType | searchQuery |
|------------|-----------|-----------|-------------|
| `''` | 全部 | undefined | undefined |
| `movie` | 小电影 | `movie` | undefined |
| `hanime` | H 动漫 | `video` | `H動漫` |
| `cos` | Cos | `video` | `Cos` |

> H 动漫和 Cos 都走 `video` 类型，用 `searchQuery` 区分。

### joycomic 集成方式

禁漫的 `videos` 端点需在 `JmNetwork` 补方法：

```dart
// jm_network.dart 待补
Future<Res<List<JmVideoBrief>>> fetchMovies({
  required int page,
  String? videoType,
  String? searchQuery,
}) async {
  final res = await get('$baseUrl/videos?page=$page'
      '&video_type=${videoType ?? ''}'
      '&search_query=${searchQuery ?? ''}');
  // 解析 res.data['list'] → JmVideoBrief 列表
}
```

`JmVideoBrief` 模型（参考 ios `MovieItem`）：

```dart
class JmVideoBrief {
  final String id;
  final String title;
  final String cover;      // 相对路径，需拼 getImgHost()
  final String author;
  final String? type;      // movie/video
}
```

### 图片鉴权

视频封面图与禁漫漫画图同源（`getImgHost()` 图床），鉴权头复用 `imageHeaders()`。
joycomic 已在 `built_in/jm.dart` 的 `getThumbnailLoadingConfig` 返回 `imageHeaders()`，
视频封面直接复用。

## 集成点

| UI 位置 | 组件 | 调用 |
|---------|------|------|
| 首页工具栏"影视" | → push `/video` | 影视页 |
| 影视页 4 Tab | `ComicGrid` | `JmNetwork.fetchMovies(videoType/tab, searchQuery)` |

## Tab 映射

joycomic 当前影视页 4 Tab：全部 / 动画 / 真人 / 广播剧。
对齐 ios 的 4 类需调整 Tab label：

| joycomic Tab | ios 对应 | videoType | searchQuery |
|-------------|---------|-----------|-------------|
| 全部 | 全部 | `''` | `''` |
| 动画 → 改"小电影" | 小电影 | `movie` | — |
| 真人 → 改"H 动漫" | H 动漫 | `video` | `H動漫` |
| 广播剧 → 改"Cos" | Cos | `video` | `Cos` |

> ⚠️ Tab 文案需按真实禁漫分类调整。joycomic 当前 4 Tab 文案是 mock，
> 集成时替换为上表。

## 视频详情页（未实现）

点视频卡 → 视频详情页（参考 ios `fetchVideoDetail`），展示：
- 视频封面 / 标题 / 作者
- 系列章节列表（`videoSeries`）
- 相关视频（`related_videos`）
- 播放器（WebView 或原生，取决于视频格式）

joycomic 当前无视频详情页 UI，需新增。播放能力较重，可考虑阶段5 再做。

## 待定问题

- 禁漫 videos 端点返回结构需实跑核实（joycomic 阶段1 未实现该端点）。
- 视频播放器选型：WebView 内嵌 vs 原生视频包，取决于视频格式（m3u8/mp4）。
- Cos/H 动漫分类可能涉及内容合规，需按地区法规决定是否启用。
