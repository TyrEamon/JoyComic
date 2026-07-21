# 阶段3 功能集成交接文档

> 给负责集成真实功能的 AI（即阶段2阅读器的开发者）。
> 阶段2 阅读器是你做的，现在继续阶段3 未完成的部分：UI 已全部落地（mock 数据），
> 你的任务是把 mock 换成真实功能调用。

## 1. 先读这三份文件接上下文

```
CONTEXT.md — 关键技术决策与约束（必读，含两源加密命脉、Rust 不引入等红线）
PROGRESS.md — 进度全貌（阶段1~3 已落地清单；阶段3 UI 已由另一个会话做好）
docs/stage3-ui-deliverables.md — 阶段3 全套页面文件清单 + 路由表 + 集成约定
```

## 2. 项目现状一句话

纯 Dart/Flutter iOS 漫画阅读器，聚合**禁漫 + 哔咔**双源。
- 阶段1：网络层 + 加密命脉 ✅
- 阶段2：阅读器（5 模式/预加载/缩放）✅ **← 你做的**
- 阶段3：**UI 全部落地 ✅（mock 数据），真实功能集成待完成 ← 你现在继续的部分**

阶段3 的 UI 由另一个会话基于你阶段2 的成果设计完成（沿用设计 token、详情页动态取色
等），阅读器代码你熟悉，接手无障碍。

## 3. 你的任务：继续阶段3 未完成的部分——把 mock 换成真实调用

### 集成约定（重要）

- **每个页面文件顶部 `library` 文档注释**已写明：①页面结构 ②功能集成说明（真实数据来自哪个 `ComicSource` 契约字段/端点）③当前 mock/留位标记。**照着注释替换 mock 数据为真实调用，UI 布局不要动。**
- `docs/features/` 6 篇文档详述每个功能的数据来源、端点签名、ViewModel 契约、待定问题。

### 功能 → 文档 → 页面 对照

| 功能 | 设计文档 | UI 页面 |
|------|---------|---------|
| 最新（最近更新）| `docs/features/latest.md` | 首页"最近更新"+排行榜"最新"Tab |
| 热门排行 | `docs/features/ranking.md` | `ranking/ranking_page.dart` |
| 影视 | `docs/features/video.md` | `video/video_page.dart` |
| 以图搜图 | `docs/features/image-search.md` | `image_search/image_search_page.dart` |
| 搜索 | `docs/features/search.md` | `search/search_page.dart` |
| 收藏库 | `docs/features/favorites.md` | `favorites/favorites_page.dart` |
| 详情页 | 阶段一已部分接真实源 | `detail/detail_page.dart` |
| 阅读器 | 阶段二已完成 | `reader/` |

## 4. 两源契约补全现状

| 契约字段 | 禁漫 jm | 哔咔 picacg | 备注 |
|---------|--------|-----------|------|
| `account.login` | ✅ | ✅ | 登录链路通 |
| `loadComicInfo` | ✅ | ✅ | 详情页能跑（已映射→ComicInfoData）|
| `loadComicPages` | ✅ | ✅ | 阅读器图片源 |
| `searchPageData` | ✅ | ✅ | 搜索/最新/排行可接 |
| `getThumbnailLoadingConfig` | ✅ imageHeaders | ✅ null | 封面鉴权头 |
| `getImageLoadingConfig` | ✅ | ✅ null | 内文图鉴权头 |
| `categoryData` / `categoryComicsData` | ❌ 待补 | ❌ 待补 | 分类页需此 |
| `favoriteData` | ❌ 待补 | ❌ 待补 | 收藏页需此 |
| `commentsLoader` / `sendCommentFunc` | ❌ 待补 | ❌ 待补 | 评论功能 |
| `explorePages` | ❌ 待补 | ❌ 待补 | 首页编辑推荐 |

> 网络层方法（`JmNetwork` / `PicacgNetwork`）大部分已实现，只是没接到
> `ComicSource.named(...)` 契约字段上。补全 = 在 `built_in/jm.dart` /
> `built_in/picacg.dart` 的 `ComicSource.named(...)` 里加对应字段 + 写映射函数。

## 5. 关键约束（红线，不可违反）

来自 `CONTEXT.md` / `CLAUDE.md`，你阶段2 已遵守，阶段3 继续：

1. **纯 Dart，不引入 Rust。** 离线归档用 `archive`+`pdf` 纯 Dart 包。
2. **命脉加密逻辑逐字保留**：哔咔 HMAC-SHA256 签名、禁漫 MD5 token + AES-ECB 解密、
   禁漫图片分段重组（`jm_image_recombine.dart`，你阶段2 已对接）。**不要改这些算法。**
3. **依赖锁版本勿升 major**：dio 5.7 / pointycastle 3.9.1 / image 4.3 /
   cached_network_image_ce 4.9 / go_router 16 / provider 6.1.5 等（见 `pubspec.yaml`）。
4. **注释中性**：不写外部仓库名、作者名或溯源表述。仅保留
   `picacomic.com`/`jmcomic1~4.cc` 等必需 API 域名。
5. **Windows 开发机无法编译 iOS**，本机无 dart 未能实跑 `dart analyze`，
   靠静态审查 + 云端 macOS CI 首次 build 验证。

## 6. 推荐集成顺序

1. **登录页**接真实登录（`source.account.login`）→ 验证两源 token 持久化
2. **搜索页**接真实搜索（`searchPageData.loadPage`）→ 禁漫免登录可先验证
3. **分类页**：补 `categoryData`/`categoryComicsData` 契约 → 分类标签 + 分类结果
4. **收藏页**：补 `favoriteData` 契约 → 文件夹 + 收藏列表
5. **首页编辑推荐**：补 `explorePages` 契约 → 推荐数据
6. **排行榜**：禁漫用 search order，哔咔补 `RankingData`
7. **影视**：禁漫补 `videos` 端点（参考 `video.md` + joycomic-ios）
8. **以图搜图**：加 `image_picker` 依赖 + SauceNAO 服务（参考 `image-search.md`）
9. **详情页评论**：补 `commentsLoader` 契约
10. **下载管理**：阶段4 sqlite3 + Isolate 限流（参考 `download_page.dart` 顶部注释）

## 7. 验证方式

```shell
flutter pub get
flutter analyze # 静态检查
flutter run # 真机/模拟器
flutter test test/crypto_logic_test.dart # 加密命脉单测
```

云端 CI（阶段5）：GitHub Actions `macos-latest` 出 IPA。

## 8. 已知未闭合点

- 本机无 dart，阶段3 全靠人工静态审查，可能有编译细节待 CI 首跑暴露。
- **禁漫阅读器图片重组**：详情页点"开始阅读"后，禁漫图是否经
  `jm_image_recombine` 重组再渲染，需在 `reader_image.dart` 核实/补全
  （你阶段2 移植阅读器时已知此点，CONTEXT.md §阅读器看图链路有详述）。
- 哔咔 `favoriteData`/`categoryComicsData` 网络层方法存在性需核实（部分可能 原版才有）。
- 阶段3 UI 是另一个会话做的，若发现某页面布局与你阶段2 的阅读器衔接不顺（如详情页→阅读器
 ComicState 透传），以你的阶段2 实现为准调整 UI 侧调用即可。
