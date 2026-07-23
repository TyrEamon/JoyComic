# iOS FVP 视频后端替换设计

**日期：** 2026-07-23  
**状态：** 用户已确认设计，待书面规格复核  
**范围：** JoyComic 禁漫影视模块的 iOS 播放后端与视频诊断日志

## 背景与证据

禁漫 API 已能返回有效的 HLS 地址，但当前 Flutter `video_player` 的 iOS
后端表现不稳定：

- Texture 渲染路径曾出现声音、进度正常但画面全黑。
- 改用 `VideoViewType.platformView` 后曾恢复画面，但随后真机日志出现
  AVFoundation TLS 初始化失败。
- Direct-HLS WebView 与详情页提取 WebView 均只能作为兜底，无法修复底层
  播放器的渲染或网络适配。
- 同一禁漫视频流程在 `expo-av` 参考实现中播放流畅，说明接口整体可用，
  故障集中在当前 Flutter iOS 播放后端及其适配层。

用户接受 IPA 体积增加，以换取更稳定的视频播放。

## 目标

1. 仅在 iOS 上使用 FVP 的 libmdk/FFmpeg 播放后端，绕开
   `video_player_avfoundation` 的不稳定路径。
2. 保留现有 `video_player` Dart API、播放器 UI、控制栏、全屏、清晰度选择和
   播放进度逻辑，降低迁移风险。
3. Android、macOS、Windows 与 Linux 保持现有官方后端，不扩大变更范围。
4. 保留多级播放兜底，并让每一级失败都有可导出的诊断证据。
5. 确保 Codemagic 能下载、链接并打包 FVP 的 iOS 原生依赖。

## 非目标

- 不重写影视列表、视频详情 API 或 JM 地址解析。
- 不迁移到 `media_kit` 的 Player/Video API。
- 不为 Android 或桌面端切换播放后端。
- 不删除 WebView 或外部浏览器兜底。
- 不声称 Windows 本机测试可以证明 iPhone 真机播放成功。

## 方案选择

### 采用：FVP 接管 iOS `video_player` 后端

将 `fvp` 作为应用直接依赖，在 Flutter binding 初始化后、创建任何视频控制器
之前调用注册函数，并将注册平台限制为 iOS。FVP 继续实现
`VideoPlayerPlatform`，因此现有 `VideoPlayerController` 和 UI 可以复用。

FVP 使用 libmdk/FFmpeg 解封装与解码，并在 iOS 上使用 Metal 渲染。其官方说明
预计每个 CPU 架构增加约 10 MB，具体 IPA 增量以 Codemagic 产物为准。

### 未采用：完整迁移到 media_kit

`media_kit` 也能绕开 AVFoundation 插件，但需要重写播放器状态、控件、全屏、
进度和清晰度逻辑，改动面与回归风险更高。

### 未采用：继续修 video_player_avfoundation

当前后端已经先后暴露 Texture 黑屏、PlatformView 适配与 TLS 初始化问题。继续
叠加特殊处理无法提供稳定性保证。

## 架构与组件

### 1. 后端注册

新增一个可测试的播放后端注册模块，职责仅包括：

- 判断当前目标平台是否为 iOS。
- iOS 调用 FVP 注册，并通过 `platforms: ['ios']` 限定接管范围。
- 非 iOS 不调用 FVP 注册。
- 注册发生在 `WidgetsFlutterBinding.ensureInitialized()` 之后、`runApp()` 以及任何
  `VideoPlayerController` 创建之前。
- 注册成功或失败均写入诊断日志；注册失败不阻止应用启动，播放页仍可进入现有
  WebView 与浏览器兜底。

FVP 版本必须在 `pubspec.yaml` 中固定到实现时验证通过的版本范围，避免
Codemagic 在未审查的版本上自动漂移。

### 2. 原生播放器适配

现有 `NativeVideoPlayer` 继续使用 `VideoPlayerController.networkUrl`。FVP 注册后，
iOS 的控制器由 FVP 的 `VideoPlayerPlatform` 实现处理。

当前 iOS/macOS 共用的 `VideoViewType.platformView` 特殊选择需要拆开：

- iOS 使用 FVP 支持的默认/Texture 渲染路径，不再强制 AVFoundation
  PlatformView。
- macOS 保持现有官方实现和当前视图策略。
- 其他平台保持现状。

不在本次迁移中重写控制栏、手势、播放进度、清晰度选择或全屏方向策略。

### 3. 播放回退状态机

播放顺序保持明确且有界：

```text
JM 视频详情
   ↓
FVP 原生直连 HLS / MP4
   ├─ 成功：显示现有播放器 UI
   └─ 失败：Direct-HLS WebView
                  ├─ 成功：显示网页视频
                  └─ 失败：影视详情页提取 WebView
                                 ├─ 提取到新地址：回到 FVP 原生播放
                                 └─ 失败：错误页 + 浏览器打开
```

已失败的视频地址仍进入 `_failedSources`，防止详情页重复提取相同坏地址造成循环。
所有超时必须有界，页面退出或视频切换时取消旧会话回调。

### 4. 视频诊断日志

新增或调整以下信息：

- 应用启动：`Video backend registered=fvp platform=ios`。
- 非 iOS：应用启动时只记录一次
  `Video backend registered=official platform=<platform>`，播放过程中不重复记录。
- 注册异常：记录异常类型与堆栈，但不包含完整鉴权参数。
- 原生初始化：记录后端名、脱敏后的 host/path、媒体类型、时长、画面尺寸、
  playing/buffering 状态。
- 回退：继续记录 FVP、Direct-HLS、详情页 WebView 各阶段的开始、成功、失败与
  失败原因。

当前导出日志可能被大量漫画图片重试覆盖。日志改造必须确保最近一次视频会话的
关键条目可导出。优先采用独立、容量受限的视频会话快照，与常规轮转日志合并
导出；不得无限增长日志文件，也不得记录完整带 token 的 URL。

## 依赖与 Codemagic 构建

- `fvp` 必须作为应用的直接依赖，满足 Flutter 3.27 及以上的插件注册要求。
- iOS 构建由 CocoaPods 获取并链接 FVP/libmdk 依赖。
- 不启用字幕扩展，因此不额外引入 `ass.framework`。
- 不在 CI 中设置 `FVP_DEPS_LATEST=1`，避免二进制依赖不可复现。
- 若上游提供固定 SDK 下载地址与 SHA-256，后续可单独增加供应链固定；不作为
  本次播放修复的前置条件。
- Codemagic 需至少完成一次无签名或正常签名的 iOS release 构建，证明 Pod 安装、
  framework 链接和架构切片有效。

## 错误处理

- FVP 注册失败：应用继续启动，视频页进入既有 WebView 兜底。
- 控制器初始化失败或上报不可渲染媒体：只触发一次当前源失败回调。
- 视频切换、清晰度切换或页面销毁后，旧控制器事件不得修改新会话状态。
- 所有播放路径失败后显示黑底错误页和“浏览器打开”，不出现纯白屏或永久转圈。
- 外部浏览器打开逻辑保持现状。

## 测试与验收

### 自动化测试

1. 注册策略测试：iOS 注册 FVP，Android、macOS、Windows 与 Linux 不注册。
2. 启动顺序测试：播放后端注册发生在创建播放器之前，并可安全处理注册异常。
3. 控制器配置测试：iOS 不再强制旧 AVFoundation PlatformView；其他平台行为
   保持既有约束。
4. 状态机测试：FVP 初始化失败后依次进入 Direct-HLS、详情页提取与最终错误页。
5. 会话隔离测试：旧控制器失败、旧 WebView 回调和清晰度切换不会污染新会话。
6. 日志测试：导出内容在常规日志被图片错误占满时仍包含最近视频会话关键条目，
   且 URL 查询与片段被脱敏。
7. 运行现有视频、HLS 清晰度、分享和详情页相关回归测试。
8. `flutter analyze` 与 `git diff --check` 通过。

### CI 与真机验收

1. Codemagic iOS release 构建成功，Pod 与原生 framework 正常链接。
2. IPA 安装后进入禁漫影视详情，不默认横屏。
3. 目标视频能够出现画面与声音，进度可推进，播放控制可交互。
4. 全屏按钮能进入和退出横屏全屏。
5. 自动或手动清晰度切换后继续播放。
6. 若播放失败，错误页可用且导出的日志包含完整分段链路。

Windows 本机只能验证 Dart/Flutter 测试、静态分析和依赖解析；第 2 至 6 项必须
由 Codemagic IPA 在 iPhone 真机完成。

## 许可证与发布说明

FVP 本身使用 BSD-3-Clause 许可证。其二进制播放依赖及 FFmpeg 组件的许可证告知
需要在发布前复核，并在应用或随附文档中加入必要的第三方声明。该复核不改变
本设计的技术边界，但属于发布验收项。
