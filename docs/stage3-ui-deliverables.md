# 阶段3 全套页面 UI 落地清单（2026-07-10）

> 主人要求：只设计全部页面 UI + 留功能注释，真实功能由其他 AI 集成。
> 本阶段落地 16 个页面文件 + 5 个公共组件 + 6 篇功能设计文档。

## 设计语言（沿用阶段一）

- 深墨紫黑底 `#0E0B14` / 卡片 `#1B1622` / 抬升 `#221A2B`
- 品牌渐变 藕粉 `#FF7BA9` → 紫罗兰 `#B967FF`
- 设计 token 七件套（`lib/theme/`），详情页动态取色（`palette_extractor.dart`）
- 全部深色基调，统一圆角/间距/字体层级

## 文件清单

### 公共组件（`lib/views/common/widgets/`）

| 文件 | 功能 |
|------|------|
| `empty_state.dart` | 空态/错误态统一组件（图标+标题+副文本+动作按钮）|
| `section_header.dart` | 区块标题（左标题+可选副+右动作入口）|
| `loading_grid.dart` | 骨架加载网格 |
| `comic_grid.dart` | 漫画网格通用组件（下拉刷新+上拉加载+三态）|

### Tab 框架

| 文件 | 功能 |
|------|------|
| `lib/views/main_scaffold.dart` | 4 Tab（首页/分类/收藏/我的）+ 毛玻璃底栏 |

### 首页 + 工具栏入口（`lib/views/home/`、`ranking/`、`image_search/`、`video/`）

| 文件 | 功能 | 工具栏入口 |
|------|------|-----------|
| `home/home_page.dart` | 首页：工具栏+编辑推荐横滑+最近更新网格 | — |
| `home/widgets/home_tool_bar.dart` | 6 入口横滑（最新/热门排行/影视/以图搜图/收藏库/下载）| 工具栏本体 |
| `home/widgets/featured_carousel.dart` | 大幅封面横滑轮播 | — |
| `ranking/ranking_page.dart` | 排行榜：3 Tab + 日/周/月/总筛选 | "热门排行" |
| `image_search/image_search_page.dart` | 以图搜图：上传/拍照+结果网格 | "以图搜图" |
| `video/video_page.dart` | 影视：4 Tab + 网格 | "影视" |

### 分类/收藏/我的（`lib/views/category/`、`favorites/`、`mine/`）

| 文件 | 功能 |
|------|------|
| `category/category_page.dart` | 分类：搜索框+一级 tab+分类标签网格+随机推荐 |
| `favorites/favorites_page.dart` | 收藏：多文件夹+排序+网格+空态 |
| `mine/mine_page.dart` | 我的：用户卡+统计三宫格+功能入口列表 |

### 搜索/下载/设置/登录（`lib/views/search/`、`download/`、`settings/`、`auth/`）

| 文件 | 功能 |
|------|------|
| `search/search_page.dart` | 搜索：搜索框+历史+热门词+结果网格 |
| `download/download_page.dart` | 下载：下载中/已下载 2 Tab + 任务卡+进度 |
| `settings/settings_page.dart` | 设置：源管理/阅读/外观/数据/关于分组 |
| `settings/source_settings_page.dart` | 源设置：禁漫图床测速+哔咔双源切换 |
| `settings/reader_settings_page.dart` | 阅读设置：5 模式+预加载+显示+图片质量 |
| `auth/login_page.dart` | 登录：源切换+账号密码+品牌渐变登录按钮 |

### 功能设计文档（`docs/features/`）

| 文档 | 对应 UI | 参考源 |
|------|---------|--------|
| `latest.md` | 首页"最近更新" + 排行榜"最新" | 两源 search 空 keyword |
| `ranking.md` | 排行榜页 | 禁漫 search order + 哔咔 RankingData |
| `video.md` | 影视页 | **joycomic-ios MoviesScreen**（videos 端点 + videoType）|
| `image-search.md` | 以图搜图页 | **joycomic-ios ImageSearchScreen**（SauceNAO + soutubot）|
| `search.md` | 搜索页 | 两源 searchPageData 并行 |
| `favorites.md` | 收藏页 | **joycomic-ios LibraryScreen**（favorite + folder 系列）|

## 路由表（`main.dart`）

| 路由 | 页面 |
|------|------|
| `/` | MainScaffold（4 Tab）|
| `/search/:sourceKey` | SearchPage |
| `/ranking?tab=` | RankingPage |
| `/image-search` | ImageSearchPage |
| `/video` | VideoPage |
| `/download` | DownloadPage |
| `/login?source=` | LoginPage |
| `/settings` `/settings/source` `/settings/reader` | 设置系列 |
| `/detail/:sourceKey/:comicId` | DetailPage（阶段3 阶段一）|
| `/reader` | Reader（阶段2）|
| *未匹配* | errorBuilder 占位页 |

## 功能集成约定（给集成的 AI）

每个页面文件顶部 `library` 文档注释已写明：
1. 页面结构（自顶向下的区块）
2. 功能集成说明（真实数据来自哪个 ComicSource 契约字段 / 端点）
3. 当前是 mock 还是留位

集成时替换 mock 数据为真实调用即可，UI 布局不动。
