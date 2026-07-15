# JoyComic 19 项回归修复设计

**日期：** 2026-07-15
**状态：** 已批准，等待书面规格复核
**范围：** 漫画详情、阅读、评论、两源登录、首页排行榜、影视与以图搜图

## 目标

- 使用统一强类型详情模型解决数据硬编码和字段误用。
- JM、哔咔继续共用一套详情 UI，不复制源专属页面。
- 完成用户列出的全部 19 项问题，不保留业务占位数据或空操作。
- 保持现有暖纸珊瑚配色；亮暗模式均满足可读性要求。
- 凭据、Token、AVS、第三方 API Key 不进入源码、日志和 Git。

## 已确认根因

1. 观看数、点赞数、评论数被格式化后塞进 `tags`，原始值丢失。
2. 无评分时固定显示 `8.0`，评价人数固定回退为 `0`。
3. JM 评论总数未从源适配层传递；哔咔总页数被误当评论总数。
4. `sendCommentFunc` 已有契约，但两个内置源都未实现。
5. JM `series=[]` 没有生成单章章节；详情图片也没有进入阅读链路。
6. 两个源都把详情 `thumbnails` 设为 `null`。
7. 分享和更多按钮回调为空。
8. 收藏按钮内部 Column 将高度撑到阅读按钮之上。
9. 页面固定留白 96px，与底栏和 SafeArea 的真实高度不一致。
10. JM 没有持久化登录响应 AVS；哔咔在 go2778 上仍发送固定官方 Host。
11. 影视页通过漫画关键词搜索伪装内容。
12. 以图搜图丢弃原始结果，并硬编码第三方 Key。

## 统一详情数据契约

`ComicInfoData` 增加明确字段：

```dart
List<String> authors;
List<String> categories;
List<String> labels;
int? viewCount;
int? likeCount;
int? commentCount;
double? sourceRating;
bool? isLiked;
bool? isFavorite;
List<ComicChapter> chapterList;
List<String>? singleChapterPages;
```

`ComicChapter` 包含 `id`、`title`、`order` 和可选 `pageCount`。旧 Map 仅用于附加元数据兼容，详情 UI 不再从中文键名读取统计。

### JM 映射

- `author` → authors
- 分类字段 → categories
- `tags` → labels
- `total_views / totalViews / views` → viewCount
- `likes` → likeCount
- `comment_total / comment / comments` → commentCount
- `series` → chapterList
- 详情 `images` → singleChapterPages

当 `series` 为空且 `series_id` 为零、空或不存在时，生成章节：

```text
id = comicId
title = 漫画标题或“第 1 话”
order = 1
```

### 哔咔映射

- `author` → authors
- `categories` 与 `tags` 分开保存
- `likesCount / totalLikes / likes` → likeCount
- `viewsCount / totalViews / views` → viewCount
- `commentsCount / totalComments / comments` → commentCount
- episode order/title → chapterList

## 简介规范化

在网络解析边界：

1. `<br>`、`</p>`、`</div>` 转换为换行。
2. 删除剩余 HTML 标签。
3. 解码常见 HTML 实体。
4. 统一换行符，清除行尾空格和过多空行。
5. 空内容由 UI 显示“暂无简介”。

简介折叠最多四行，仅在真实溢出时显示展开按钮。

## 评分算法

优先使用真实源评分；否则使用观看和点赞生成 10 分制评分。

有观看数时：

```text
engagement = clamp(likes / views, 0, 0.20) / 0.20
popularity = clamp(log(1 + views + likes × 10) / log(1 + 10,000,000), 0, 1)
rating = clamp(5.5 + 2.8 × sqrt(engagement) + 1.5 × popularity, 5.5, 9.8)
```

只有点赞数时：

```text
popularity = clamp(log(1 + likes) / log(1 + 100,000), 0, 1)
rating = clamp(5.8 + 3.0 × popularity, 5.5, 9.8)
```

两项都不可用时隐藏评分。删除“XX 人评价”，不使用评论数冒充评价人数。

## 评论契约与回复

评论加载改为：

```dart
class CommentPageData {
  List<Comment> comments;
  int page;
  int totalPages;
  int totalComments;
}
```

评论模型增加 ID、回复数、点赞数、是否点赞和子回复列表。

- JM 使用响应 `total`；普通评论调用 `comment` 端点。
- JM 回复内容发送为 `@用户名 用户输入内容`，保持顶层评论语义。
- 哔咔使用 `comments.total` 和 `comments.pages`。
- 哔咔普通评论：`POST /comics/:id/comments`。
- 哔咔回复：`POST /comments/:id`。
- 哔咔子评论：`GET /comments/:id/childrens`。
- 发送成功刷新第一页和总数；失败保留输入内容。
- 评论首次切到评论 Tab 时再加载。

## 详情页结构

使用一个 `CustomScrollView` 和 Sliver：

```text
封面与基本信息
简介
分类与标签
吸顶章节/评论 Tab
当前 Tab 内容
```

头部顺序：标题、可点击作者、评分、阅读/点赞/评论/章节统计、JM 车号、分类、标签。取消热度和评价人数。

标题使用语义化 `onImage` 颜色和稳定遮罩，保证亮暗模式可读。相关推荐放在章节 Tab 的列表之后。

搜索页支持：

```text
/search/:sourceKey?q=<keyword>
```

作者和标签执行当前源搜索；分类优先走分类查询，不能路由时回退关键词搜索。搜索框输入纯数字、`JM123` 或 `jm123` 时直接进入 JM 详情。

JM 详情显示 `JM<comicId>`，点击复制纯 ID，并提供复制反馈。

## 章节、阅读和封面

- 章节卡片进入可见区域后调用 `loadComicPages`，取第一张图为封面。
- 同一章节缓存 Future 和结果，同时最多三个请求。
- 图片继续使用源图片加载配置。
- 单章 JM 优先使用 `singleChapterPages`，否则以漫画 ID 调章节接口。
- 章节仍为空时显示具体错误，不显示“暂无章节”。
- 大量章节按区间显示；下载入口与“全部章节”分离。

## 顶部和底部操作栏

分享按钮使用 `share_plus` 分享标题、作者、来源、漫画 ID 和 JM 车号；无公开 URL 时不编造链接。

更多菜单仅包含真实操作：复制标题、复制 ID、复制 JM 车号、搜索作者、章节下载、打开源首页。

收藏和阅读按钮统一固定 52px，收藏改为横向图标加文字。底栏只应用一次 SafeArea：

```text
52px 按钮 + 上下各 8px + 系统底部 inset
```

正文底部 padding 根据真实底栏高度计算，不再固定 96px。

## 哔咔未登录处理

请求前先检查哔咔登录状态，不再显示 `latest：未登录`、`popular：未登录` 等内部错误。

统一弹窗：

```text
登录哔咔后浏览推荐与排行
稍后 / 去登录
```

覆盖首页、排行榜、详情、评论、回复和云端收藏。登录成功返回后自动刷新或继续原操作。

## JM 登录

- 解析登录响应中的 `s` 并作为 AVS 保存。
- 后续请求发送 `Cookie: AVS=<token>`。
- 启动时恢复；401 时最多重登一次。
- 登录和重登串行化，失败时清除 AVS 并触发登录引导。
- 账号密码迁移到 `flutter_secure_storage`，删除普通源数据中的明文副本。

## 哔咔登录

- 删除固定 Host，签名使用包含 Query 的完整相对路径。
- 登录请求禁止触发自动重登；普通请求 401 最多重登一次。
- 登录依次尝试用户地址、官方地址和 go2778，成功后保存实际地址和 Token，再获取档案。
- 日志屏蔽密码、Token、签名和授权头。

## 首页排行榜

首页工具栏改为：

```text
排行榜 / 影视 / 以图搜图 / 收藏库 / 下载
```

排行榜页内部保留最新、热门、评分 Tab，并使用源支持的真实排序或排行榜接口。

## 影视

替换漫画关键词搜索，接入 JM：

```text
videos / video / latest_hanime
```

分类为全部、小电影、H动漫、Cos，支持搜索、分页、刷新、封面、标签、详情和相关视频。

播放器优先播放 `video_src`；失败时使用 WebView 加载真实页面并尝试提取地址；仍失败时提供浏览器打开。播放器具备播放、暂停、进度、全屏、错误状态和资源释放。

## 以图搜图

流程：选图或拍照 → 原始 SauceNAO 结果 → 提取标题/作者 → JM/哔咔二次搜索。

展示相似度、数据库来源、缩略图、标题、作者、外部链接和内部漫画结果。

Key 来源：安全存储用户 Key → 构建时 `SAUCENAO_API_KEY` → Key 设置与 SauceNAO/soutubot 引导。源码不保存默认 Key。

Codemagic 生成 iOS 工程后写入相册和相机用途说明。错误区分权限拒绝、相机不可用、Key 无效、限流、网络失败和无结果。

## 安全和测试

账号密码、AVS、Token、第三方 Key、完整签名不得进入源码、日志或 Git。真实登录联调通过临时环境变量执行。

单元测试覆盖评分、字段兼容、简介、单章、AVS、哔咔签名与重登、评论分页/回复、章节封面缓存、JM ID、影视和 SauceNAO 解析。

Widget 测试覆盖亮色标题、无热度/评价人数、可点击元数据、Tab、评论总数/回复、等高底栏、SafeArea、工具栏、登录弹窗和首页单一排行榜入口。

最终执行：

```text
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
git diff --check
```

iOS 由 Codemagic 动态生成工程、注入权限并执行无签名构建。

## 19 项追踪

| # | 覆盖方案 |
|---|---|
| 1 | 强类型统计与评分算法 |
| 2 | 标题优先、作者点击搜索 |
| 3 | 简介规范化 |
| 4 | 章节/评论吸顶 Tab |
| 5 | 总评论数和总页数分离 |
| 6 | 两按钮固定 52px |
| 7 | 动态底部 padding |
| 8 | 单次 SafeArea |
| 9 | 哔咔真实回复、JM @回复 |
| 10 | JM 合成单章和图片优先级 |
| 11 | 阅读/点赞/分类/标签展示和搜索 |
| 12 | 章节首图懒加载 |
| 13 | 分享和真实更多菜单 |
| 14 | 统一哔咔登录引导 |
| 15 | onImage 对比度与信息重组 |
| 16 | JM 车号复制和 ID 直达 |
| 17 | JM AVS、哔咔 Host/签名/重登修复 |
| 18 | 合并排行榜入口 |
| 19 | JM 视频 API 与完整反向搜索 |

## 提交策略

实现拆分为本地提交；19 项、测试和验证全部完成后统一合并，只进行一次最终 GitHub 推送。
