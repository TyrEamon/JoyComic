# 登录后首页自动刷新 Implementation Plan

> **For agentic workers:** 使用主代理 inline execution；禁止子代理；禁止新增或修改测试用例。

**Goal:** 登录或退出漫画源账号后自动刷新已挂载的首页内容。

**Architecture:** 使用独立的 `SourceSessionNotifier` 解耦认证页面与首页。认证状态变化发事件，首页监听事件并复用现有 `_loadHome`，不重建主框架。

**Tech Stack:** Flutter、Dart、ChangeNotifier、GoRouter。

---

### Task 1：账号状态通知器

**Files:**
- Create: `lib/foundation/source_session_notifier.dart`

- [x] 新增单例通知器，记录最近变化的 source key，并允许重复 source key 继续触发通知。

### Task 2：登录与退出事件

**Files:**
- Modify: `lib/views/auth/login_page.dart`
- Modify: `lib/views/common/source_account_sheet.dart`

- [x] 登录成功后、路由返回前发送状态变化事件。
- [x] 退出登录成功后发送状态变化事件。

### Task 3：首页自动刷新

**Files:**
- Modify: `lib/views/home/home_page.dart`

- [x] 首页订阅和释放通知器。
- [x] 收到事件后复用 `_loadHome`。
- [x] 移除首页登录提示的重复刷新回调。

### Task 4：既有验证

- [x] 确认 `git diff -- test` 为空。
- [x] 运行 `dart format --output=none --set-exit-if-changed lib`。
- [x] 运行 `flutter analyze --no-pub`。
- [x] 运行现有 `home_content_test.dart`、认证和导航测试。
- [x] 运行 `git diff --check`。

## 验证结果

- 现有首页、认证、我的页和主题生命周期测试：68 项全部通过。
- 现有导航冒烟测试：5 项通过、1 项旧文案断言失败；失败项仍查找“源管理 / 登录”，与已批准的源管理/登录分离需求冲突。
- 未新增或修改测试文件。
- `flutter analyze --no-pub`：No issues found。
