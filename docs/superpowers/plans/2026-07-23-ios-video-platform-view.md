# iOS Video PlatformView Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make iOS JM HLS video frames visible by selecting the native PlatformView backend while preserving current playback fallbacks and diagnostics.

**Architecture:** Keep `NativeVideoPlayer` as the single playback widget. Add two pure helpers: one selects `VideoViewType` by target platform, and one constructs the controller with that selection. The iOS/macOS path uses `platformView` (native `AVPlayerLayer`); other platforms keep `textureView`. Initialization logs non-sensitive media state before playback, and existing failure callbacks remain unchanged.

**Tech Stack:** Flutter/Dart, `video_player 2.13.0`, `flutter_test`, existing `Log` facade.

---

### Task 1: Lock platform selection and controller construction with tests

**Files:**
- Modify: `test/video_page_test.dart`
- Test target: pure helpers exported from `lib/views/video/video_player_page.dart`

- [ ] **Step 1: Write the failing tests**

Add these tests near the existing native-player tests:

```dart
  test('iOS and macOS select the native platform view backend', () {
    expect(nativeVideoViewType(TargetPlatform.iOS), VideoViewType.platformView);
    expect(
      nativeVideoViewType(TargetPlatform.macOS),
      VideoViewType.platformView,
    );
  });

  test('non-Apple targets retain the texture backend', () {
    expect(
      nativeVideoViewType(TargetPlatform.android),
      VideoViewType.textureView,
    );
    expect(
      nativeVideoViewType(TargetPlatform.windows),
      VideoViewType.textureView,
    );
  });

  test('native controller uses the selected view type', () {
    final controller = createNativeVideoController(
      'https://18comic.vip/video/test.m3u8',
      platform: TargetPlatform.iOS,
    );
    addTearDown(controller.dispose);
    expect(controller.viewType, VideoViewType.platformView);
  });
```

- [ ] **Step 2: Run the focused tests to verify RED**

Run:

```powershell
flutter test --no-pub test/video_page_test.dart --plain-name "platform view"
```

Expected: compilation failure because `nativeVideoViewType` and `createNativeVideoController` do not exist yet.

### Task 2: Implement the minimal PlatformView selection

**Files:**
- Modify: `lib/views/video/video_player_page.dart:500-540` (helpers before `NativeVideoPlayer`)
- Modify: `lib/views/video/video_player_page.dart:550-620` (controller creation and source updates)

- [ ] **Step 1: Add the pure selection helper**

```dart
VideoViewType nativeVideoViewType(TargetPlatform platform) {
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return VideoViewType.platformView;
  }
  return VideoViewType.textureView;
}
```

- [ ] **Step 2: Add one controller factory and use it in both lifecycle paths**

```dart
VideoPlayerController createNativeVideoController(
  String source, {
  TargetPlatform? platform,
}) {
  final target = platform ?? defaultTargetPlatform;
  return VideoPlayerController.networkUrl(
    Uri.parse(source),
    viewType: nativeVideoViewType(target),
  );
}
```

In `initState` and `didUpdateWidget`, replace direct `VideoPlayerController.networkUrl(...)` construction with `createNativeVideoController(widget.source)` and retain the existing listener registration and disposal order.

- [ ] **Step 3: Run the new tests to verify GREEN**

Run:

```powershell
flutter test --no-pub test/video_page_test.dart --plain-name "platform view"
```

Expected: all three new tests pass.

### Task 3: Add media-state diagnostics without changing playback behavior

**Files:**
- Modify: `lib/views/video/video_player_page.dart:585-635`
- Modify: `test/video_page_test.dart`

- [ ] **Step 1: Add an assertion for the diagnostic formatter**

Expose a pure formatter so tests do not require an iOS channel:

```dart
String describeNativeVideoState(
  VideoPlayerValue value, {
  required VideoViewType viewType,
}) {
  final size = value.size;
  return 'view=${viewType.name} size=${size.width}x${size.height} '
      'aspect=${value.aspectRatio} duration=${value.duration.inMilliseconds}ms '
      'playing=${value.isPlaying} buffering=${value.isBuffering}';
}
```

Test it with a `VideoPlayerValue` whose duration is nonzero and assert the output contains `view=platformView`, `size=`, `aspect=`, `duration=`, and `playing=`.

- [ ] **Step 2: Log initialization state before calling `play()`**

Immediately after `await controller.initialize()` and generation validation, add:

```dart
      Log.i(
        'Video native initialized',
        describeNativeVideoState(
          controller.value,
          viewType: nativeVideoViewType(defaultTargetPlatform),
        ),
      );
```

Keep the existing `Video native playing`, controller-error, and initialization-exception logs. Do not log query strings or signed URL tokens.

- [ ] **Step 3: Run all video tests**

Run:

```powershell
flutter test --no-pub test/jm_video_test.dart test/video_page_test.dart
```

Expected: all tests pass, including existing WebView fallback and stale-generation cases.

### Task 4: Regression verification and handoff

**Files:**
- No additional production files.

- [ ] **Step 1: Run reader and route regressions**

```powershell
flutter test --no-pub test/reader_v2_image_test.dart test/reader_v2_viewport_test.dart test/reader_v2_route_test.dart
```

- [ ] **Step 2: Run focused static analysis and whitespace checks**

```powershell
flutter analyze --no-pub lib/views/video/video_player_page.dart test/video_page_test.dart
git diff --check
```

Expected: no issues and exit code 0. Full repository analysis may retain unrelated pre-existing info-level lints documented in the handoff.

- [ ] **Step 3: Review the diff and commit**

```powershell
git add lib/views/video/video_player_page.dart test/video_page_test.dart
git commit -m "fix: render iOS JM video with platform view"
```

- [ ] **Step 4: Push after verification**

```powershell
git push origin HEAD:main
```

After the IPA is tested, inspect the exported log for `Video native initialized` and confirm whether `size` is nonzero. If PlatformView still renders black with a nonzero size, create a separate codec/HLS investigation; do not combine it with this change.
