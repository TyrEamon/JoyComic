# JoyComic 用户反馈回归修复实施计划

> **执行方式：** 主代理 inline execution；禁止子代理；禁止新增或修改测试用例。

**Goal:** 修复用户报告的 11 项登录、源管理、详情、分类、阅读器与日志导出回归。

**Architecture:** 分离源启用管理与账号登录；保留双源抽象。阅读器引入统一图片请求配置并让显示与预加载共享。UI 按用户指定和  分类参考做定向修复，不做无关重构。

**Tech Stack:** Flutter、Dart、Provider、GoRouter、cached_network_image_ce、share_plus。

---

## 修复结果表

| # | 问题 | 状态 | 修改文件 | 验证结果 |
|---|---|---|---|---|
| 1 | 已登录仍进入登录页 | 已修复 | `mine_page.dart`、`settings_page.dart`、`source_account_sheet.dart` | 已登录账号点击后打开资料/退出面板，未登录才进入登录页 |
| 2 | JM 用户资料缺失 | 已修复 | `jm_network.dart`、`jm.dart`、`mine_page.dart`、`source_account_sheet.dart` | 登录响应中的用户名、UID、昵称、等级、头像已持久化；头像加载携带源请求头 |
| 3 | 我的页源管理跳登录 | 已修复 | `mine_page.dart`、`source_manager_page.dart`、`main.dart` | “源管理”固定进入独立源启用页面，与登录状态无关 |
| 4 | 详情顶部分享按钮 | 已修复 | `detail_app_bar.dart`、`detail_page.dart` | 顶部仅保留返回与更多；分享移动到更多菜单 |
| 5 | 封面与右侧文字底部对齐 | 已修复 | `info_overlay.dart` | 封面与右侧完整标题/作者/评分块按中心线垂直对齐 |
| 6 | 详情统计排版与重复评分 | 已修复 | `detail_metadata.dart` | 统计改为图标在左、文字在右；下方重复评分已删除 |
| 7 | 分类页 cell/chip 布局 | 已修复 | `category_page.dart` | 已改为  风格响应式图片+名称网格，哔咔使用分类封面，JM 使用同尺寸占位 |
| 8 | 分类页底部被遮挡 | 已修复 | `category_page.dart` | 底部 padding 包含 60px TabBar、系统安全区和额外间距 |
| 9 | 设置源管理和测速混乱 | 已修复 | `settings_page.dart`、`source_manager_page.dart`、`main.dart` | 漫画源、账号、线路与域名已分组；JM 图床/API 测速与哔咔接入域名入口独立 |
| 10 | JM/哔咔阅读器黑屏 | 已修复 | `reader.dart`、`reader_provider.dart`、`reader_image_provider.dart`、预加载与横竖列表、JM/哔咔网络层 | JM 原始图片下载后按指纹规则重组；图床支持 fallback；哔咔媒体优先使用 go2778；显示和预加载共用最终图片 provider |
| 11 | 日志导出无反应 | 已修复 | `log_viewer_page.dart` | 空日志、忙状态、TXT MIME、iPad 分享锚点、成功/取消/失败反馈均已实现 |

### Task 1：账号、登录与源管理边界

**Files:**
- Create: `lib/views/settings/source_manager_page.dart`
- Modify: `lib/main.dart`
- Modify: `lib/views/mine/mine_page.dart`
- Modify: `lib/views/settings/settings_page.dart`
- Create: `lib/views/common/source_account_sheet.dart`

- [x] 新增 `/settings/sources` 路由和内置源启用选择页面。
- [x] 我的页已登录账号卡打开账号面板，未登录才进入登录页。
- [x] 我的页“源管理”始终进入 `/settings/sources`。
- [x] 设置页拆分漫画源、账号、线路与域名三个分组。
- [x] JM 与哔咔线路入口明确分开，JM 测速不再被首源逻辑隐藏。

### Task 2：JM 登录公开资料

**Files:**
- Modify: `lib/network/jm/jm_network.dart`
- Modify: `lib/comic_source/built_in/jm.dart`
- Create: `lib/views/common/source_account_sheet.dart`

- [x] 从 JM 登录响应解析 username、uid、nickname、level、photo/avatar。
- [x] 登录成功并完成图床选择后写入 `source.data['user']`。
- [x] 退出登录清理资料但不影响源设置。

### Task 3：详情页布局

**Files:**
- Modify: `lib/views/detail/detail_page.dart`
- Modify: `lib/views/detail/widgets/detail_app_bar.dart`
- Modify: `lib/views/detail/widgets/info_overlay.dart`
- Modify: `lib/views/detail/widgets/detail_metadata.dart`

- [x] 顶部删除独立分享按钮，分享移动到更多菜单。
- [x] 封面和右侧完整文字块垂直居中。
- [x] 统计项改为图标在左、文字在右。
- [x] 删除下方重复评分。

### Task 4： 风格分类页与安全区

**Files:**
- Modify: `lib/views/category/category_page.dart`

- [x] 用响应式 GridView 替换 ListTile/ActionChip。
- [x] 哔咔显示分类 cover + 名称。
- [x] JM 使用同尺寸图片占位 + 名称。
- [x] 底部增加 60px 导航栏和系统安全区 padding。

### Task 5：JM/哔咔阅读器黑屏

**Files:**
- Modify: `lib/views/reader/reader.dart`
- Modify: `lib/views/reader/providers/reader_provider.dart`
- Modify: `lib/views/reader/widgets/reader_image.dart`
- Modify: `lib/views/reader/utils/image_preload_controller.dart`
- Modify: `lib/views/reader/widgets/vertical_list/vertical_list.dart`
- Modify: `lib/views/reader/widgets/horizontal_list/horizontal_list.dart`

- [x] loader 缺失、抛异常、错误和空图片均进入可见错误态。
- [x] 加载阶段显示进度文字，工具栏可返回。
- [x] 解析源图片 URL、headers 和 cacheKey。
- [x] 显示与预加载共用同一图片请求配置。
- [x] 图片最终失败显示明确说明与重试按钮。

### Task 6：日志 TXT 导出

**Files:**
- Modify: `lib/views/settings/log_viewer_page.dart`

- [x] 空日志点击提示。
- [x] 增加导出 busy 状态。
- [x] 写入 text/plain TXT 并传递分享锚点。
- [x] 捕获并展示写入/分享异常及分享结果。

### Task 7：文档与既有验证

**Files:**
- Modify: `docs/superpowers/plans/2026-07-17-user-reported-ui-reader-regressions.md`

- [x] 确认 `git diff -- test` 为空。
- [x] 运行既有相关测试，不新增测试文件或测试用例。
- [x] 运行 `dart format --output=none --set-exit-if-changed lib`。
- [x] 运行 `flutter analyze --no-pub`。
- [x] 运行 `flutter test --no-pub`。
- [x] 运行 `git diff --check`。
- [x] 更新上方 11 项结果表。

## 验证记录

- 未新增或修改任何测试文件：`git diff -- test` 输出为空。
- 格式化检查：`dart format --output=none --set-exit-if-changed lib`，127 个文件、0 个需修改。
- 静态分析：`flutter analyze --no-pub`，`No issues found`。
- 本次修复相关的现有测试：131 项全部通过。
- 全量现有测试：397 项通过、5 项失败。失败项均是旧 UI 断言与本次用户明确要求冲突，按约束未修改测试、也未恢复旧 UI：
  1. `detail_tabs_test.dart` 仍要求顶部独立分享图标；新需求要求删除该按钮。
  2. `category_page_test.dart` 两项仍按 `ListView`/旧 cell 布局操作；新需求要求图片+名称网格。
  3. `category_page_test.dart` 仍要求子分类 cell 箭头；新需求要求统一图片+名称网格。
  4. `navigation_smoke_test.dart` 仍查找旧文案“源管理 / 登录”；新需求要求源管理与登录分离。
- `git diff --check` 通过。

## 补充修复：登录后首页自动刷新

- 新增源账号状态通知器。
- 登录或退出成功后通知已挂载的首页自动重新加载。
- 首页保留在 `IndexedStack` 中时无需用户手动下拉刷新，哔咔内容会在登录完成后自动出现。
- 不重建主 Tab，不丢失分类、收藏和其他页面状态。

## 补充修复：双源真实图片协议（方案 B）

- 新增源感知阅读图片 provider，统一负责 headers、备用 URL、原始字节下载、源专属转换和 Flutter 解码。
- JM 在线阅读复用现有 `JmRecombine`：按 `episodeId + 图片文件名` 计算分段数，在 Isolate 中逆序重组后再解码显示。
- JM 显示端和预加载端共用同一 provider/cacheKey；首选图床失败时依次尝试内置图床候选。
- JM 默认图床调整为已验证可达的 `cdn-msp3.jmapiproxy1.cc`；测速改为请求真实封面，不再用返回 404 的 `/favicon.ico`。
- 哔咔列表、详情、分类、头像和章节图统一将 `picacomic` 媒体 host 转换为 `go2778`，阅读器保留原直连 host 作为 fallback。
- 未新增或修改测试文件。针对阅读/JM/哔咔的 38 项现有测试全部通过；`flutter analyze --no-pub` 为 `No issues found`。
- 全量现有测试仍为 397 项通过、5 项旧 UI 断言失败，失败集合与上方既有记录一致，本轮按约束未修改测试。
