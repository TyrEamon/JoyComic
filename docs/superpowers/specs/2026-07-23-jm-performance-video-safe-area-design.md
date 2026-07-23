# 禁漫源视频、性能与安全区优化设计

**日期：** 2026-07-23  
**状态：** 待用户复核  
**范围：** 禁漫源（JM）网络请求、图片加载、影视播放和独立页面底部安全区

## 目标

1. 修复禁漫影视在 API 已返回有效 HLS、但原生播放器黑屏，随后 WebView 因网页 `504` 超时的失败链路。
2. 缩短禁漫详情、搜索、列表、章节和图片页面的首次等待时间，避免多个页面并发重复扫描失效域名。
3. 保持现有 JM token、Cookie、AES 解密、图片解扰和缓存 key 不变。
4. 为独立滚动页面统一补上系统底部安全区，避免底部操作栏遮挡内容。
5. 保持哔咔源行为不变，不把本次 JM 优化扩散成全局网络重构。

## 参考实现结论

### 官方 APK `JMComic3v2.0.29`

静态分析记录在 `clone/JMComic3v2.0.29-analysis.md`。该 APK 是 Capacitor WebView 包装的 React/TypeScript Web 应用，不是传统原生客户端。

- `components/Movies/HlsPlayer.tsx` 使用 HTML `<video>`、`hls.js` 和系统原生 HLS 回退。
- 阅读页只保留当前页附近的窗口，图片使用 lazy loading；这证明播放器和网络层应分开处理。
- service worker 使用图片 cache-first 和通用 GET 缓存，但没有 TTL、容量或账户隔离；JoyComic 不直接复制此策略。
- 官方实现没有足够的错误恢复、质量选择或缓冲指标，因此只采纳“直接 HLS + 生命周期日志”的方向。

### `hect0x7/JMComic-APK`

本地副本：`clone/JMComic-APK`。该仓库只通过 `jmcomic` Python 包检查官方 APK 版本并发布下载产物；`main.py` 没有播放器、图床或客户端页面实现。因此它不能作为播放器源码移植来源，但会保留为上游版本观察入口。

### `hect0x7/JMComic-Crawler-Python`

本地副本：`clone/JMComic-Crawler-Python`。该仓库是 `JMComic-APK` 的实际依赖，提供可移植的网络策略参考：

- 移动端 API client 与网页 client 分离，移动端 API 适合低 Cloudflare 风险的请求路径。
- `jm_async_client.py` 支持可配置域名列表、重试次数、超时、异步图片下载和自动更新 API 域名。
- `assets/docs/sources/tutorial/12_domain_strategy.md` 将域名选择作为独立策略，而不是每次请求盲目从头轮询。
- API 与图片缓存、并发下载、失败重试均通过 option 配置控制。

JoyComic 只移植这些抽象：健康状态、冷却、single-flight、请求取消和有限重试；不引入 Python 运行时，不复制其抓取代码，也不绕过 Cloudflare 挑战。

### `clone/joycomic-ios`

- `src/utils/ApiCache.ts` 提供按业务类型设置 TTL 的内存 API cache。
- `src/utils/SourceSelector.ts` 提供 shunt 测速、快速通道和持久化选择。
- `src/utils/fetchImage.ts` 与 `ImageCache.ts` 证明图片应带源所需 headers，并可使用本地缓存。
- `src/screens/MoviesScreen.tsx` 的 `AuthImage` 将受保护图片转为 data URI；其 WebView 播放 fallback 直接打开 `full_url`，缺少请求上下文，不能解决当前 504。

JoyComic 保留 Flutter 侧已有解扰和缓存实现，只吸收 API cache、shunt 偏好和图片 fallback 的行为模型。

### `clone/PicaComic`

- `lib/network/cache_network.dart` 使用磁盘缓存和显式过期时间，适合公开 GET 数据；其缓存策略不能直接用于登录态私有响应。
- `lib/network/jm_network/jm_network.dart` 使用 JM 移动端 API、shunt 和章节/评论解析，是当前 Flutter 项目最接近的同类参考。
- `lib/network/jm_network/jm_image.dart` 保持图片 URL 生成简单，解扰在上层完成；JoyComic 不改变已有 URL 与解扰契约。

## 方案

### 1. 视频直接 HLS 播放

修改 `lib/views/video/video_player_page.dart`：

1. API 返回 `video_src` 后，优先创建原生播放器。
2. 若原生 platform view 尺寸为 `0x0`、初始化失败或超过缓冲启动窗口，创建受控本地 HTML 页面，页面只包含 `<video controls autoplay playsinline>`，`src` 使用 API 返回的 HLS 地址。
3. iOS 依赖 WebKit/AVPlayer 的原生 HLS，不访问 `https://18comic.vip/video/<id>` 作为首个 fallback。
4. 只有直接 HLS WebView 也失败时，才显示明确错误并提供外部浏览器入口。
5. HTML 页面记录 `loadedmetadata`、`canplay`、`playing`、`waiting`、`stalled`、`error` 和 `videoWidth/videoHeight`，通过 WebView JavaScript channel 写入现有日志系统；日志不记录 Cookie、token 或完整私密 URL 查询参数。

这样处理的是当前已确认的链路问题：API 的 HLS 可用，但网页 fallback 受 Cloudflare 上游 `504` 影响。不会加入所谓“指纹混淆”或伪造浏览器身份。

### 2. 禁漫 API 健康状态与请求合并

新增 `lib/network/jm/jm_endpoint_health.dart`，职责只有：

- 为 API host 保存成功时间、连续失败次数、最近失败原因和冷却截止时间。
- 成功 host 置顶；明确的网络/超时/5xx/空响应进入短期冷却；401 和业务错误不把 host 判死。
- 对同一 API 探测建立 single-flight：第一个调用执行探测，其余调用等待同一个 Future。
- GET 请求允许有限的候选 host failover；登录、收藏、评论等有副作用的 POST 继续串行，并且只在网络层判定可重试时切换。
- 冷却时间使用有上限的指数退避，进程内状态不写入凭据存储。

接入点是 `lib/network/jm/jm_network.dart` 的 `_withDomainFailover`、`selectDomain` 和 `_rememberSuccessfulApiHost`。保留现有 `JmState` 的持久化首选域名，健康状态只作为运行期排序和冷却层。

请求缓存只覆盖公开、幂等、短时变化的 GET：详情/设置 2--5 分钟，搜索和列表 30--60 秒；登录态详情、收藏和评论不命中公开缓存。缓存 key 必须包含 source、API host、路径、查询参数和必要的账户隔离标识。

### 3. 禁漫图片 host 健康状态

新增 `lib/network/jm/jm_image_health.dart`，供以下加载入口共享：

- `lib/views/common/widgets/comic_cover.dart`
- `lib/views/reader_v2/image/reader_v2_image_provider.dart`
- `lib/views/reader/utils/reader_image_provider.dart`

行为：最近成功图床优先；明确连接失败、超时、非图片响应进入短期冷却；单个 URL 的并发请求去重；失败后按健康排序尝试候选图床；解扰前后仍使用同一 URL 归一化和现有 isolate。图片连接/接收超时不简单全局缩短，而由 host 冷却避免重复等待。

### 4. 统一底部安全区

新增 `lib/theme/app_safe_area.dart`，提供：

```dart
double bottomContentInset(BuildContext context, {double spacing = AppSpacing.xl}) {
  return MediaQuery.viewPaddingOf(context).bottom + spacing;
}
```

独立页面的 `ListView`/`CustomScrollView` 将其作为 `padding.bottom` 或末尾 `SliverPadding`。已由主底栏统一处理的页面不再叠加第二层 inset。重点覆盖：影视列表和播放器、完整章节、搜索、历史、排行、以图搜图、会员及设置子页。详情页已有的底部安全 padding 继续复用同一 token。

## 数据流

```text
JM 页面请求
  -> JmNetwork
  -> endpoint health 排序 / single-flight / 冷却
  -> Dio request + 现有 headers/token/cookie
  -> Res / 现有解密解析

JM 图片 URL
  -> image health 排序 / URL 去重
  -> 下载缓存
  -> 现有解扰 isolate
  -> reader / cover widget

video_src
  -> native player
  -> 不可渲染时 local HLS HTML WebView
  -> 播放生命周期日志 / 明确错误状态
```

## 错误处理与可观测性

- 日志字段统一包含 source、operation、host、attempt、elapsedMs、status 和 failureClass。
- 绝不记录密码、Cookie、AVS、token 或完整带查询参数的受保护 URL。
- 视频错误区分 API 无地址、原生尺寸为零、manifest 加载失败、媒体解码失败和 WebView 超时。
- JM 全部 host 失败时返回最后一个可诊断错误，同时显示“线路不可用”，不无限重试。
- 用户手动选择的 API/shunt 仍优先，但连续明确失败后允许临时避让，下一次冷却结束再恢复。

## 测试策略

先写失败测试，再实现：

1. `test/jm_endpoint_health_test.dart`：成功置顶、失败冷却、指数退避、同 key single-flight、401 不熔断。
2. `test/jm_image_health_test.dart`：最近成功图床优先、失败跳过、同 URL 去重、全部失败返回诊断错误。
3. `test/video_page_test.dart`：生成的 HTML 包含 HLS URL 和 `playsinline`，原生 `0x0` 后进入 direct-HLS WebView，日志事件被转译且不泄露敏感参数。
4. `test/app_safe_area_test.dart`：底部 inset 使用 view padding，页面基础间距不被系统栏覆盖或重复计算。
5. 运行现有 JM 网络、阅读器、视频和页面 widget 测试，确保解扰、缓存 key、首章入口及哔咔源无回归。

## 验收标准

- API 线路首次失败后，同一时段的并发详情请求不再各自等待完整候选列表。
- 在有效 HLS 且原生 platform view 为 `0x0` 的设备上，direct-HLS WebView 能出现 `loadedmetadata` 或给出可定位的 manifest/media 错误。
- 封面、章节缩略图和阅读器图片在首选图床失败时能自动尝试健康候选，且图片解扰结果不变。
- 影视、章节、搜索、历史、排行、设置等页面最后一项不会被 iPhone 底部操作栏遮挡。
- 定向测试、完整 Flutter 测试、静态分析和 `git diff --check` 全部通过。

## 非目标

- 不复制官方 APK、`joycomic-ios` 或其他仓库的源代码、source map、密钥、Cookie 或内容保护常量。
- 不实现浏览器指纹伪造、Cloudflare 挑战绕过或抓取代理。
- 不重写 PicaComic 阅读器，也不改变哔咔源请求策略。
- 不把所有网络请求盲目改成并发或无限重试。
