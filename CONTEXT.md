# JoyComic 关键上下文

> 本文档记录不会被代码或 git 体现的关键决策、约束、与参考项目的差异。是 [PROGRESS.md](./PROGRESS.md) 的"为什么"与"注意点"伴侣文档。
> 来源：从已卡死的开发会话 `f0ccb366`（788 行 / ~9.7 万 token，因上下文超限 + `/compact` 被打断而卡死）抢救整理。

---

## 技术栈决策

- **纯 Dart / Flutter，不引入 Rust。** 原因：主人 Windows 开发机无法编译 iOS，Rust 会增加 iOS 原生链接与云端 CI 复杂度。
- **离线归档用 `archive` + `pdf` 纯 Dart 包**替代  的 Rust 归档能力。
- **图片加解密全部纯 Dart**：哔咔 HMAC-SHA256（`crypto` 包）、禁漫 AES-ECB + MD5 token（`pointycastle` 包）、禁漫图片分段重组（`image` 包 + 独立 Isolate）。
- **依赖锁版本**已写入 `pubspec.yaml`（dio 5.7 / pointycastle 3.9.1 / uuid 4.5 / image 4.3 / go_router 16 / sqlite3 2.4 等），阶段2~4 直接用，勿随意升 major。

## 参考项目的边界（绝对约束）

三个 `clone/` 仓库**只读参考，不参与编译、不复制源码注释/作者名/溯源表述**。移植时只能中性重写逻辑。

| 参考项目 | 路径 | 仅参考什么 | 它的"语言"不采用 |
|---|---|---|---|
|  | `clone/` | 网络层签名/解密逻辑、DB 设计、WebDAV 同步 | 它是 Flutter/Dart（与本项目一致，最易移植） |
|  | `clone/` | 阅读器交互（5 模式/预加载/缓存）、UI 质感 | 它含 Rust，**Rust 部分必须用纯 Dart 重写** |
| joycomic-ios | `clone/joycomic-ios` | 功能定位的"目标蓝本" + 源配置 + 测速选源交互 | 它是 **React Native/TS，仅参考功能不改语言** |

已 grep 校验：项目内无任何仓库名/作者名/溯源评论残留，仅保留 `picaapi.picacomic.com`、`jmcomic1~4.cc` 等必需 API 域名。

## 源数量配置（✅ 已闭环 — 2026-07-09）

主人原话（idx=727）：*"jm 我记得是有五个源的，还有一个快速源，应该算六个源吧？然后就是 pica，pica 是不是有两个源？"*

经 Agent 核查 `clone/joycomic-ios` 的 TS 实现，结论如下（**主人记忆基本正确**），已全量落地：

### JM 禁漫 —— 6 个图片源 + 9 个 API 兜底域名

| 层级 | 是什么 | 数量 | 落地位置 |
|------|--------|------|------|
| 图片源（用户可选） | `app_shunts` 动态分流 + express 快速通道 | **6**（服务端动态 + express key=0） | `jm_network.dart::JmNetwork.fetchSetting/testAllShunts/selectShunt`、`source_state.dart::JmState.shunts/selectedShuntKey` |
| API 兜底域名 | 失败时自动轮询切换 | **9**（5 CDN `cdnhjk/cdngwc×3/cdnutc` + 4 网页 `jmcomic1~4`） | `jm_network.dart::jmBuiltInDomains` + `_withDomainFailover` 轮询 |

> JM 用户可选图片源 = 服务器 `app_shunts` 动态分流（运行时拉取）+ 1 个 express 快速通道（key=0，拼 `?express=on`）= **6 个**；另有 **9 个 API 兜底域名**用于失败重试（CDN 优先 + 网页域名兜底），与"源"非同层级。
> 轮询优先级对齐参考 `client.ts`：`用户首选(preferredDomain) > 当前主源(apiBaseUrl/setting 的 main_web_host) > 兜底池`，由 `_domainCandidates` 实现。
> 命脉加密逻辑（MD5 token / AES-ECB 解密 `convertData` / 图片分段重组）**逐字保留未动**。

### Pica 哔咔 —— 2 个源（已补 go2778）

| 源 key | 域名 | 性质 | 落地 |
|--------|------|------|------|
| `go2778`（中转） | `https://picaapi.go2778.com` | 默认 | `picacg_network.dart::picacgApiHosts` + `apiUrl` getter + `PicacgStateImpl.apiBaseUrl` |
| `picacomic`（直连） | `https://picaapi.picacomic.com` | 备用 | 同上，运行时切换持久化 `source.data['apiBaseUrl']` |

两者同一套 HMAC 签名（`buildHeaders` 命脉保留未动），UI 切换写 `setApiBaseUrl` 持久化。

### 已落地改动清单（6 文件）

| 文件 | 改动 |
|------|------|
| `lib/network/source_state.dart` | `PicacgState` 加 `apiBaseUrl/setApiBaseUrl`；`JmState` 加 `preferredDomain/shunts/selectedShuntKey` 共 6 字段；新增 `JmShunt` 类 |
| `lib/network/jm/jm_network.dart` | 兜底池 9 域名 + 5 图床；`get/post` 经 `_withDomainFailover` 轮询；新增 `fetchSetting/getShuntImgHost/testAllShunts/pickFastest/selectShunt/testImgHostLatency` + `JmShuntSpeed` |
| `lib/comic_source/built_in/jm.dart` | `JmStateImpl` 实现 6 新字段；登录流改为探测→登录→`fetchSetting` 拉取 shunts |
| `lib/network/picacg/picacg_network.dart` | `_apiUrl` const → `picacgApiHosts` 候选 + `apiUrl` getter（默认 go2778） |
| `lib/comic_source/built_in/picacg.dart` | `PicacgStateImpl` 实现 `apiBaseUrl`；`initData` 默认 go2778 |
| `lib/network/res.dart` | 顺手修复阶段1遗留的 `Res.fromErrorRes` 重复构造定义（编译阻断级） |

### 阶段1遗留也顺手修复

`res.dart` 存在 `Res.fromErrorRes` 重复定义（39-45 行重复），会导致 `duplicate constructor` 编译错误——阶段1靠逐文件审查未发现，本次改动顺手修掉。

## 阶段2 阅读器移植关键技术约束（⚠️ 必读）

### Rust 不需要重写（已在 2026-07-09 摸清）

经探查 `clone//rust/`： 的 Rust 只暴露两类离线功能——`compress.rs`（zip 打包/解压，用于 WebDAV 备份恢复 + 各平台导出 zip）、`simple.rs::export_pdf`（图片目录→PDF 导出）。**阅读器看图链路零 Rust 调用**，整 `views/reader/` 目录 grep Rust 全无命中。

→ **阶段2 阅读器移植无需重写任何 Rust**，直接移植 Dart 层即可。Rust 相关的 zip/PDF/WebDAV 备份推迟到阶段3/4 用 joycomic 已锁的 `archive`(^4.0.0) + `pdf` 包替代，与阅读器解耦。

### 阅读器看图链路是纯 Dart 但需接 joycomic 重组逻辑

 阅读器 `reader_image.dart` 直接拿 API 返回的 `media.url` 喂 `CachedNetworkImageProvider`/`FileImage`，**无解密无分段重组**—— 根本没实现禁漫图片分段。

但 joycomic 阶段1已实现禁漫图片分段重组（`lib/foundation/jm_image_recombine.dart`，独立 Isolate）。→ **移植阅读器时**：网络取图后，禁漫图片必须经 joycomic 自己的重组 Isolate 还原再渲染，不能照搬  的直加载流程（否则禁漫新章节图会乱序）。

### 5 种阅读模式（read_mode.dart，纯 enum 零依赖可直接移植）

```
1. vertical         连续从上到下   ← 竖直连续流 scrollable_positioned_list
2. leftToRight      单页从左到右   ← 单页 PageView
3. rightToLeft      单页从右到左   ← 单页 PageView 反向
4. doubleLeftToRight 双页从左到右  ← 双页 PageView
5. doubleRightToLeft 双页从右到左  ← 双页 PageView 反向
```
方向判定 helper：`isVertical`/`isDoublePage`/`isReverse`。

### 依赖对齐差异（ vs joycomic，移植前需决策）

|  用的 | joycomic 现状 | 差异/处理 |
|---|---|---|
| `photo_view` (fork d951ef0) | `photo_view: ^0.15.0` (pub 官方) | 先用 pub 官方版移植，遇 fork 定制能力缺失再回退 fork |
| `cached_network_image_ce` ^4.9.0 | `cached_network_image` ^3.4.1 | **大版本差异**，API 不同，需统一（倾向升到 _ce 系或评估官方4.x） |
| `scrollable_positioned_list` (fork) | ❌ 缺失 | 竖直连续模式定位必需，需加（先 pub 官方版） |
| `vector_math` ^2.2.0 | ❌ 缺失 | 缩放手势数学必需，需加 |
| `pool` ^1.5.2 | ❌ 缺失 | 预加载并发限流，需加 |
| `provider` ^6.1.5 | `provider: ^6.1.2` | 兼容，统一升 ^6.1.5 |

### 阅读器 Dart 架构要点（2026-07-09 摸清）

**核心结构**：`reader.dart` 纯 StatefulWidget，`provider` 包管两个 `ChangeNotifier`：
- `ReaderProvider`（内容态：章节切换 `go/goNext/goPrevious`/页码 `pageNo`(双页模式经 `toCorrectMultiPageNo` 换算)/阅读记录 50ms debounce 写 `ComicReadRecord`/翻页 `pageTurnForVertical`&`pageTurnForHorizontal`/沉浸式 UI `openOrCloseToolbar`)
- `ListStateProvider`（UI 态：`isCtrlPressed`/`physics`/`verticalListWidthRatio`/`lockMenu`/`showPageNumbers`）

**渲染只有两 widget**（`reader.dart:86` 按 `isVertical` 二选一）：
- `VerticalList`（竖直连续）= `ScrollablePositionedList` + **自定义 `InteractiveViewer`**（非 photo_view，`gesture.dart:184`，minScale1.0/maxScale3.5/MATRIX4Tween 双击放大/双指切physics）
- `HorizontalList`（横向）= `PhotoViewGallery`（`horizontal_list.dart:158`，单页 minScale contained*1 maxScale covered*4；双页 `buildPageImages` Row 并排 + reverse 控序，maxScale covered*10）

**预加载**（`image_preload_controller.dart`）：`maxPreloadCount=4`（设置可调2-8），keepWindow=10 debounce50ms，方向感知基于 first/last 与 `_lastAnchorIndex` 判 isBackward，用**相同 `ResizeImage(cacheWidth)` 包裹保证缓存命中**，`generation` 元组失效旧记录，`updatePreloadCacheWidth` 由 LayoutBuilder 校准，`invalidatePreloaded()` 清缓存。

**章节边界**：竖值模式末尾"本章完"占位项(`itemCount:pageCount+1`)+越界 `goNext/goPrevious`+Toast；横向模式越界切章 + 边缘 `ChapterSwipeDetector`(注意当前被注释未挂，改用 `gesture.dart::GestureWrapper`)；浮动下一章 FAB(`next_chapter.dart`，pageNo>=total-2 && !isLastChapter 淡入)。

**图片加载缓存**（`reader_image.dart:55`）：`CachedNetworkImageProvider`(网)/`FileImage`(本) + `ResizeImage.resizeIfNeeded(cacheWidth)`，`DefaultCacheManager(stalePeriod:15d)`，`RetryForImage` 重试，尺寸入 DB `ImagesHelper`。

**移植需用 joycomic 基础设施替代/简化的  模块**：`AppConf`(配置→用阶段1`app_data.dart`或新增)、`network/models`(→joycomic已有`base_comic`/`jm_models`/`picacg_models`)、`utils/request/*`(→joycomic用Res封装简化)、`database/read_record_helper`+`images_helper`(→阶段4 DB，移植期先内存/shared_preferences兜底)、`utils/extension`/`common`/`log`/`ui`(→自写最小)、`widgets/toast`/`error_page`/`retry_for_image`/`deferred_blur`/`shadow_text`(→自写或精简)。

**注意 publisher 关键修正**：无任何方向锁定代码（grep `lockOrientation` 0命中），资源里的"lockOrientation设置"是误信息，只锁菜单`menuLocked`。阅读记录DB与图片尺寸DB属阶段4，移植期可空实现/兜底。

- **声明式多源契约**：`ComicSource` 用 typedef 函数字段描述契约（非继承抽象类），每个源在 `built_in/` 下以 `ComicSource.named(...)` 声明并注册到 `builtInMap`，靠 **key 路由**到实现，无 if-else 硬编码。新增源 = 新增一个 `built_in/xxx.dart` + 在 `registrar.dart` 注册一行。
- **状态门面模式**：每个网络类有 `state` 字段（如 `PicacgNetwork()..state = PicacgStateImpl(source)`），网络层不直接读 `ComicSource.data`，统一走 `XxxStateImpl`。改源数据 = 改 `source.data[...]` + `source.saveData()`。
- **网络单例 + cascade 注入**：`PicacgNetwork()` / `JmNetwork()` 是 factory 单例，`..state=XxxStateImpl(source)` 在源构造时一次性注入。reload 时覆盖即可。
- **Res<T> 统一封装**：所有网络方法返回 `Res<T>`，错误统一 `Res.fromErrorRes(res)`，外层只判断 `res.error` / `res.data`。
- **禁漫图片重组走 Isolate**：`jm_image_recombine.dart` 用独立 Isolate 后台执行条带重组，不阻塞 UI。
- **`ComicInfoData` 用 `with HistoryMixin`**：`target=comicId`、`historyType`、`title` 实现 mixin 要求，收藏/历史由阶段4 DB 接入。

### ReaderProvider 移植关键设计（2026-07-09 定，任务9落地）

| 决策 | 做法 | 原因 |
|------|------|------|
| `ReaderImageLoader` 回调注入 | `typedef ReaderImageLoader = Future<Res<List<String>>> Function(String comicId, String? ep)` | 源无关，reader 不需要知道图片来源是哪个网络层 |
| 砍掉 `RequestProvider` 基类 | 直接 `extends ChangeNotifier` + `ReaderLoadState` 枚举 |  的 handler 模式耦合其专用网络层，joycomic 的 `Res<T>` 已统一封装 |
| 砍掉 `volume_button_override` | 不实现音量键翻页 | iOS 场景无拦截音量键需求 |
| 砍掉 DB `ReadRecordHelper` | 50ms debounce + 内存兜底 | 阶段4 统一接入 sqlite3，移植期不引入 DB 依赖 |
| `ImagePreloadControllerRef` 抽象契约 | 在 `reader_provider.dart` 定义抽象接口 | 任务10 实现前先定交互边界，保证 ReaderProvider 不依赖具体预加载实现 |
| `ReaderImage` 值类 | url + cacheKey，==/hashCode 对照 cacheKey | 替代  的 `ImageBase` 抽象类，简化图片数据模型 |
| `_pageNo` 始终存原始单页索引 | 双页模式 getter 返回 `~/2`，setter 存原始值 | 与  一致，保证 `multiPageImages` 缓存分组逻辑正确 |
| `onPageNoChanged` 对比 `_pageNo` 而非 `pageNo` | 避免双页模式下不必要的冗余通知 | 修复  原版的细微 bug（ 对比 `pageNo` 在双页模式下可能误判） |

### 2026-07-09 已落地的 ReaderProvider 模块清单

- `lib/views/reader/providers/reader_provider.dart`（~645 行）— 内容态 Provider
- `lib/views/reader/providers/list_state_provider.dart`（~72 行）— UI 态 Provider（任务8 并入任务7）
- `lib/views/reader/state/comic_state.dart` — ReaderChapter / ComicState / ReaderType / ReaderImage（任务8 并入任务7）

### ImagePreloadController 移植设计（2026-07-09 定，任务10落地）

| 决策 | 做法 | 原因 |
|------|------|------|
| 非泛型，硬绑定 `ReaderImage` | `implements ImagePreloadControllerRef` | joycomic 只有一个图片类型，去泛型减复杂度 |
| 砍掉 `urlResolver` / `cacheKeyResolver` 回调 | 直接用 `ReaderImage.url` / `.cacheKey` | `ReaderImage` 是统一值类，不需要回调来适配多实现 |
| `ResizeImage` 对齐缓存键 | `ResizeImage.resizeIfNeeded(cacheWidth, null, base)` | 预加载和解码用同一 cacheWidth，否则 ImageCache key 不同造成白预加载 |
| `invalidatePreloaded` 不取消 timer | 仅递增 `_generation` + 清 `_preloaded` | 防止 LayoutBuilder 校准 cacheWidth 吃掉数据加载后的首批预加载 |

### VerticalList 移植设计（2026-07-09 定，任务11落地）

| 决策 | 做法 | 原因 |
|------|------|------|
| 图片渲染使用 `ReaderImage` widget | 正式 ReaderImage 组件 | 任务13 提取后垂直列表直接引用 |
| `ImagePreloadController` 在 `initState` 创建 | `VerticalList.initState` 中 `new` + `ReaderProvider.initPreloadController` | 控制器生命周期跟随列表 widget，不在 Provider 中管理 |
| `ComicListMixin` + DB 跳过 | 不查询/存储图片尺寸 | 阶段4 DB 统一接入 |
| `ChapterSwipeDetector` 跳过 | 不移植边缘滑动手势 |  原版也注释掉了该组件 |
| 三区翻页参数 | `ReaderConf.verticalCenterFraction`（默认 0.3）| 上/中/下 = (1-center)/2 / center / (1-center)/2 |
| 双击缩放倍数 | `Matrix4.identity()..translateByVector3(..)..scaleByVector3(3.0,3.0,1.0)` | 以双击点为中心放大 3×，双击恢复 1:1 |

### HorizontalList 移植设计（2026-07-09 定，任务12落地）

| 决策 | 做法 | 原因 |
|------|------|------|
| `PhotoViewGallery` 非 `PageView` | Gallery 提供内置缩放/双页/反向 | 与  一致，零适配 |
| 双页模式用 `customChild` | Row + 2× `ReaderImage` | 支持各自独立缩放 |
| 图片缓存踢出 `_evictImage` | 走 `cacheManager.removeFile` + `CachedNetworkImageProvider.evict` | 重试时确保重新下载 |
| 滚轮翻页 200ms 防抖 | `_scrollLock` bool 锁 | 防连续滚轮触发多次翻页 |

### reader.dart + ReaderImage + 叠层UI（2026-07-09 定，任务13落地）

| 决策 | 做法 | 原因 |
|------|------|------|
| `Reader` 接收 `ComicState` + `ReaderImageLoader` | 不依赖 ComicSource 上下文 | 单元可测、源无关 |
| `MultiProvider` 两 Provider | `ReaderProvider` + `ListStateProvider` | 内容态与 UI 态分离 |
| `ReaderImage` 识别网络/本地 | `Uri.tryParse(url)?.scheme` | 自动判断，无需 `ReaderType` 参数 |
| 工具栏 `AnimatedPositioned` | top/bottom 滑入滑出 | 系统 UI 模式 + 动画双保险 |
| 章节列表 `Drawer` → `ScrollablePositionedList` | 定位当前章节 | 与  一致 |
| 缩放图片 `ReaderImage` 用 `RetryForImage` | 3 次自动重试 + 手动重试 | joycomic 已有 RetryForImage 实现 |

### 入口连接（2026-07-09 定，任务14落地）

| 决策 | 做法 | 原因 |
|------|------|------|
| `GoRouter` 路由 | `/reader` 接收 `ComicState` extra | 阶段3 详情页 push 即可 |
| `ReaderImageLoader` 自动匹配 | reader 路由内 `ComicSource.find(sourceKey).loadComicPages` | 调用方无需手动传 |
| 测试入口 | 占位首页登录后显示测试按钮 | 阶段2 可手动验证阅读器 |

## 阶段3 UI 设计语言 + 功能集成 + 日志系统（全部完成，2026-07-10）

### 设计语言（阶段一已落地）

- **深色唯一主题**，全程深墨紫黑底，不提供 lightTheme
- **静态主品牌色**：藕粉 `#FF7BA9` → 紫罗兰 `#B967FF` 渐变（取色兜底色）
- **7 个自建 Design Token 文件**：`app_colors`/`app_typography`/`app_spacing`/`app_radius`/`app_shadows`/`app_motion`/`app_theme`
- **无第三方 UI 组件库**，全部 Flutter 原生手写
- **详情页动态取色**：`palette_extractor.dart` → Isolate 色相聚类取封面色`

### 动态取色（详情页局部）

- **范围**：仅详情页"头部渐变 + 底栏主按钮 + 星级/进度"跟随封面色；列表/导航/其他页恒定静态主色
- **实现**：`lib/foundation/palette_extractor.dart` → dio 取字节 → `compute`（Isolate）→ `image.decodeImage` + `getRange` 步长采样（与 [jm_image_recombine.dart](./lib/foundation/jm_image_recombine.dart) **同套已验证 API**，不用 `getPixel`/`copyResize` 等未验证项）→ 色相 12 桶聚类 → HSL 钳制（饱和度 0.55~1、亮度 0.5~0.72）
- **accent + accentVariant 二色**：主桶均值 + 次桶均值（无次桶则 accent 色调 +30° 派生）
- **失败回退**：`ComicPalette.fallback`（=静态品牌色），缓存 url→结果避免重复解码
- **注入方式**：`DetailViewModel` 首屏先铺 fallback 立即可渲染，取色完成后 `notifyListeners` 平滑替换
- **预热**：`PaletteExtractor.prefetch(url)` 供列表页滚动到卡片前置取色

### 详情页 4 区块（按主人原始描述逐条落地）

| 区块 | widget | 关键实现 |
|------|--------|---------|
| 1 沉浸式双封面通栏 | `hero_header.dart` | 4 层叠加：后层背景 CachedNetworkImage cover 截取（非模糊）+ 顶部暗化蒙版 + 取色染色氛围光 + 底部大面积渐变蒙版融入主体；前景 `ComicCover` 左侧完整无裁剪矩形封面 + 微阴影立体感 |
| 1 导航栏 | `detail_app_bar.dart` | 常驻最顶透明，左返回/右分享+更多；滚动到内容区叠加实色渐变 |
| 1 信息叠加层 | `info_overlay.dart` | 热度 `PillBadge` 置顶 → 主标题 + 两行副标题 → 评分复合（大号数字取色 + 五星 + 评价人数） |
| 2 简介组件 | `synopsis_block.dart` | 小标题"简介" + 多行文本，TextPainter 测溢出决定"展开/收起"按钮显隐，右下角渐变底文字按钮 |
| 2 章节目录 | `chapter_grid.dart` | 头部"章节/更新至XX话"+右"全部 >"入口；2 列 GridView，16:9 章节封面 + 最新章 NEW 角标 + 单行名 |
| 3 评论组件 | `comment_section.dart` | "评论(总数)"+右"更多评论 >"；评论卡=头像/昵称/等级勋章/星级/多行文/时间+点赞数 |
| 3 相关推荐 | `recommendation_carousel.dart` | "相关推荐"+右"换一换(旋转Icon)"；横滑 `ComicCard.poster` 3:4 海报 + 名 + 评分 |
| 4 悬浮底栏 | `sticky_action_bar.dart` | 常驻不随滚动消失；次级收藏(心形+状态,92宽轻量卡) + 主阅读(高亮取色渐变胶囊,主标题+副提示) |

### 取色 API 与已验证 image 包调用约束

- `image` 包只信 `decodeImage(bytes)` + `Image.getRange(x,y,w,h)` 返回的迭代器 + `current.r/g/b`（num 通道）——这三项在 `jm_image_recombine.dart` 已跑通禁漫重组，是 joycomic 唯一验证过的像素访问路径。
- **禁止**引入 `getPixel`/`copyResize`/`numChannels` 等未在本项目验证的 API（context7 查到的 image 包文档版本杂，Elixir/Rust/Dart 混淆，未验证直接用有编译风险）。
- Isolate 用 `package:flutter/foundation.dart` 的 `compute`（已在 `PaletteExtractor.extractFromBytes` 用），不手搓 `Isolate.spawn`。

### 路由与样板

- `/detail/:sourceKey/:comicId` 新增；`comicId == 'demo-comic-id'` 时 `main.dart` 路由 builder 注入 `buildDemoComicInfo()` 演示数据，`DetailViewModel` 走 demo 旁路跳过网络，无登录也能看完整设计。
- 占位首页加"打开 XX 详情页样板"入口，picsum 占位图 + 中文文案构造的 `ComicInfoData` 跑通沉浸头/取色/章节网格/推荐/悬浮底栏。
- 评论/相关推荐当前用占位数据（total=0、suggestions 来自 demo），阶段3 阶段二接入真实源 `commentsLoader` / `loadComicInfo` 返回的 suggestions。

## 卡死现场记录（避免重蹈覆辙）

- 原会话最后状态：`/effort max`（最高推理）+ 上下文已达 ~9.7 万 token + `/compact` 被打断 → 卡在"等待 compact 总结结果"的中间态，后续任何「继续」都挂在未完成请求上。
- **教训**：(1) 体量到 ~6 万 token 主动 `/compact`，别等到 9.7 万；(2) compact 跑的时候**别按「继续」打断**它；(3) 长任务用 `/effort high` 而非 `max`，max 对超大上下文更易超时；(4) 「继续」不要在已有流式响应进行时连按。

## 下次会话起步点

1. 先读本 `CONTEXT.md` 与 [PROGRESS.md](./PROGRESS.md) 接住全部上下文。
2. ✅ 「源数量待澄清」已闭环（见上节），网络层双源配置已全量落地，本机无 dart 未能实跑 `dart analyze`，待云端 CI 首次 build 验证。
3. 阶段2 阅读器移植**全部完成**（任务7~14）。阅读器架构详见本文件 §阅读器 Dart 架构要点 §ReaderProvider 移植关键设计 §ImagePreloadController 移植设计 §VerticalList 移植设计 §HorizontalList 移植设计 §reader.dart + ReaderImage + 叠层UI §入口连接。
4. ⏳ 阶段3 UI 进行中：设计 token + 动态取色 + 详情页样板已落地（详见本文件 §阶段3 UI 设计语言 + PROGRESS.md §阶段3 阶段一交付清单），首页/搜索/收藏/下载/设置/登录待补。
5. 恢复方式：`cd /e/code/joycomic && claude` 新开会话，先读本 `CONTEXT.md` 与 [PROGRESS.md](./PROGRESS.md) 接住全部上下文。进度已全量写入 PROGRESS.md + CONTEXT.md + memory 三处，不依赖会话历史。
