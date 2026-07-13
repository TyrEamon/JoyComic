# JoyComic 字体使用说明

## 推荐字体

**LXGW WenKai（霞鹜文楷）** — 开源楷体，适合漫画/小说阅读，文艺感强。

## 启用步骤

### 1. 下载字体文件

从 [GitHub Releases](https://github.com/lxgw/LxgwWenKai/releases/latest) 下载：

| 文件 | 用途 |
|------|------|
| `LXGWWenKai-Regular.ttf` | 常规体（正文） |
| `LXGWWenKai-Bold.ttf` | 粗体（标题） |

放到 `assets/fonts/` 目录下。

### 2. 启用 pubspec 配置

打开 `pubspec.yaml`，取消注释 `fonts:` 段落：

```yaml
flutter:
  fonts:
    - family: LXGWWenKai
      fonts:
        - asset: assets/fonts/LXGWWenKai-Regular.ttf
          weight: 400
        - asset: assets/fonts/LXGWWenKai-Bold.ttf
          weight: 700
```

### 3. 修改代码常量

打开 `lib/theme/app_typography.dart`，将第 16 行改为：

```dart
const String? kFontFamily = 'LXGWWenKai';
```

### 4. 重新编译

```shell
flutter pub get
flutter run
```

## 如何切换其他字体

如需使用其他字体（如 Noto Sans SC）：

1. 将字体文件放入 `assets/fonts/`
2. 修改 `pubspec.yaml` 中的 `family` 名和文件路径
3. 修改 `app_typography.dart` 中的 `kFontFamily` 常量值
