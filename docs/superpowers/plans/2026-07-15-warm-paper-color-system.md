# JoyComic Warm Paper Color System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace JoyComic's pink-purple and cover-derived visual system with the approved accessible Warm Paper + Coral light/dark themes, remove decorative gradients and color hardcoding, and load application version metadata at runtime without changing comic-source behavior.

**Architecture:** `AppColors` becomes the only hexadecimal palette authority; Material `ColorScheme` handles standard roles and a new `AppSemanticColors` `ThemeExtension` handles statuses, image/reader contrast, and shimmer. Widgets consume colors through `ThemeData`, `AppThemeContext`, and centralized `AppGradients`; dynamic `ComicPalette` extraction is deleted because it only affects detail-page decoration. Existing API, database, favorites, history, download, cache, and reader state flows remain unchanged.

**Tech Stack:** Flutter 3.32+, Dart 3.10, Material 3, `ThemeExtension`, `package_info_plus`, `flutter_test`, Provider, and go_router.

---

## File map

**Create:**
- `lib/theme/app_semantic_colors.dart` — non-Material semantic roles.
- `lib/theme/app_gradients.dart` — only allowed image/reader/shimmer gradient definitions.
- `lib/foundation/app_package_info.dart` — runtime package metadata and injectable loader.
- `test/theme_color_system_test.dart` — exact palette and contrast contracts.
- `test/theme_component_test.dart` — flat component contracts.
- `test/theme_source_policy_test.dart` — source-level regression policy.
- `test/detail_theme_test.dart` and `test/reader_theme_test.dart` — focused migrations.

**Delete:**
- `lib/foundation/palette_extractor.dart` — only used by detail decoration.

**Modify:**
- Theme: `lib/theme/app_colors.dart`, `app_theme.dart`, `app_theme_context.dart`, `app_shadows.dart`, `widgets/pill_badge.dart`.
- Pages: common widgets/utilities; home/discovery; login/mine/about/settings; favorites/history/download; detail widgets/view model; reader controls.
- Dependencies/tests: `pubspec.yaml`, `pubspec.lock`, and existing affected widget tests.

---

## Task 1: Build the palette, semantic extension, and allowed gradients

**Files:** Create `lib/theme/app_semantic_colors.dart`, `lib/theme/app_gradients.dart`, `test/theme_color_system_test.dart`; rewrite `lib/theme/app_colors.dart`.

- [ ] **Step 1: Write the failing exact-token and WCAG tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/theme/app_colors.dart';
import 'package:joycomic/theme/app_gradients.dart';
import 'package:joycomic/theme/app_semantic_colors.dart';

void main() {
  test('schemes match approved Warm Paper colors', () {
    expect(AppColors.lightScheme.primary, const Color(0xFFB7463F));
    expect(AppColors.lightBackground, const Color(0xFFF7F5F2));
    expect(AppColors.darkScheme.primary, const Color(0xFFF08A82));
    expect(AppColors.darkBackground, const Color(0xFF111315));
  });

  test('foreground pairs satisfy 4.5 contrast', () {
    const pairs = <(Color, Color)>[
      (Color(0xFF1D1E20), Color(0xFFF7F5F2)),
      (Color(0xFF62666B), Color(0xFFF7F5F2)),
      (Color(0xFFFFFFFF), Color(0xFFB7463F)),
      (Color(0xFFF2F3F4), Color(0xFF111315)),
      (Color(0xFFB7BDC3), Color(0xFF111315)),
      (Color(0xFF3B0B08), Color(0xFFF08A82)),
    ];
    for (final (fg, bg) in pairs) {
      expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5));
    }
  });

  test('only functional gradients are exposed', () {
    expect(AppGradients.imageScrimBottom(AppSemanticColors.light), isA<LinearGradient>());
    expect(AppGradients.readerScrimTop(AppSemanticColors.dark), isA<LinearGradient>());
    expect(AppGradients.shimmer(AppSemanticColors.light), isA<LinearGradient>());
  });
}

double _contrast(Color a, Color b) {
  final al = a.computeLuminance();
  final bl = b.computeLuminance();
  return ((al > bl ? al : bl) + 0.05) / ((al > bl ? bl : al) + 0.05);
}
```

- [ ] **Step 2: Verify the new contracts fail**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/theme_color_system_test.dart
```

Expected: FAIL because `AppSemanticColors`, `AppGradients`, and `AppColors.darkScheme` do not exist.

- [ ] **Step 3: Rewrite `AppColors` as the hex authority**

```dart
class AppColors {
  AppColors._();
  static const lightBackground = Color(0xFFF7F5F2);
  static const darkBackground = Color(0xFF111315);
  static const lightScheme = ColorScheme.light(
    primary: Color(0xFFB7463F), onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFF6DEDA), onPrimaryContainer: Color(0xFF5A1713),
    secondary: Color(0xFF6A5E57), onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEFE4DC), onSecondaryContainer: Color(0xFF2C251F),
    surface: Color(0xFFFFFFFF), onSurface: Color(0xFF1D1E20),
    onSurfaceVariant: Color(0xFF62666B), outline: Color(0xFFC9C3BB),
    outlineVariant: Color(0xFFE1DDD7), error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
  );
  static const darkScheme = ColorScheme.dark(
    primary: Color(0xFFF08A82), onPrimary: Color(0xFF3B0B08),
    primaryContainer: Color(0xFF32110E), onPrimaryContainer: Color(0xFFFFDAD6),
    secondary: Color(0xFFD5C2B7), onSecondary: Color(0xFF392E28),
    secondaryContainer: Color(0xFF51453E), onSecondaryContainer: Color(0xFFF2DED3),
    surface: Color(0xFF191C1F), onSurface: Color(0xFFF2F3F4),
    onSurfaceVariant: Color(0xFFB7BDC3), outline: Color(0xFF60676E),
    outlineVariant: Color(0xFF2E3338), error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
  );
}
```

- [ ] **Step 4: Implement `AppSemanticColors` and `AppGradients`**

`AppSemanticColors` is a const `ThemeExtension` with `copyWith`/`lerp` and these fields: `pageBackground`, `surfaceMuted`, `surfaceRaised`, `success`, `onSuccess`, `warning`, `onWarning`, `info`, `onInfo`, `rating`, `onImage`, `imageScrimStrong`, `imageScrimSoft`, `imageScrimClear`, `readerScrimStrong`, `readerControlForeground`, `readerCanvas`, `shimmerBase`, and `shimmerHighlight`. Add `static AppSemanticColors fallback(Brightness value) => value == Brightness.dark ? dark : light;`.

Use these exact semantic values:

| Field | Light | Dark |
|---|---:|---:|
| pageBackground | `#F7F5F2` | `#111315` |
| surfaceMuted | `#F0EDE8` | `#202428` |
| surfaceRaised | `#E9E5DF` | `#272C31` |
| success / onSuccess | `#2F6B4F` / `#FFFFFF` | `#8BD3AB` / `#0F3322` |
| warning / onWarning | `#8A5A00` / `#FFFFFF` | `#F1C56D` / `#3A2900` |
| info / onInfo | `#3F5F88` / `#FFFFFF` | `#AAC7F0` / `#17314D` |
| rating | `#8A5A00` | `#F1C56D` |
| onImage | `#FFFFFF` | `#FFFFFF` |
| imageScrimStrong / Soft / Clear | `#D9000000` / `#7A000000` / `#00000000` | same |
| readerScrimStrong / Control / Canvas | `#B3000000` / `#FFFFFF` / `#000000` | same |
| shimmerBase / Highlight | `#E8E3DD` / `#F7F4F0` | `#24282C` / `#30363B` |

```dart
class AppGradients {
  AppGradients._();
  static LinearGradient imageScrimBottom(AppSemanticColors c) => LinearGradient(
    begin: Alignment.bottomCenter, end: Alignment.topCenter,
    colors: [c.imageScrimStrong, c.imageScrimSoft, c.imageScrimClear],
  );
  static LinearGradient imageScrimTop(AppSemanticColors c) => LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [c.imageScrimSoft, c.imageScrimClear],
  );
  static LinearGradient readerScrimTop(AppSemanticColors c) => LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [c.readerScrimStrong, c.imageScrimClear],
  );
  static LinearGradient readerScrimBottom(AppSemanticColors c) => LinearGradient(
    begin: Alignment.bottomCenter, end: Alignment.topCenter,
    colors: [c.readerScrimStrong, c.imageScrimClear],
  );
  static LinearGradient shimmer(AppSemanticColors c) => LinearGradient(
    colors: [c.shimmerBase, c.shimmerHighlight, c.shimmerBase],
    stops: const [0.1, 0.5, 0.9],
  );
}
```

- [ ] **Step 5: Run and commit**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/theme_color_system_test.dart
git add lib/theme/app_colors.dart lib/theme/app_semantic_colors.dart lib/theme/app_gradients.dart test/theme_color_system_test.dart
git commit -m "feat: add warm paper semantic palette"
```

Expected: test PASS; commit contains only theme foundation and its test.

---

## Task 2: Wire ThemeData, context access, and neutral shadows

**Files:** Modify `lib/theme/app_theme.dart`, `app_theme_context.dart`, `app_shadows.dart`, `test/theme_color_system_test.dart`, `test/theme_application_test.dart`.

- [ ] **Step 1: Add failing ThemeData integration tests**

```dart
test('AppTheme installs matching semantic extensions', () {
  final light = AppTheme.light();
  final dark = AppTheme.dark();
  expect(light.extension<AppSemanticColors>(), AppSemanticColors.light);
  expect(dark.extension<AppSemanticColors>(), AppSemanticColors.dark);
  expect(light.scaffoldBackgroundColor, const Color(0xFFF7F5F2));
  expect(dark.scaffoldBackgroundColor, const Color(0xFF111315));
  expect(light.progressIndicatorTheme.color, light.colorScheme.primary);
});
```

Add a widget test that reads `context.semanticColors` inside each theme.

- [ ] **Step 2: Verify old ThemeData fails**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/theme_color_system_test.dart test/theme_application_test.dart
```

Expected: FAIL because `AppTheme` still builds pink-purple colors and no extension is installed.

- [ ] **Step 3: Build both themes from scheme + extension**

```dart
static ThemeData dark() => _build(AppColors.darkScheme, AppSemanticColors.dark);
static ThemeData light() => _build(AppColors.lightScheme, AppSemanticColors.light);

static ThemeData _build(ColorScheme scheme, AppSemanticColors semantic) => ThemeData(
  useMaterial3: true,
  brightness: scheme.brightness,
  colorScheme: scheme,
  scaffoldBackgroundColor: semantic.pageBackground,
  canvasColor: semantic.pageBackground,
  extensions: <ThemeExtension<dynamic>>[semantic],
  progressIndicatorTheme: ProgressIndicatorThemeData(
    color: scheme.primary, linearTrackColor: semantic.surfaceRaised,
  ),
  fontFamily: kFontFamily,
  appBarTheme: AppBarTheme(
    backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0,
    foregroundColor: scheme.onSurface,
  ),
  iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
  dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
  cardTheme: CardThemeData(
    color: scheme.surface, elevation: 0, margin: EdgeInsets.zero,
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true, fillColor: semantic.surfaceRaised,
    border: const OutlineInputBorder(
      borderRadius: AppRadius.brMd, borderSide: BorderSide.none,
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: semantic.surfaceRaised,
    contentTextStyle: TextStyle(color: scheme.onSurface),
    behavior: SnackBarBehavior.floating,
  ),
  textSelectionTheme: TextSelectionThemeData(
    cursorColor: scheme.primary,
    selectionColor: scheme.primary.withValues(alpha: 0.28),
    selectionHandleColor: scheme.primary,
  ),
);
```

- [ ] **Step 4: Add context getters and neutral-only shadows**

```dart
AppSemanticColors get semanticColors {
  final value = appTheme.extension<AppSemanticColors>();
  assert(value != null, 'AppSemanticColors must be installed');
  return value ?? AppSemanticColors.fallback(colorScheme.brightness);
}
Color get successColor => semanticColors.success;
Color get warningColor => semanticColors.warning;
Color get infoColor => semanticColors.info;
Color get ratingColor => semanticColors.rating;
Color get onImageColor => semanticColors.onImage;
```

Rewrite cover/card/action-bar shadows with black alpha values only. Delete `pillGlow` and `brandPillGlow`.

- [ ] **Step 5: Run and commit**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/theme_color_system_test.dart test/theme_application_test.dart
git add lib/theme/app_theme.dart lib/theme/app_theme_context.dart lib/theme/app_shadows.dart test/theme_color_system_test.dart test/theme_application_test.dart
git commit -m "refactor: wire semantic light and dark themes"
```

Expected: both tests PASS.

---

## Task 3: Flatten shared badges, cards, states, and login guards

**Files:** Modify `lib/theme/widgets/pill_badge.dart`, `lib/views/common/widgets/rating_stars.dart`, `comic_card.dart`, `comic_grid.dart`, `comic_cover.dart`, `empty_state.dart`, `shimmer.dart`, `lib/views/common/utils/source_login_guard.dart`; create `test/theme_component_test.dart`.

- [ ] **Step 1: Write the failing flat-component test**

```dart
testWidgets('PillBadge uses a flat semantic container', (tester) async {
  final theme = AppTheme.light();
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: const Scaffold(body: PillBadge(label: '热门')),
  ));
  final box = tester.widget<DecoratedBox>(
    find.byKey(const Key('pill-badge-decoration')),
  );
  final decoration = box.decoration as BoxDecoration;
  expect(decoration.gradient, isNull);
  expect(decoration.boxShadow, isNullOrEmpty);
  expect(decoration.color, theme.colorScheme.primaryContainer);
});
```

Add a second test proving source labels still display source text without separate purple/pink values.

- [ ] **Step 2: Verify the old badge fails**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/theme_component_test.dart
```

Expected: FAIL because `PillBadge` defaults to `brandGradient`, glow, and hardcoded white.

- [ ] **Step 3: Replace the badge API and implementation**

```dart
const PillBadge({
  super.key,
  required this.label,
  this.leadingDotColor,
  this.backgroundColor,
  this.foregroundColor,
  this.style,
  this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
});

final background = backgroundColor ?? context.colorScheme.primaryContainer;
final foreground = foregroundColor ?? context.colorScheme.onPrimaryContainer;
```

Remove `Gradient`, `glow`, brand imports, and dot shadows. Set the keyed `DecoratedBox` color to `background`, border to `context.borderColor`, and text/dot to `foreground` or the explicit dot color.

- [ ] **Step 4: Migrate common widgets by semantic role**

```text
rating star       -> context.ratingColor
success state     -> context.successColor
error/delete      -> context.colorScheme.error
source badge      -> surfaceRaised + onSurfaceVariant
image text        -> context.onImageColor
image overlay     -> AppGradients.imageScrimBottom(context.semanticColors)
empty action      -> primary / onPrimary
shimmer           -> AppGradients.shimmer(context.semanticColors)
```

`source_login_guard.dart` must use the dialog's active scheme; no old fixed dark `AppColors` references remain.

- [ ] **Step 5: Run and commit**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/theme_component_test.dart test/theme_application_test.dart
git add lib/theme/widgets/pill_badge.dart lib/views/common test/theme_component_test.dart test/theme_application_test.dart
git commit -m "refactor: flatten shared themed components"
```

Expected: tests PASS.

---

## Task 4: Remove home and carousel decoration gradients

**Files:** Modify `lib/views/home/widgets/home_tool_bar.dart`, `featured_carousel.dart`, `lib/views/home/home_page.dart`, `test/home_content_test.dart`, `test/theme_component_test.dart`.

- [ ] **Step 1: Write the failing toolbar test**

```dart
testWidgets('home tools use one flat icon treatment', (tester) async {
  final theme = AppTheme.light();
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(body: HomeToolBar(entries: [
      ToolEntry(label: '最新', icon: Icons.new_releases_outlined, onTap: () {}),
    ])),
  ));
  final container = tester.widget<Container>(
    find.byKey(const Key('home-tool-icon-最新')),
  );
  final decoration = container.decoration as BoxDecoration;
  expect(decoration.gradient, isNull);
  expect(decoration.boxShadow, isNullOrEmpty);
  expect(decoration.color, theme.colorScheme.primaryContainer);
});
```

- [ ] **Step 2: Verify required old gradient fields fail the test**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/theme_component_test.dart test/home_content_test.dart
```

Expected: FAIL because `gradientStart` and `gradientEnd` are required.

- [ ] **Step 3: Simplify `ToolEntry` and render flat icons**

```dart
class ToolEntry {
  const ToolEntry({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

Container(
  key: Key('home-tool-icon-${entry.label}'),
  width: 48,
  height: 48,
  decoration: BoxDecoration(
    color: context.colorScheme.primaryContainer,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: context.borderColor),
  ),
  child: Icon(entry.icon, color: context.colorScheme.primary),
)
```

Retain all six existing labels, icons, routes, and tap actions.

- [ ] **Step 4: Flatten remaining home decoration**

Replace the carousel error gradient with `surfaceContainerHighest`; replace inline readability gradients with `AppGradients.imageScrimBottom`; replace the title `ShaderMask` with normal `onSurface` text and at most one solid primary accent. Preserve real home sections, loading, retry, and API data.

- [ ] **Step 5: Run and commit**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/home_content_test.dart test/theme_component_test.dart test/theme_application_test.dart
git add lib/views/home test/home_content_test.dart test/theme_component_test.dart test/theme_application_test.dart
git commit -m "refactor: flatten home color treatments"
```

Expected: tests PASS.

---

## Task 5: Load runtime app metadata and flatten identity pages

**Files:** Modify `pubspec.yaml`, `pubspec.lock`, `lib/views/settings/about_page.dart`, `lib/views/auth/login_page.dart`, `lib/views/mine/mine_page.dart`, `test/about_page_test.dart`, `test/mine_page_test.dart`, `test/theme_application_test.dart`; create `lib/foundation/app_package_info.dart`.

- [ ] **Step 1: Write the failing injected-version test**

```dart
const info = AppPackageInfo(
  appName: 'JoyComic Test', version: '9.8.7', buildNumber: '654',
);
await tester.pumpWidget(MaterialApp(
  theme: AppTheme.light(),
  home: AboutPage(packageInfoLoader: () async => info),
));
await tester.pumpAndSettle();
expect(find.text('JoyComic Test'), findsOneWidget);
expect(find.text('版本 9.8.7 (654)'), findsOneWidget);
expect(find.textContaining('0.1.0'), findsNothing);
```

- [ ] **Step 2: Verify the metadata API is missing**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/about_page_test.dart
```

Expected: FAIL because `AppPackageInfo` and `packageInfoLoader` do not exist.

- [ ] **Step 3: Add `package_info_plus` and the injectable abstraction**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' pub add package_info_plus
```

```dart
import 'package:package_info_plus/package_info_plus.dart';

class AppPackageInfo {
  const AppPackageInfo({required this.appName, required this.version, required this.buildNumber});
  final String appName;
  final String version;
  final String buildNumber;
  String get versionLabel => '版本 $version ($buildNumber)';
  String get licenseVersion => '$version+$buildNumber';
}
typedef AppPackageInfoLoader = Future<AppPackageInfo> Function();
Future<AppPackageInfo> loadAppPackageInfo() async {
  final info = await PackageInfo.fromPlatform();
  return AppPackageInfo(
    appName: info.appName.isEmpty ? 'JoyComic' : info.appName,
    version: info.version,
    buildNumber: info.buildNumber,
  );
}
```

- [ ] **Step 4: Convert `AboutPage` to runtime metadata and flat styling**

```dart
const AboutPage({
  super.key,
  this.launchUrl = _launchExternal,
  this.packageInfoLoader = loadAppPackageInfo,
});
```

Load once in `initState` or `FutureBuilder`; use a neutral progress placeholder until loaded. Logo uses `primaryContainer`/`onPrimaryContainer`. Pass loaded values to `showLicensePage`. Keep the GitHub URL as centralized product metadata.

- [ ] **Step 5: Flatten login and mine without changing behavior**

Login source chips use `primaryContainer`; login action uses standard `FilledButton`. Mine account card uses `surface`/`surfaceContainer`, avatar uses `primaryContainer`/`primary`, and stats/accounts remain real. Existing password-non-disclosure and persisted-count tests stay unchanged.

- [ ] **Step 6: Run and commit**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/about_page_test.dart test/mine_page_test.dart test/theme_application_test.dart
git add pubspec.yaml pubspec.lock lib/foundation/app_package_info.dart lib/views/settings/about_page.dart lib/views/auth/login_page.dart lib/views/mine/mine_page.dart test/about_page_test.dart test/mine_page_test.dart test/theme_application_test.dart
git commit -m "refactor: theme identity pages and load app metadata"
```

Expected: tests PASS.

---

## Task 6: Migrate settings, library, and status colors

**Files:** Modify `lib/views/settings/settings_page.dart`, `source_settings_page.dart`, `webdav_settings_page.dart`, `log_viewer_page.dart`, `reader_settings_page.dart`, `lib/views/download/download_page.dart`, `history/history_page.dart`, `favorites/favorites_page.dart`, plus `test/source_settings_page_test.dart`, `reader_settings_page_test.dart`, `webdav_settings_test.dart`, `app_data_test.dart`.

- [ ] **Step 1: Add failing status and reader-preview assertions**

Key each reader mode preview and require a solid decoration:

```dart
final preview = tester.widget<Container>(
  find.byKey(const Key('reader-mode-preview-rightToLeft')),
);
final decoration = preview.decoration as BoxDecoration;
expect(decoration.gradient, isNull);
expect(decoration.color, AppTheme.light().colorScheme.surfaceContainerHighest);
```

In source settings tests, inspect completed latency text and require the installed `AppSemanticColors.success`; failed latency must use `colorScheme.error`.

- [ ] **Step 2: Run settings tests and verify failure**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/source_settings_page_test.dart test/reader_settings_page_test.dart test/webdav_settings_test.dart test/app_data_test.dart
```

Expected: FAIL on the new keys/colors while existing state-persistence assertions remain green.

- [ ] **Step 3: Apply one semantic mapping**

```text
success/complete/fast endpoint -> context.successColor
danger/failure/delete          -> context.colorScheme.error
warning/slow/retrying           -> context.warningColor
informational/in progress       -> context.infoColor or primary
selected                         -> primary / primaryContainer
```

Remove `redAccent`, `orangeAccent`, `hotAccent`, old `AppColors.success`, and hardcoded white button foregrounds. Let Material buttons and progress indicators inherit the theme unless status semantics require an override.

- [ ] **Step 4: Flatten previews and image overlays**

Reader mode previews use `surfaceContainerHighest`, outline, and a primary direction icon. Favorites cover text uses `AppGradients.imageScrimBottom` and `onImageColor`. Preserve cache measurement/clearing, source selection/testing, WebDAV secure storage, downloads, history DB reads, and remote/local favorites merging.

- [ ] **Step 5: Run and commit**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/source_settings_page_test.dart test/reader_settings_page_test.dart test/webdav_settings_test.dart test/app_data_test.dart test/mine_page_test.dart
git add lib/views/settings lib/views/download lib/views/history lib/views/favorites test/source_settings_page_test.dart test/reader_settings_page_test.dart test/webdav_settings_test.dart test/app_data_test.dart test/mine_page_test.dart
git commit -m "refactor: migrate settings and library status colors"
```

Expected: tests PASS.

---

## Task 7: Delete cover palette extraction and flatten detail

**Files:** Delete `lib/foundation/palette_extractor.dart`; modify `lib/views/detail/detail_view_model.dart`, `detail_page.dart`, all files in `lib/views/detail/widgets` currently accepting `ComicPalette`; modify `test/detail_actions_test.dart`, `detail_view_model_favorite_test.dart`; create `test/detail_theme_test.dart`.

- [ ] **Step 1: Write failing palette-free detail tests**

```dart
test('detail implementation has no dynamic palette dependency', () {
  final files = <File>[
    File('lib/views/detail/detail_view_model.dart'),
    File('lib/views/detail/detail_page.dart'),
    ...Directory('lib/views/detail/widgets').listSync().whereType<File>(),
  ];
  for (final file in files) {
    final source = file.readAsStringSync();
    expect(source, isNot(contains('ComicPalette')), reason: file.path);
    expect(source, isNot(contains('PaletteExtractor')), reason: file.path);
    expect(source, isNot(contains('palette.gradient')), reason: file.path);
  }
});
```

Add a view-model test that loads fake `ComicInfoData` and expects `DetailUiData(info: info)` without any palette field, while favorite/comment behavior is unchanged.

- [ ] **Step 2: Verify palette dependencies fail**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/detail_theme_test.dart test/detail_actions_test.dart test/detail_view_model_favorite_test.dart
```

Expected: FAIL because the detail graph still imports and passes `ComicPalette`.

- [ ] **Step 3: Remove extraction from the view model**

```dart
class DetailUiData {
  const DetailUiData({required this.info});
  final ComicInfoData info;
}
```

In `load()`, after `_applyFavoriteState(info)`, assign `DetailUiData(info: info)`, set success, notify, then call `loadComments()` without fetching cover bytes. Keep `coverHeaders`, favorite persistence, comment pagination, errors, and disposal guards unchanged.

- [ ] **Step 4: Remove every palette parameter and map widgets to theme**

```text
HeroHeader           -> cover + centralized image scrims
InfoOverlay          -> primary/rating/onSurface roles
StickyActionBar      -> primary button + semantic favorite state
SynopsisBlock        -> solid surface divider + explicit expand action
ChapterGrid          -> themed selection + image scrim
Recommendation       -> neutral cards + theme text
CommentSection       -> rating/status roles, no decorative gradient
DetailAppBar         -> centralized functional top scrim
```

Update all constructors and `detail_page.dart` call sites in the same commit so no compatibility parameter remains.

- [ ] **Step 5: Delete extractor and verify no references**

```powershell
Remove-Item -LiteralPath 'lib\foundation\palette_extractor.dart'
rg -n "PaletteExtractor|ComicPalette|palette_extractor" lib
```

Expected: no matches. Keep `dio` and `image` dependencies because other production code uses them.

- [ ] **Step 6: Run and commit**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/detail_theme_test.dart test/detail_actions_test.dart test/detail_view_model_favorite_test.dart
git add -A lib/foundation/palette_extractor.dart lib/views/detail test/detail_theme_test.dart test/detail_actions_test.dart test/detail_view_model_favorite_test.dart
git commit -m "refactor: remove cover-derived detail palette"
```

Expected: tests PASS.

---

## Task 8: Centralize reader contrast overlays

**Files:** Modify `lib/views/reader/reader.dart`, `widgets/app_bar.dart`, `bottom.dart`, `menu_lock.dart`, `page_no_tag.dart`, `toast.dart`; create `test/reader_theme_test.dart`; modify `test/reader_preload_test.dart`.

- [ ] **Step 1: Write failing reader semantic assertions**

Pump controls under both app themes. Add `reader-top-scrim` and `reader-bottom-scrim` keys, then assert:

```dart
final semantic = theme.extension<AppSemanticColors>()!;
expect(
  (tester.widget<DecoratedBox>(find.byKey(const Key('reader-top-scrim')))
      .decoration as BoxDecoration).gradient,
  AppGradients.readerScrimTop(semantic),
);
expect(
  tester.widget<Icon>(find.byKey(const Key('reader-back-icon'))).color,
  semantic.readerControlForeground,
);
```

- [ ] **Step 2: Verify inline reader colors fail**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/reader_theme_test.dart test/reader_preload_test.dart
```

Expected: FAIL because controls use inline black gradients and scattered `Colors.white*` values.

- [ ] **Step 3: Replace inline reader colors**

```dart
gradient: AppGradients.readerScrimTop(context.semanticColors)
color: context.semanticColors.readerControlForeground
```

Use `readerScrimBottom` for bottom controls and `semanticColors.readerCanvas` for the comic canvas. Toast chooses foreground based on its actual themed container.

- [ ] **Step 4: Preserve reader state and interactions**

Do not alter vertical/horizontal mode, preload, chapter navigation, zoom, gestures, toolbar auto-hide, menu lock, or page-number settings. Run both reader settings and preload suites.

- [ ] **Step 5: Run and commit**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/reader_theme_test.dart test/reader_preload_test.dart test/reader_settings_page_test.dart
git add lib/views/reader test/reader_theme_test.dart test/reader_preload_test.dart test/reader_settings_page_test.dart
git commit -m "refactor: centralize reader contrast colors"
```

Expected: tests PASS.

---

## Task 9: Flatten search, ranking, category, and remaining discovery states

**Files:** Modify `lib/views/search/search_page.dart`, `temp_search_page.dart`, `lib/views/ranking/ranking_page.dart`, `lib/views/category/category_page.dart`, `lib/views/common/source_content_page.dart`, `lib/views/image_search/image_search_page.dart`, `lib/views/video/video_page.dart`, `test/theme_application_test.dart`, and applicable home/category adapter tests.

- [ ] **Step 1: Add failing selected-state tests**

For search, ranking, and the JM/Picacg category switch, key the selected item and assert:

```dart
expect(selectedDecoration.gradient, isNull);
expect(selectedDecoration.color, theme.colorScheme.primaryContainer);
expect(selectedText.style?.color, theme.colorScheme.onPrimaryContainer);
```

- [ ] **Step 2: Verify old selected gradients fail**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/theme_application_test.dart test/home_content_test.dart
```

Expected: new style assertions FAIL while existing content/API assertions stay green.

- [ ] **Step 3: Replace gradients with Material states**

```dart
color: selected
    ? context.colorScheme.primaryContainer
    : context.colorScheme.surfaceContainerHighest
```

Selected text/icon uses `onPrimaryContainer`; unselected uses `onSurfaceVariant`. Remove search/ranking `LinearGradient` declarations and page-local brand literals.

- [ ] **Step 4: Preserve real dual-source behavior**

Keep JM/Picacg API switching, pagination, retry, merged search, ranking parameters, image search, video routes, and source-content loading unchanged. Existing adapter/content tests are the behavior guard.

- [ ] **Step 5: Run and commit**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/theme_application_test.dart test/home_content_test.dart test/picacg_home_adapter_test.dart
git add lib/views/search lib/views/ranking lib/views/category lib/views/common/source_content_page.dart lib/views/image_search lib/views/video test/theme_application_test.dart test/home_content_test.dart test/picacg_home_adapter_test.dart
git commit -m "refactor: flatten discovery selection states"
```

Expected: tests PASS.

---

## Task 10: Enforce the source policy and clean every remaining color leak

**Files:** Create `test/theme_source_policy_test.dart`; modify every production file it reports; update theme tests only when adding a named semantic role.

- [ ] **Step 1: Write the source-policy test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final files = Directory('lib').listSync(recursive: true)
      .whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

  test('deleted brand and palette APIs cannot return', () {
    final banned = RegExp(
      r'brandPink|brandViolet|brandGradient|gradientStart|gradientEnd|'
      r'ComicPalette|PaletteExtractor|palette_extractor',
    );
    for (final file in files) {
      expect(file.readAsStringSync(), isNot(matches(banned)), reason: file.path);
    }
  });

  test('views contain no hexadecimal design colors', () {
    final hex = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)');
    for (final file in files.where((f) =>
        f.path.contains('lib${Platform.pathSeparator}views'))) {
      expect(file.readAsStringSync(), isNot(matches(hex)), reason: file.path);
    }
  });

  test('gradients are centralized', () {
    for (final file in files) {
      if (file.path.endsWith('app_gradients.dart')) continue;
      expect(file.readAsStringSync(), isNot(contains('LinearGradient(')),
          reason: file.path);
    }
  });
}
```

Add a fourth test banning `Colors.redAccent`, `orangeAccent`, `pink`, `purple`, `black*`, and `white*` inside `lib/views`; `Colors.transparent` remains allowed.

- [ ] **Step 2: Run and collect the finite failure list**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/theme_source_policy_test.dart
```

Expected: FAIL with any migration gaps.

- [ ] **Step 3: Fix each report by role, not allowlist**

```text
design/status color -> ColorScheme or AppSemanticColors
image/reader scrim  -> AppGradients
image foreground    -> onImageColor / readerControlForeground
transparent         -> Colors.transparent (allowed)
```

Do not add broad file exceptions. If a functional gradient geometry is missing, add a named `AppGradients` factory and exact test.

- [ ] **Step 4: Run policy and theme suites**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test test/theme_source_policy_test.dart test/theme_color_system_test.dart test/theme_component_test.dart test/theme_application_test.dart
```

Expected: PASS.

- [ ] **Step 5: Run fast-context architecture audit**

Query:

```text
Find any JoyComic production widget bypassing ThemeData/AppSemanticColors for brand, status, surface, image-overlay, or selected-state colors; find unauthorized gradients, colored glows, and remaining cover palette behavior.
```

Expected: only central theme definitions and approved consumers; no page-local palette architecture.

- [ ] **Step 6: Commit policy and cleanup**

```powershell
git add lib test/theme_source_policy_test.dart test/theme_color_system_test.dart test/theme_component_test.dart test/theme_application_test.dart
git commit -m "test: enforce semantic color source policy"
```

---

## Task 11: Complete verification and integration review

**Files:** Modify only files required by verified failures; review all changes since commit `cf01711`.

- [ ] **Step 1: Format and verify formatting**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\cache\dart-sdk\bin\dart.exe' format lib test
& 'C:\Users\pekilove\development\flutter\bin\cache\dart-sdk\bin\dart.exe' format --output=none --set-exit-if-changed lib test
```

Expected: second command exits 0 with no changed files.

- [ ] **Step 2: Run static analysis**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' analyze
```

Expected: `No issues found!` Resolve all unused imports, deleted-palette references, const errors, and package-info type errors.

- [ ] **Step 3: Run the entire suite**

```powershell
& 'C:\Users\pekilove\development\flutter\bin\flutter.bat' test
```

Expected: all existing and new tests PASS. Record the actual total instead of assuming a count.

- [ ] **Step 4: Run exact source and whitespace audits**

```powershell
rg -n "brandPink|brandViolet|brandGradient|gradientStart|gradientEnd|ComicPalette|PaletteExtractor|palette_extractor" lib
rg -n --glob '*.dart' "Color\(0x|Colors\.(redAccent|orangeAccent|pink|purple)" lib/views
git diff --check
git status --short
```

Expected: no production violations and no whitespace errors. `.superpowers/` may remain untracked but must never be staged.

- [ ] **Step 5: Run final fast-context semantic review**

```text
Review the completed JoyComic Warm Paper + Coral migration. Verify all light/dark colors flow AppColors -> ColorScheme/AppSemanticColors -> ThemeData -> BuildContext; icons have no gradients; only centralized image/reader scrims and neutral shimmer remain; about version is runtime metadata; real category/favorites/history/download/cache behavior is untouched.
```

Expected: no architecture leak or functional placeholder. Resolve concrete findings and rerun Tasks 10–11 checks.

- [ ] **Step 6: Review diff and make an integration commit only if needed**

```powershell
git diff cf01711 --stat
git diff cf01711 -- lib test pubspec.yaml pubspec.lock
git status --short
git add lib test pubspec.yaml pubspec.lock
git diff --cached --check
git commit -m "feat: complete warm paper theme migration"
```

If the index is empty because all work is already committed, do not create an empty commit.

- [ ] **Step 7: Stop before remote push**

Report exact analyze output, actual passed test count, semantic/hardcoding audit result, commits created, and remaining untracked preview directory. Do not run `git push` until the user explicitly asks; when requested, push exactly once.
