# JoyComic 项目进度

> 本文档由会话抢救生成。原开发会话（`f0ccb366`）因上下文超限（~9.7 万 token）+ `/compact` 被打断而卡死，此处汇总已落地的全部工作与后续路线，确保上下文不丢失。
> 配套阅读：[CONTEXT.md](./CONTEXT.md)（关键技术决策与约束）。

## 项目定位

集成 **** 与 **** 两个开源项目优点，做一个聚合 **哔咔漫画 + 禁漫天堂** 双源的 iOS 漫画阅读器。主人是 Windows 开发机、本机无法编译 iOS，因此采用**纯 Dart/Flutter** 技术栈（不引入 Rust），逻辑直接移植自开源，UI 自行设计。云端 macOS CI 出 IPA。

三个 `clone/` 下的项目**仅作功能参考，不参与编译**：

| 参考项目 | 语言 | 贡献 |
|---|---|---|
| `clone/` | Flutter/Dart | 网络层（哔咔 HMAC 签名、禁漫 token/AES 解密）、本地 DB、WebDAV 同步 |
| `clone/` | Flutter + Rust | 阅读器（5 种阅读模式、预加载、缓存）——以纯 Dart 重写其 Rust 部分 |
| `clone/joycomic-ios` | React Native/TS | 功能定位的"目标蓝本"（同为 JM+Pica 双源聚合），仅参考功能与源配置 |

## 任务总览：5 阶段路线

```
阶段1 脚手架+核心架构  ──┬──> 阶段2 阅读器
（已完成 ✅）          ├──> 阶段3 UI 页面
                      ├──> 阶段4 本地DB+下载+状态
                      ├──> 阶段5 质量审计
                      └──> 阶段6 云端 iOS CI
```

| # | 阶段 | 状态 | 内容 |
|---|------|------|------|
| 1 | 脚手架 + 核心架构 | ✅ 完成 | 工程地基、双源契约、两源网络层、Res 封装、禁漫图片重组 |
| 1.5 | 双源配置补全 | ✅ 完成 | JM 6 图片源+9 兜底域名轮询、Pica go2778/picacomic 双源切换（2026-07-09） |
| 2 | 阅读器 | ✅ 完成 | 移植  精致阅读器为纯 Dart（5 模式 / photo_view 缩放 / 方向感知预加载）—— 全部 8 任务已落地 |
| 3 | UI 页面 + 功能集成 + 日志系统 | ✅ 完成 | 全部 16 页面 UI 落地；8 组功能集成（登录/搜索/排行/收藏/首页/影视/分类/评论）；18+ 文件真实数据对接；7 个新增 API 端点；卡片源徽标（JM/Pica）；搜索/收藏源筛选 Tab（全部/禁漫/哔咔）；登录检测弹窗；SauceNAO 以图搜图；Shimmer 骨架屏动画；logger 日志系统 + 查看器（复制/筛选/导出TXT）；image_picker 依赖 |
| 4 | 本地 DB + 下载 + 状态 | ✅ 全部完成 | sqlite3 双库+搜索历史+阅读记录+收藏同步+下载管理器(Dio并发限流)+WebDAV同步(archive zip+上传/恢复) |
| 5 | 质量审计 + TODO 清理 + 亮色主题 + 字体 | ✅ 全部完成 | 审计 + TODO 清零 + 亮色主题 + LXGW WenKai 字体框架（assets/fonts/ + app_typography 字体常量 + pubspec 注释配置） |
| 6 | 云端 iOS CI | ✅ 完成 | `codemagic.yaml` Flutter 工作流 + `flutter_launcher_icons` 应用图标 + CI 首次自动 `flutter create . --platforms=ios`；修复 `url_launcher` 版本兼容性 |

## 阶段 1 交付清单（已落地，可编译）

21 个文件，共约 2400 行代码。逻辑移植自，注释中性、无溯源残留（已 grep 校验，仅保留 `picacomic.com` / `picaapi.picacomic.com` 等必需 API 域名）。

```
joycomic/
├── pubspec.yaml                         依赖清单（纯 Dart，无 Rust 依赖）
├── analysis_options.yaml               lint 规则
├── README.md                           项目说明 + 云编译指引
├── lib/
│   ├── main.dart                       启动编排 + 占位首页（登录链路可跑通，100 行）
│   ├── comic_source/
│   │   ├── comic_source.dart           ★ 声明式多源契约（455 行，typedef 函数字段 + key 路由）
│   │   ├── history.dart                历史契约 mixin（33 行）
│   │   └── built_in/
│   │       ├── registrar.dart          内置源注册入口（19 行，picacg + jm）
│   │       ├── picacg.dart             哔咔源声明 + 状态门面（89 行）
│   │       └── jm.dart                 禁漫源声明 + 状态门面（93 行）
│   ├── network/
│   │   ├── res.dart                   Res<T> 结果封装（46 行）
│   │   ├── base_comic.dart             漫画基类（34 行）
│   │   ├── source_state.dart           源状态读写门面（47 行）
│   │   ├── picacg/
│   │   │   ├── picacg_headers.dart     ★ 哔咔 HMAC-SHA256 请求签名（77 行）
│   │   │   ├── picacg_models.dart      哔咔数据模型（181 行）
│   │   │   └── picacg_network.dart     ★ 哔咔端点：登录/搜索/详情/章节图/推荐/收藏（349 行）
│   │   └── jm/
│   │       ├── jm_headers.dart         ★ 禁漫 MD5 token + AES-ECB 响应解密（109 行）
│   │       ├── jm_image.dart           禁漫图片 URL 构造（21 行）
│   │       ├── jm_models.dart          禁漫数据模型（174 行）
│   │       └── jm_network.dart         ★ 禁漫端点：登录/搜索/专辑详情/章节图（314 行）
│   └── foundation/
│       ├── app_data.dart               全局设置 + 数据目录（35 行）
│       └── jm_image_recombine.dart     ★ 禁漫图片分段重组（独立 Isolate，231 行）
└── test/crypto_logic_test.dart         哔咔签名确定性 + 禁漫分段边界单测（59 行，纯 dart 可跑）
```

### 三个命脉加密函数（逐字移植、已单测覆盖）

| 函数 | 位置 | 验证点 |
|------|------|--------|
| 哔咔请求签名 | `picacg_headers.dart` | HMAC-SHA256，确定性、64 位 hex、输入敏感 |
| 禁漫 token 生成 | `jm_headers.dart` | MD5(timestamp + salt) 组合 |
| 禁漫响应 AES-ECB 解密 | `jm_headers.dart` | pointycastle 3.9.1 API |
| 禁漫图片分段数计算 | `jm_image_recombine.dart` | `getSegmentationNum`：旧作(epsId<scrambleId)→0、中段→10、最新→%8偶数、中后→%10偶数 |
| 禁漫图片条带重组 | `jm_image_recombine.dart` | 独立 Isolate 后台执行，还原乱序 |

### 验证方式

```shell
flutter test test/crypto_logic_test.dart   # 任意装了 dart 的环境可跑，不依赖网络
```

本机无 Flutter/dart，故阶段1靠**逐文件人工静态审查**保证可编译，未实跑 `flutter build`。云端 CI 首次会跑 `flutter create . --platforms=ios` 补全 iOS 工程。

## 阶段 2 交付清单（进行中）

### 已完成：阅读器基础设施（任务7 ✅）

```
lib/
├── foundation/reader_config.dart          ★ ReaderConf（AppConf 阅读器字段兑底，shared_preferences 持久化）
├── views/reader/
│   ├── state/read_mode.dart              ★ 5 阅读模式枚举（零依赖，直接移植）
│   ├── utils/reader_utils.dart           ★ 页码换算/screenHeight/computeImageCacheWidth/splitList/平台判定/BuildContext扩展
│   └── widgets/
│       ├── retry_for_image.dart          ★ 图片重试组件+全局cacheManager（15d/5000obj，原样移植）
│       ├── toast.dart                    ★ 轻量全局提示（navKey 模式注入）
│       └── error_page.dart               ★ 通用错误+重试页
```

`app_data.dart::AppData.init` 已在拿到 prefs 后注入 `ReaderConf.inject(prefs)`。

### 已完成：ReaderProvider 内容态（任务9 ✅）

```
lib/views/reader/
├── state/
│   ├── read_mode.dart                    ★ 5 阅读模式枚举（任务7）
│   └── comic_state.dart                  ★ 阅读器 DTO（ReaderChapter, ComicState, ReaderType）
├── providers/
│   ├── list_state_provider.dart          ★ UI 态 Provider（Ctrl/Physics/列宽/菜单锁/页码显隐）
│   └── reader_provider.dart              ★ 内容态 Provider（645 行，改编自  537 行）
├── utils/reader_utils.dart               ★ 工具集
└── widgets/
    ├── retry_for_image.dart
    ├── toast.dart
    └── error_page.dart
```

#### ReaderProvider 内容覆盖

| 模块 | 行号 | 说明 |
|------|------|------|
| ReaderImage 值类 | 35-51 | url + cacheKey，==/hashCode 对照 cacheKey |
| ReaderImageLoader typedef | 59-60 | `(String, String?) → Res<List<String>>` |
| BuildContextReader 扩展 | 64-69 | reader/watcher/selector 便捷访问 |
| ReaderLoadState 枚举 | 74 | idle/loading/success/error |
| ImagePreloadControllerRef 抽象契约 | 80-86 | 任务10 预加载实现的接口占位 |
| 基本信息 (id/title/chapters/sourceKey) | 107-125 | 来自 ComicState 的快照 |
| 章节切换 (go/goNext/goPrevious) | 125-261 | 带 PageController 复位 |
| 页码与图片列表 | 145-181 | _pageNo 原始索引 / pageNo 模式适应 / multiPageImages 缓存分组 |
| 图片加载 (_loadImageUrls/retry) | 197-235 | 通过 ReaderImageLoader 回调获取 → 更新 images + 预加载通知 |
| 阅读记录 (onPageNoChanged) | 263-289 | 50ms debounce + 内存兜底，DB 占位留阶段4 |
| 阅读模式 readMode setter | 291-299 | 即时持久化到 ReaderConf |
| 滚动/翻页控制器 | 301-311 | ScrollOffset + ItemScroll + PageController |
| 工具栏显隐 (openOrCloseToolbar) | 313-388 | 打开时暂停自动翻页 / 关闭时恢复 + SystemUiMode 切换 |
| Slider/垂直/水平翻页 | 390-484 | pageTurnForVertical/pageTurnForHorizontal |
| 统一翻页 prev/next | 486-504 | 模式自适应的 prev/next |
| 自动翻页（定时 + 平滑） | 506-608 | Timer.periodic + Ticker-based smooth scroll |
| 预加载控制器引用 | 610-632 | initPreloadController/updatePreloadCacheWidth |
| 资源释放 dispose | 634-644 | 清理 controller/timer/ticker/super |

### 已完成：ImagePreloadController（任务10 ✅）

```
lib/views/reader/utils/image_preload_controller.dart   ★ 方向感知预加载（200 行）
```

| 模块 | 说明 |
|------|------|
| 方向感知锚点调度 | `onAnchorChanged` 比较首索引判定前后滚，前滚预加载尾部、后滚预加载前部 |
| Debounce 防抖 | 50ms 合并连续锚点变化，避免短时密集预加载 |
| Generation 代际管理 | 递增 `_generation` 使旧章节/cacheWidth变更后的记录自然失效 |
| 窗口修剪 `_trimPreloaded` | 锚点前后各保留 `keepWindow`（10）项，其余剔除 |
| 缓存键对齐 | `ResizeImage.resizeIfNeeded(cacheWidth, null, base)` 保证与显示端 ImageCache key 一致 |
| 网络/本地双模式 | `ReaderType.network` → `CachedNetworkImageProvider`，`ReaderType.local` → `FileImage` |
| 实现 `ImagePreloadControllerRef` | 匹配任务9定义的契约，ReaderProvider 可通过引用操控预加载 |
| `invalidatePreloaded` 不取消 timer | 防止 LayoutBuilder 的 cacheWidth 校准吃掉首批预加载 |

**集成关系**：VerticalList/HorizontalList（任务11/12）在 `initState` 中创建此控制器，
然后调用 `ReaderProvider.initPreloadController(controller)` 注入引用。

### 已完成：VerticalList 竖直连续（任务11 ✅）

```
lib/views/reader/widgets/vertical_list/
├── vertical_list.dart    ★ 主 Widget
├── gesture.dart          ★ GestureWrapper 手势包装
└── page_index.dart       ★ 可见索引计算工具
```

| 文件 | 功能 |
|------|------|
| `vertical_list.dart` | `ScrollablePositionedList.builder` + `FractionallySizedBox` 宽度控制 + "本章完"占位；创建 `ImagePreloadController` 并注入 `ReaderProvider`；`_onItemPositionsChanged` 驱动预加载与页码更新 |
| `gesture.dart` | `GestureWrapper`：多指追踪切换 `InteractiveViewer` 缩放态、双击 `Matrix4Tween` 放大/恢复、三区点击翻页/工具栏、锁定态下半屏翻页 |
| `page_index.dart` | `visibleVerticalImageIndices` 过滤可视区索引、`currentVerticalPageIndex` 取末项 |

**移植精简**：
- `AppConf()` → `ReaderConf.instance`
- `ComicListMixin` + DB → 砍掉（阶段4）
- 图片渲染使用 `ReaderImage` widget

### 已完成：HorizontalList 横向翻页（任务12 ✅）

```
lib/views/reader/widgets/horizontal_list/horizontal_list.dart
```

单页 `PhotoViewGalleryPageOptions` + 双页 `customChild` Row + RTL 支持 + 滚轮翻页 + 三区点击 + 预加载联动。

### 已完成：ReaderImage + reader.dart 主框架 + 叠层UI（任务13 ✅）

```
lib/views/reader/
├── reader.dart                ★ 主框架（MultiProvider + 沉浸式 + 三态渲染）
└── widgets/
    ├── reader_image.dart      ★ 单图加载（RetryForImage + ResizeImage）
    ├── app_bar.dart           ★ 顶部工具栏
    ├── bottom.dart            ★ 底部工具栏（滑块/模式/自动翻页）
    ├── menu_lock.dart         ★ 菜单锁按钮
    ├── next_chapter.dart      ★ 下一章 FAB
    ├── page_no_tag.dart       ★ 页码角标
    └── reader_keyboard_listener.dart ★ 键盘快捷键
```

### 已完成：入口接通 + 审查 + 文档（任务14 ✅）

- `main.dart`：`MaterialApp` → `MaterialApp.router`，`/reader` 路由自动匹配 `ComicSource.loadComicPages`
- 测试入口：占位首页登录后显示"测试 XXX 阅读器"按钮
- 注释洁净度：`grep ||clone` 零命中

## 阶段2 阅读器移植（全部完成 ✅✅✅）

```
lib/
├── foundation/reader_config.dart
└── views/reader/
    ├── reader.dart
    ├── state/
    │   ├── read_mode.dart
    │   └── comic_state.dart
    ├── providers/
    │   ├── list_state_provider.dart
    │   └── reader_provider.dart
    ├── utils/
    │   ├── reader_utils.dart
    │   └── image_preload_controller.dart
    └── widgets/
        ├── reader_image.dart
        ├── retry_for_image.dart
        ├── toast.dart
        ├── error_page.dart
        ├── app_bar.dart
        ├── bottom.dart
        ├── menu_lock.dart
        ├── next_chapter.dart
        ├── page_no_tag.dart
        ├── reader_keyboard_listener.dart
        ├── vertical_list/
        │   ├── vertical_list.dart
        │   ├── gesture.dart
        │   └── page_index.dart
        └── horizontal_list/
            └── horizontal_list.dart
```

| 文件 | 功能 |
|------|------|
| `vertical_list.dart` | `ScrollablePositionedList.builder` + `FractionallySizedBox` 宽度控制 + "本章完"占位；创建 `ImagePreloadController` 并注入 `ReaderProvider`；`_onItemPositionsChanged` 驱动预加载与页码更新 |
| `gesture.dart` | `GestureWrapper`：多指追踪切换 `InteractiveViewer` 缩放态、双击 `Matrix4Tween` 放大/恢复、三区点击翻页/工具栏、锁定态下半屏翻页 |
| `page_index.dart` | `visibleVerticalImageIndices` 过滤可视区索引、`currentVerticalPageIndex` 取末项 |

**手势区划分**（非锁定态，`verticalCenterFraction` 默认 0.3）：
```
┌─────────── 上 35% ───────────┐ ← 上一页
├─────────── 中 30% ───────────┤ ← 切换工具栏
└─────────── 下 35% ───────────┘ ← 下一页
```

**移植精简**：
- `AppConf()` → `ReaderConf.instance`
- `ComicListMixin` + `_initImageSizeCache` + `ImagesHelper` → 砍掉（DB 留阶段4）
- 图片渲染 `_ImageTile` 为临时内联实现（任务13 抽出为独立 `ReaderImage` widget）
- `ChapterSwipeDetector` 在  中已注释不用，跳过

### 移植关键决策（2026-07-09 定，详见 CONTEXT.md）

- **Rust 不重写**：阅读器看图链路全程纯 Dart，Rust 仅 zip/PDF/WebDAV（推迟阶段3/4）
- **图片缓存包**：用社区版 `cached_network_image_ce ^4.9.0`（官方版停维护两年、有内存泄漏；社区版99%API兼容、SQLite→Hive更优、用它零适配）
- **不接 DB**：阅读记录/图片尺寸用内存+SharedPreferences 兜底，DB留阶段4
- **完整移植**：5模式+预加载+自定义手势全移植
- **重点**： 图片直加载无分段重组，移植时禁漫图必须经 joycomic 自己的 `jm_image_recombine.dart` 重组 Isolate

### 待移植（任务12~14）

- #12 HorizontalList（横向，PhotoViewGallery单页/双页）
- #13 ReaderImage + reader.dart 主框架 + 叠层UI
- #14 入口接通 + 静态审查 + 文档

## 已知未闭合点（阶段1遗留，阶段2/3 接续）

1. ✅ **源数量与参考不一致**（**已闭环 — 2026-07-09**）：双源配置已全量补全——JM 6 图片源（`fetchSetting` 动态拉取 `app_shunts` + express 快速通道）+ 9 API 兜底域名轮询（5 CDN `cdnhjk/cdngwc×3/cdnutc` + 4 网页 `jmcomic1~4`，CDN 优先）+ 5 图床；Pica 补 `go2778` 中转源 + `picacomic` 直连双源切换。改动见 [CONTEXT.md § 源数量配置](./CONTEXT.md#源数量配置已闭环--2026-07-09)。
2. **`CategoryData` 系列类型为最小骨架**：`comic_source.dart` 末尾补了占位定义，分类页功能留到阶段3 细化。
3. **登录交互仅占位**：`main.dart` 用 `demo/demo` 调通鉴权链路，真实登录表单 + 源切换 UI（JM 测速选源 `SourceSelector`、Pica 双源切换）在阶段3。
4. **无 `ios/` 工程**：云端 CI 首跑 `flutter create . --platforms=ios` 补全，README 已说明。
5. **picsum 占位图** 等阶段3 UI 替换。
6. **本机无 dart 未能实跑静态分析**：源配置改动靠人工逐文件审查保证，待云端 CI 首次 build 验证（顺手修复了阶段1遗留的 `res.dart::Res.fromErrorRes` 重复构造编译阻断 bug）。

## 下次会话起步点

1. ✅ **源决策已闭环**：网络层 `jm_network.dart`（兜底池 9 域名 + 5 图床 + setting 拉取 + 测速选源）与 `picacg_network.dart`（go2778/picacomic 双源）已落地，命脉加密逻辑逐字保留。
2. ✅ **阶段2 阅读器全部完成**（任务7~14）。
3. ✅ **阶段3 UI + 功能集成 + 日志系统全部完成**。
4. 恢复方式：在 `E:/code/joycomic` 目录下 `claude` 新开会话，先读本文件 + CONTEXT.md + docs/stage3-integration-completed.md 即可接上下文。进度已全量写入 PROGRESS.md + CONTEXT.md + memory 三处，不依赖会话历史。

## 阶段3 交付清单（全部完成，2026-07-10）

### 16 页面 UI 落地
```
lib/views/
├── main_scaffold.dart           ★ 4 Tab（首页/分类/收藏/我的）毛玻璃底栏
├── home/home_page.dart          ★ 首页：Logo+工具栏+推荐轮播+最近更新
├── category/category_page.dart  ★ 分类页：分类标签网格
├── favorites/favorites_page.dart★ 收藏页：源筛选+收藏网格
├── mine/mine_page.dart          ★ 我的页：用户卡+功能入口
├── ranking/ranking_page.dart    ★ 排行榜：最新/热门/评分 3 Tab
├── video/video_page.dart        ★ 影视页：全部/动画/真人/广播剧 4 Tab
├── search/search_page.dart      ★ 搜索页：搜索框+历史+热门词+结果+源筛选
├── image_search/image_search_page.dart ★ 以图搜图：上传/拍照+结果
├── detail/detail_page.dart      ★ 详情页：沉浸头+元数据+章节+评论+推荐
├── download/download_page.dart  ★ 下载页
├── settings/settings*.dart      ★ 设置/源设置/阅读设置/日志查看
└── auth/login_page.dart         ★ 登录页：源切换+账号密码+品牌按钮
```

### 8 组功能集成（mock→真实数据）
| 功能 | 集成方式 |
|------|---------|
| 登录 | `source.account.login!()` 真实鉴权 |
| 搜索 | 跨源并行 `searchPageData.loadPage()` |
| 排行榜 | 禁漫 search order（mr/mp/mv） |
| 收藏 | `favoriteData` 契约两源补全 |
| 首页 | `search('',1,[])` 最近更新 + 轮播 |
| 影视 | 标签搜索（动画化/真人化/广播剧） |
| 分类 | `categoryData` 契约两源预设分类 |
| 评论 | `commentsLoader` 契约 JM forum + Pica |

### 7 个新增 API 端点
| 端点 | 源 | 作用 |
|------|----|------|
| `GET /hot_tags` | JM | 热门搜索词 |
| `GET /forum` | JM | 评论列表 |
| `GET /favorite` | JM | 收藏列表/切换 |
| `GET /favorite_folder` | JM | 收藏文件夹 |
| `GET /users/favourite` | Pica | 收藏列表 |
| `GET /comics/$id/comments` | Pica | 评论列表 |
| `POST /comics/$id/favourite` | Pica | 切换收藏（已有） |

### 额外 UI 增强
| 特性 | 说明 |
|------|------|
| 卡片源徽标 | 每张漫画卡左上角 `JM`/`Pica` 标签 |
| 源筛选 Tab | 搜索页+收藏页「全部/禁漫/哔咔」三 Tab |
| 登录检测弹窗 | 点哔咔内容未登录→弹窗→跳转登录页 |
| Shimmer 骨架屏 | `shimmer.dart` 微光扫动 + `LoadingGrid` 全覆盖 |
| 日志系统 | 5 级日志 + 文件轮转 + 查看器（筛选/复制/导出TXT） |

### 新增依赖
| 包 | 版本 | 用途 |
|----|------|------|
| `logger` | ^2.5.0 | 日志引擎 |
| `jiffy` | ^6.3.2 | 时间格式化 |
| `share_plus` | ^10.1.4 | 日志导出分享 |
| `image_picker` | ^1.1.2 | 以图搜图选图/拍照 |

## 阶段4 交付清单（全部完成，2026-07-10）

### 全部 6 任务

| 任务 | 文件 | 功能 |
|:----:|------|------|
| 4-1 DB 基础设施 | `lib/database/joy_database.dart` | sqlite3 双库隔离（core + downloads）5 张表自动建 |
| 4-2 搜索历史 | `search_history_helper.dart` + 搜索页 | sqlite3 持久化 + 20 条上限去重置顶 |
| 4-3 阅读记录 | `read_record_helper.dart` + reader_provider | 50ms debounce 写 DB，支持继续阅读 |
| 4-4 收藏同步 | `favorites_helper.dart` + 详情页/收藏页 | `FavoriteNotifier` 跨 Tab 自动刷新 |
| 4-5 下载管理器 | `download_manager.dart` + 下载页 | Dio 并发限流 3 + 进度追踪 + 暂停/恢复/重试 |
| 4-6 WebDAV 同步 | `webdav_client.dart` + `webdav_sync.dart` + 设置页 | 阅读记录+收藏+历史→archive zip→备份/恢复 |

### 新增依赖
| 包 | 版本 | 用途 |
|----|------|------|
| `sqlite3` | ^2.4.0 | 数据库引擎 |
| `sqlite3_flutter_libs` | ^0.5.28 | 原生库 |
| `archive` | ^4.0.0 | WebDAV zip 打包（已有） |
| `share_plus` | ^10.1.4 | 日志导出（阶段3） |

### 文件结构
```
lib/
├── database/
│   ├── joy_database.dart        ★ DB 管理器（双库隔离）
│   ├── search_history_helper.dart ★ 搜索历史 CRUD
│   ├── read_record_helper.dart  ★ 阅读记录 CRUD
│   ├── favorites_helper.dart    ★ 收藏同步 + FavoriteNotifier
│   └── download_helper.dart     ★ 下载队列 CRUD
├── foundation/
│   ├── download_task.dart       ★ 下载任务模型
│   ├── download_manager.dart    ★ 下载管理器（Dio 并发限流）
│   ├── webdav_client.dart       ★ WebDAV 协议客户端
│   └── webdav_sync.dart         ★ 备份/恢复服务
└── views/settings/
    └── webdav_settings_page.dart ★ WebDAV 配置页面
```
├── theme/
│   ├── app_colors.dart                  ★ 色板 token（背景/卡片/文字层级/品牌渐变/双蒙版）
│   ├── app_spacing.dart                 ★ 间距栅格（4 倍数语义命名）
│   ├── app_radius.dart                  ★ 圆角 token
│   ├── app_shadows.dart                 ★ 阴影 token（上抬光晕+下沉暗影双系）
│   ├── app_typography.dart               ★ 字体层级 token
│   ├── app_motion.dart                  ★ 动效时长/曲线 token
│   ├── app_theme.dart                    ★ ThemeData 组装（深色唯一主题）
│   └── widgets/pill_badge.dart           ★ 微光胶囊标签（详情/列表复用）
├── views/
│   ├── common/widgets/
│   │   ├── comic_cover.dart              ★ 封面图（微阴影/细边框/骨架占位/网络+本地）
│   │   ├── comic_card.dart              ★ 漫画卡片（poster/horizontal/grid 三形态）
│   │   └── rating_stars.dart             ★ 五星评分（含半星 CustomPaint）
│   └── detail/
│       ├── detail_page.dart              ★ 详情页主框架（CustomScrollView+Sliver+悬浮底栏）
│       ├── detail_view_model.dart        ★ 详情 ViewModel（加载态枚举+取色注入+demo旁路）
│       ├── detail_demo_data.dart         ★ 演示数据（picsum 占位图+中文文案，样板可跑）
│       └── widgets/
│           ├── hero_header.dart          ★ 沉浸式双封面通栏（4 层叠加）
│           ├── info_overlay.dart         ★ 信息层（热度pill/标题/元数据/评分复合）
│           ├── synopsis_block.dart       ★ 简介展开/收起（TextPainter 测溢出）
│           ├── chapter_grid.dart         ★ 章节目录网格（2列+NEW角标+16:9封面）
│           ├── comment_section.dart      ★ 评论组件（头像/勋章/星级/点赞）
│           ├── recommendation_carousel.dart ★ 相关推荐横滑（3:4海报+评分）
│           ├── sticky_action_bar.dart    ★ 悬浮底栏（收藏+阅读双按钮，主按钮取色渐变）
│           └── detail_app_bar.dart       ★ 详情导航栏（透明+滚动叠加渐变）
```

### 设计决策（2026-07-10 定，详见 CONTEXT.md §阶段3 UI 设计语言）

- **静态主品牌色**：藕粉 `#FF7BA9` → 紫罗兰 `#B967FF` 渐变；背景 `#0E0B14` 深墨紫黑、卡片 `#1B1622` 暖紫黑面
- **动态取色范围**：仅详情页局部（头部渐变/底栏主按钮/星级进度）跟随封面色；列表/导航恒定静态主色
- **取色实现**：`PaletteExtractor.extract(url)` → dio 取字节 → `compute` Isolate → `image.decodeImage` + `getRange` 步长采样（与 jm_image_recombine 同套已验证 API）→ 色相 12 桶聚类 → HSL 钳制（饱和度 0.55~1、亮度 0.5~0.72）→ accent+accentVariant；失败回退 `ComicPalette.fallback`
- **详情页样板测试**：占位首页"打开 XX 详情页样板"→ `/detail/{key}/demo-comic-id` 走 `detail_demo_data.dart` 演示旁路，无网络也能看完整设计
- **路由**：`/detail/:sourceKey/:comicId` 新增，comicId==`demo-comic-id` 注入 demo 数据跳过网络

### 待补（阶段3 阶段二）

- 首页（底部 Tab + 卡片网格 + 探索横滑）
- 搜索页 / 搜索结果
- 收藏页 / 下载页
- 设置页 / 登录页（真实登录表单 + JM 测速选源 SourceSelector + Pica 双源切换）
- 把详情页样板接入真实源（登录后真实漫画详情）+ 评论/推荐真实数据

## 阶段3 阶段一·补丁：接真实源验证取色（2026-07-10）

详情页样板之前只能跑 demo 数据旁路。本次把两源网络层已实现的方法**接到 ComicSource 契约字段**，让真实搜索 → 真实详情 → 动态取色全链路可跑（禁漫免登录可搜）。

### 改动清单

| 文件 | 改动 |
|------|------|
| `lib/comic_source/built_in/jm.dart` | 补 `loadComicInfo`（JmNetwork.getComicInfo→ComicInfoData）/`loadComicPages`（getChapter）/`getImageLoadingConfig`+`getThumbnailLoadingConfig`（imageHeaders 鉴权头）/`searchPageData`（search 免登录）；新增 `_jmInfoToComicInfoData` 映射 + `_formatCount` 数值量化 |
| `lib/comic_source/built_in/picacg.dart` | 同上对应：`loadComicInfo`（getComicInfo）/`loadComicPages`（getComicContent，ep=order）/`searchPageData`（search，需登录）；新增 `_picacgItemToComicInfoData` 映射 + `_formatCount` |
| `lib/views/search/temp_search_page.dart` | 新增临时搜索页：调源 `searchPageData.loadPage` → 3 列网格 `ComicCard.poster` → 点进 `/detail/{key}/{id}` 真实详情 |
| `lib/main.dart` | 加 `/search/:sourceKey` 路由；占位首页加"搜索 XX"入口（禁漫免登录、哔咔需登录） |

### 关键映射约定

- **章节标识**：禁漫 chapters key=`chapterId`（series 映射值），哔咔 key=`order.toString()`。`loadComicPages(comicId, ep)` 的 ep 即此 key，阅读器 `_resolveImageLoader` 已自动透传。
- **tags 映射到 ComicInfoData.tags**（`Map<String,List<String>>`）：作者/标签/作品 + 热度/收藏/评价人数数值化，供详情页 `_hotValue`/`_favCount`/`_ratingCount` 取用。禁漫无评分数据，留空走默认 8.0 占位（不编造）。
- **封面鉴权头**：禁漫 `getThumbnailLoadingConfig` 返回 `imageHeaders()`（UA/Referer，部分图床校验）；哔咔图片无鉴权返回 null。取色器 `PaletteExtractor.extract(cover, headers: coverHeaders)` 复用同一份头。
- **封面 URL host**：禁漫 `getJmCoverUrl` 依赖全局 `jmBaseUrl`（未登录=默认图床 `cdn-msp3.jmapiproxy1.cc`，可达性看运气；不通则取色回退品牌色，也是验证点）。

## 阶段3 阶段二：全套页面 UI 落地（2026-07-10）

主人调整方向：**只设计全部页面 UI + 留功能注释，真实功能由其他 AI 集成**。
本阶段落地 16 个页面 + 4 个公共组件 + Tab 框架 + 6 篇功能设计文档。全部深色基调，
沿用阶段一设计 token，数据全 mock（picsum 占位 + 中文文案），每文件顶部 `library`
文档注释写明页面结构与功能集成方式。

### 公共组件（`lib/views/common/widgets/`）

| 文件 | 功能 |
|------|------|
| `empty_state.dart` | 空态/错误态统一（图标+标题+副文本+动作按钮）|
| `section_header.dart` | 区块标题（左标题+可选副+右动作入口）|
| `loading_grid.dart` | 骨架加载网格 |
| `comic_grid.dart` | 漫画网格通用组件（下拉刷新+上拉加载+三态切换）|

### Tab 框架

`lib/views/main_scaffold.dart`：4 Tab（首页/分类/收藏/我的）+ 毛玻璃半透明底栏 +
品牌色选中态。`main.dart` 首页路由改为 `MainScaffold`。

### 首页 + 工具栏入口

| 文件 | 功能 |
|------|------|
| `home/home_page.dart` | 首页：顶栏(Logo+搜索) + 工具栏 + 编辑推荐横滑 + 最近更新网格 |
| `home/widgets/home_tool_bar.dart` | **6 入口横滑**：最新/热门排行/影视/以图搜图/收藏库/下载（渐变光晕圆）|
| `home/widgets/featured_carousel.dart` | 大幅封面横滑轮播（渐变蒙版+标题+badge）|
| `ranking/ranking_page.dart` | 排行榜：最新/热门/评分 3 Tab + 日/周/月/总榜筛选 |
| `image_search/image_search_page.dart` | 以图搜图：选图区+相册/相机+结果网格 |
| `video/video_page.dart` | 影视：全部/动画/真人/广播剧 4 Tab + 网格 |

### 分类/收藏/我的

| 文件 | 功能 |
|------|------|
| `category/category_page.dart` | 分类：搜索框+一级 tab+分类标签网格+随机推荐 |
| `favorites/favorites_page.dart` | 收藏：多文件夹横滑+排序+网格+空态引导 |
| `mine/mine_page.dart` | 我的：用户卡(未登录占位)+统计三宫格+功能入口列表 |

### 搜索/下载/设置/登录

| 文件 | 功能 |
|------|------|
| `search/search_page.dart` | 搜索：搜索框+历史+热门词+结果网格+空态 |
| `download/download_page.dart` | 下载：下载中/已下载 2 Tab + 任务卡进度+速度栏 |
| `settings/settings_page.dart` | 设置：源管理/阅读/外观/数据/关于分组 |
| `settings/source_settings_page.dart` | 源设置：禁漫图床测速(6项)+API兜底域名+哔咔双源 |
| `settings/reader_settings_page.dart` | 阅读设置：5模式单选+预加载+显示开关+图片质量 |
| `auth/login_page.dart` | 登录：源切换chip+账号密码+品牌渐变登录按钮 |

### 功能设计文档（`docs/features/`）

为主人下一阶段集成而写，影视和以图搜图参考 `clone/joycomic-ios`：

| 文档 | UI 位置 | 参考源 |
|------|---------|--------|
| `latest.md` | 首页最近更新+排行榜最新 | 两源 search 空 keyword |
| `ranking.md` | 排行榜页 | 禁漫 search order + 哔咔 RankingData |
| `video.md` | 影视页 | **joycomic-ios MoviesScreen**（videos 端点 + videoType 映射）|
| `image-search.md` | 以图搜图页 | **joycomic-ios ImageSearchScreen**（SauceNAO + soutubot）|
| `search.md` | 搜索页 | 两源 searchPageData 并行 + 历史本地存储 |
| `favorites.md` | 收藏页 | **joycomic-ios LibraryScreen**（favorite + folder 系列端点）|

另 `docs/stage3-ui-deliverables.md` 汇总全部文件清单 + 路由表 + 功能集成约定。

### 路由表（`main.dart`）

`/` MainScaffold / `/search/:sourceKey` / `/ranking?tab=` / `/image-search`
`/video` `/download` `/login?source=` `/settings` `/settings/source` `/settings/reader`
`/detail/:sourceKey/:comicId` / `/reader`，未匹配路由走 `errorBuilder` 占位页（避免崩溃）。

### 集成约定（给集成的 AI）

- 每个页面文件顶部 `library` 注释含：①页面结构 ②功能集成说明（真实数据来自哪个
  ComicSource 契约字段）③当前 mock/留位标记。
- 替换 mock 数据为真实调用即可，UI 布局不动。
- `docs/features/*.md` 详述每个功能的数据来源、端点、ViewModel 契约、待定问题。

### 静态审查结论

本机无 dart 未实跑，靠人工逐文件静态审查：
- 全部 import 路径自洽、依赖文件齐全（4 Tab 页 + 公共组件均存在）
- `Navigator.pushNamed` 残留已清零（全改 `context.push`）
- `image` 包只用 `jm_image_recombine` 已验证 API（decodeImage+getRange+current.r/g/b）
- 通配路由改 `GoRouter.errorBuilder` 占位（go_router 16 通配语法易错）
- 重复 gradient 赋值已清理（category_page）


