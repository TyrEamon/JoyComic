# JoyComic

JoyComic 是一款使用 Flutter 构建的 iOS 漫画阅读器，聚合哔咔与禁漫两个内容源，提供搜索、分类、收藏、下载、阅读记录和多模式阅读体验。

当前稳定版本：`1.0.0`

> JoyComic 不提供、存储或分发漫画资源。应用仅作为第三方客户端连接用户选择的内容服务，内容版权归原作者及对应平台所有。请遵守所在地法律法规及内容服务的使用条款。

## 功能

- 双源浏览：支持哔咔与禁漫，禁漫普通内容可匿名浏览，账号用于云端收藏等个性化功能。
- 内容发现：首页推荐、分类、排行、搜索、以图搜图和相关推荐。
- 漫画详情：章节列表、收藏、评论、点赞、分享及阅读进度恢复。
- 五种阅读模式：纵向连续、单页左右翻页、双页左右翻页，并支持缩放、预加载和章节切换。
- 图片处理：支持禁漫图片解扰、多图床回退、缓存及失败重试。
- 离线阅读：章节下载队列、暂停与恢复、任务持久化和本地阅读。
- 数据管理：本地收藏、阅读历史、搜索历史以及 WebDAV 备份与恢复。
- 媒体与诊断：禁漫视频播放、清晰度选择、运行日志查看与导出。
- iOS 适配：安全区域、横竖屏阅读布局及无签名 IPA 云端构建配置。

## 登录说明

| 内容源 | 普通浏览 | 账号能力 |
| --- | --- | --- |
| 禁漫 | 无需登录 | 云端收藏、收藏同步等账号功能 |
| 哔咔 | 需要登录 | 内容浏览、收藏、评论及账号资料 |

登录或退出后，首页、分类页、分类内容页和收藏页会自动刷新对应内容源的状态。

## 技术栈

- Flutter / Dart
- Dio、CookieJar、Crypto、PointyCastle
- SQLite、SharedPreferences、Flutter Secure Storage
- Provider、GoRouter
- `cached_network_image_ce`、PhotoView、`video_player`

网络签名、图片解扰、离线归档与数据同步均由 Dart/Flutter 代码完成，iOS 工程可在 CI 构建时生成。

## 本地开发

环境要求：

- Flutter `3.32.0` 或更高版本
- Dart `3.10.0` 或更高版本
- 构建 iOS 应用时需要 macOS 与 Xcode

```shell
flutter pub get
flutter test
flutter run
```

运行静态分析：

```shell
flutter analyze
```

## 构建 iOS

本地 macOS 构建：

```shell
flutter create . --platforms=ios
flutter pub get
dart run flutter_launcher_icons
flutter build ios --release --no-codesign
```

仓库中的 `codemagic.yaml` 提供无签名 IPA 构建流程，可在 Codemagic 连接仓库后运行 `Build IPA` 工作流。生成的 IPA 仍需使用合法证书签名后才能安装到 iOS 设备。

## 项目结构

```text
lib/
  comic_source/   内容源契约与内置源
  network/        API、鉴权、解析与媒体链路
  database/       收藏、历史与下载数据
  foundation/     下载、同步、缓存和诊断服务
  views/          页面、阅读器与播放器
  theme/          主题与响应式界面规范
test/             单元测试与组件测试
```

## 安全与隐私

- 账号凭据通过系统安全存储保存，不写入普通配置文件。
- 日志会对账号、密码、会话及敏感请求信息进行脱敏。
- WebDAV 配置与备份由用户自行提供和管理。
- 请勿在 Issue、日志或截图中公开账号凭据、会话令牌或私人服务器地址。

## 交流

[学AI，上L站](https://linux.do)

## 声明

本项目仅供学习、研究与个人使用。使用者应自行判断内容来源的合法性，并承担使用本软件产生的全部责任。项目名称、图标与第三方平台名称不代表任何官方合作或授权关系。
