# JoyComic 用户反馈回归修复实施计划

> **执行方式：** 主代理 inline execution；禁止子代理；禁止新增或修改测试用例。

**Goal:** 修复用户报告的 11 项登录、源管理、详情、分类、阅读器与日志导出回归。

**Architecture:** 分离源启用管理与账号登录；保留双源抽象。阅读器引入统一图片请求配置并让显示与预加载共享。UI 按用户指定和  分类参考做定向修复，不做无关重构。

**Tech Stack:** Flutter、Dart、Provider、GoRouter、cached_network_image_ce、share_plus。

---

## 修复结果表

| # | 问题 | 状态 | 修改文件 | 验证结果 |
|---|---|---|---|---|
| 1 | 已登录仍进入登录页 | 待修复 | - | - |
| 2 | JM 用户资料缺失 | 待修复 | - | - |
| 3 | 我的页源管理跳登录 | 待修复 | - | - |
| 4 | 详情顶部分享按钮 | 待修复 | - | - |
| 5 | 封面与右侧文字底部对齐 | 待修复 | - | - |
| 6 | 详情统计排版与重复评分 | 待修复 | - | - |
| 7 | 分类页 cell/chip 布局 | 待修复 | - | - |
| 8 | 分类页底部被遮挡 | 待修复 | - | - |
| 9 | 设置源管理和测速混乱 | 待修复 | - | - |
| 10 | JM/哔咔阅读器黑屏 | 待修复 | - | - |
| 11 | 日志导出无反应 | 待修复 | - | - |

### Task 1：账号、登录与源管理边界

**Files:**
- Create: `lib/views/settings/source_manager_page.dart`
- Modify: `lib/main.dart`
- Modify: `lib/views/mine/mine_page.dart`
- Modify: `lib/views/settings/settings_page.dart`
- Modify: `lib/views/auth/login_page.dart`

- [ ] 新增 `/settings/sources` 路由和内置源启用选择页面。
- [ ] 我的页已登录账号卡打开账号面板，未登录才进入登录页。
- [ ] 我的页“源管理”始终进入 `/settings/sources`。
- [ ] 设置页拆分漫画源、账号、线路与域名三个分组。
- [ ] JM 与哔咔线路入口明确分开，JM 测速不再被首源逻辑隐藏。

### Task 2：JM 登录公开资料

**Files:**
- Modify: `lib/network/jm/jm_network.dart`
- Modify: `lib/comic_source/built_in/jm.dart`
- Modify: `lib/views/common/source_account_profile.dart`

- [ ] 从 JM 登录响应解析 username、uid、nickname、level、photo/avatar。
- [ ] 登录成功并完成图床选择后写入 `source.data['user']`。
- [ ] 退出登录清理资料但不影响源设置。

### Task 3：详情页布局

**Files:**
- Modify: `lib/views/detail/detail_page.dart`
- Modify: `lib/views/detail/widgets/detail_app_bar.dart`
- Modify: `lib/views/detail/widgets/info_overlay.dart`
- Modify: `lib/views/detail/widgets/detail_metadata.dart`

- [ ] 顶部删除独立分享按钮，分享移动到更多菜单。
- [ ] 封面和右侧完整文字块垂直居中。
- [ ] 统计项改为图标在左、文字在右。
- [ ] 删除下方重复评分。

### Task 4： 风格分类页与安全区

**Files:**
- Modify: `lib/views/category/category_page.dart`

- [ ] 用响应式 GridView 替换 ListTile/ActionChip。
- [ ] 哔咔显示分类 cover + 名称。
- [ ] JM 使用同尺寸图片占位 + 名称。
- [ ] 底部增加 60px 导航栏和系统安全区 padding。

### Task 5：JM/哔咔阅读器黑屏

**Files:**
- Modify: `lib/views/reader/reader.dart`
- Modify: `lib/views/reader/providers/reader_provider.dart`
- Modify: `lib/views/reader/widgets/reader_image.dart`
- Modify: `lib/views/reader/utils/image_preload_controller.dart`
- Modify: `lib/views/reader/widgets/vertical_list/vertical_list.dart`
- Modify: `lib/views/reader/widgets/horizontal_list/horizontal_list.dart`

- [ ] loader 缺失、抛异常、错误和空图片均进入可见错误态。
- [ ] 加载阶段显示进度文字，工具栏可返回。
- [ ] 解析源图片 URL、headers 和 cacheKey。
- [ ] 显示与预加载共用同一图片请求配置。
- [ ] 图片最终失败显示明确说明与重试按钮。

### Task 6：日志 TXT 导出

**Files:**
- Modify: `lib/views/settings/log_viewer_page.dart`

- [ ] 空日志点击提示。
- [ ] 增加导出 busy 状态。
- [ ] 写入 text/plain TXT 并传递分享锚点。
- [ ] 捕获并展示写入/分享异常及分享结果。

### Task 7：文档与既有验证

**Files:**
- Modify: `docs/superpowers/plans/2026-07-17-user-reported-ui-reader-regressions.md`

- [ ] 确认 `git diff -- test` 为空。
- [ ] 运行既有相关测试，不新增测试文件或测试用例。
- [ ] 运行 `dart format --output=none --set-exit-if-changed lib`。
- [ ] 运行 `flutter analyze --no-pub`。
- [ ] 运行 `flutter test --no-pub`。
- [ ] 运行 `git diff --check`。
- [ ] 更新上方 11 项结果表。
