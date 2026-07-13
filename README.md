# JoyComic

哔咔 & 禁漫双源 iOS 漫画阅读器。

> 本项目为学习与个人使用目的的第三方客户端，仅与第三方漫画站点交互，
> 不提供任何漫画资源。资源版权归原作者及平台所有，请于下载后合理期间删除。
> 使用本软件产生的一切后果由使用者自行承担。

## 当前状态：全部阶段完成 ✅

| 阶段 | 内容 | 状态 |
|------|------|:----:|
| 1 | 脚手架 + 核心架构（多源契约、网络层、加密命脉） | ✅ |
| 1.5 | 双源配置补全（JM 6 图片源 + Pica 双源切换） | ✅ |
| 2 | 阅读器（5 模式 / 预加载 / 缩放） | ✅ |
| 3 | UI 页面 + 功能集成（16 页面 + 8 组功能 + 日志系统） | ✅ |
| 4 | 本地 DB + 下载管理器 + WebDAV 同步 | ✅ |
| 5 | 质量审计 + 亮色主题 + 霞鹜文楷字体 | ✅ |
| 6 | 云端 iOS CI（Codemagic） | ✅ 配置完成 |

## 技术栈

纯 Dart / Flutter，不引入额外 native 语言。理由：网络加解密本就纯 Dart 可完成，
离线归档用 `archive` + `pdf` 纯 Dart 包替代，避免增加 iOS 原生链接与 CI 复杂度。

## 编译方式（Windows 开发机无法编 iOS）

iOS 包须在 macOS 环境产出。方式是在 [Codemagic.io](https://codemagic.io) 连接本仓库，
`codemagic.yaml` 已配置好，首次 CI 运行会自动执行：

1. `flutter create . --platforms=ios` — 生成 iOS 工程
2. `dart run flutter_launcher_icons` — 生成应用图标
3. `flutter build ios --release --no-codesign` — 构建无签名 IPA
4. 打包 `joycomic-*.ipa` 产物

## 应用图标

`assets/app.jpg` 为题图照片，运行 `dart run flutter_launcher_icons` 可自动生成
iOS 各尺寸图标（已配置 `pubspec.yaml` 的 `flutter_launcher_icons` 段）。

## 可选字体

内置霞鹜文楷（LXGW WenKai）字体，启用后需运行 `flutter pub get`。

## 测试

```shell
flutter test test/crypto_logic_test.dart
```
