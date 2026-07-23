# iOS 视频 PlatformView 渲染修复设计

**日期：** 2026-07-23  
**状态：** 已确认方案，待规格复核后实现  
**范围：** `VideoPlayerPage` 原生视频显示层

## 背景与根因证据

最新诊断日志 `joycomic_logs_1784776809345.txt` 显示：

- JM API 返回了有效的 HLS `index.m3u8` 地址。
- `direct=true`，说明地址校验已经通过。
- `Video native playing`，说明 AVPlayer 初始化、音频播放和时间进度都正常。
- 真机截图表现为有声音、进度条推进、画面区域全黑，没有控制器错误日志。

当前 Flutter `video_player` 默认使用 TextureView。该路径需要把 iOS 的视频像素帧复制到 Flutter texture；音频正常但画面黑屏符合纹理帧没有呈现的症状。`video_player 2.13.0` 同时提供 `VideoViewType.platformView`，可直接使用 iOS 原生 `AVPlayerLayer`。

## 目标

1. iOS 原生视频使用 PlatformView 绘制，绕过当前黑屏的 Texture 渲染路径。
2. Android 和其他平台保持现有 Texture 默认行为。
3. 保留现有播放控制、进度条、全屏、失败回退到 WebView 和外部浏览器入口。
4. 日志能区分“源加载成功”“视频轨尺寸/时长”“渲染视图类型”“控制器错误”。
5. 不改变 HLS 地址解析、JM 域名安全策略和 WebView 抽取逻辑。

## 非目标

- 本轮不更换播放器包，不重写 HLS 请求，不实现视频代理。
- 本轮不修改 JM 漫画搜索、图片解扰、缓存或域名测速。
- 若 PlatformView 后仍无画面，再依据新增的尺寸/轨道日志单独判断编码兼容性；不在本轮猜测性加入转码或代理。

## 设计

### 1. 渲染类型选择

新增一个纯 Dart 的选择函数：

- `TargetPlatform.iOS` / `TargetPlatform.macOS` → `VideoViewType.platformView`
- 其他平台 → `VideoViewType.textureView`

`NativeVideoPlayer` 创建 `VideoPlayerController.networkUrl` 时显式传入该类型。控制器更新源时复用同一选择策略。

### 2. 诊断日志

在 `initialize()` 成功后记录以下非敏感字段：

- URI 的 host/path（不记录 query/token）
- `viewType`
- `value.size` 与 `aspectRatio`
- `duration`
- `isPlaying`、`isBuffering`

控制器 `hasError` 或初始化异常时记录错误描述和堆栈，并保留现有 WebView 回退。

### 3. 布局与交互

继续使用现有 `AspectRatio` 和 `VideoProgressIndicator`。PlatformView 只替换视频画面的承载方式，不改变顶部标题、底部控制栏、方向切换和按钮行为。

### 4. 测试

先写失败测试，再实现：

- iOS 选择 `VideoViewType.platformView`。
- Android/其他平台选择 `VideoViewType.textureView`。
- 网络控制器构造确实使用选择结果。
- 现有原生失败 → WebView 回退测试继续通过。
- 现有 JM 视频模型、路由和播放器相关测试无回归。

## 风险与回退

- PlatformView 可能在部分 Flutter/iOS 版本上有合成层限制；若初始化或播放失败，现有 `onFailure` 会切换 WebView。
- PlatformView 仍黑屏时，日志中的 `size=0x0` 或错误描述可区分“无视频轨/编码不支持”；非零尺寸但黑屏则继续调查 iOS 合成层。
- 不在 UI 层伪造画面或隐藏错误；所有失败都保留可导出的诊断日志。

## 验收标准

- 在同一条 JM HLS 地址上，iOS IPA 中可看到视频画面，同时音频和进度继续正常。
- Android 行为与本轮前一致。
- 定向测试、静态分析和差异检查通过。
- 真机仍失败时，日志至少能明确指出是初始化错误、视频尺寸为零、缓冲问题还是渲染层问题。
