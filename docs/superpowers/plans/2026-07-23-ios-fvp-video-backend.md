# iOS FVP Video Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace JoyComic's iOS `video_player_avfoundation` playback backend with FVP while preserving the existing video UI, quality selection, fullscreen behavior, bounded fallbacks, and actionable diagnostics.

**Architecture:** Add FVP as a direct dependency and register it only for iOS before any video controller is created. Keep `VideoPlayerController` as the application-facing API, use FVP's texture/Metal renderer on iOS, preserve official backends elsewhere, and retain the current Direct-HLS/WebView/browser fallback chain. Add a bounded in-memory video diagnostic snapshot that is merged into exports so reader-image noise cannot erase the latest video failure evidence.

**Tech Stack:** Flutter/Dart, `video_player` 2.13, `fvp` 0.37.3, libmdk/FFmpeg, CocoaPods, flutter_test, Codemagic iOS release build.

**Design:** `docs/superpowers/specs/2026-07-23-ios-fvp-video-backend-design.md`

**Execution ownership:** Grok implements and runs checks but must not commit or push. Codex reviews each resulting diff, runs independent verification, and owns the final commit and push.

---

## File Structure

- Create `lib/foundation/video_backend.dart`: platform selection, FVP registration, startup logging, and injectable registrar for tests.
- Create `test/video_backend_test.dart`: iOS-only registration, non-iOS preservation, registration failure, and startup ordering contracts.
- Modify `lib/main.dart`: initialize logging, then register the selected video backend before application services and `runApp`.
- Modify `pubspec.yaml` and `pubspec.lock`: add exact direct dependency `fvp: 0.37.3`.
- Modify `lib/views/video/video_player_page.dart`: stop forcing AVFoundation PlatformView on iOS while preserving macOS and non-Apple behavior.
- Modify `test/video_page_test.dart`: lock the FVP-compatible iOS texture view and existing platform choices.
- Modify `lib/foundation/log.dart`: maintain an 80-entry bounded video snapshot and merge it into normal log reads/exports.
- Modify `test/log_export_test.dart`: verify bounded retention, deduplication, chronological export, and survival amid reader noise.
- Create `THIRD_PARTY_NOTICES.md`: record FVP's BSD-3-Clause notice and libmdk distribution terms used by FVP.
- Inspect `codemagic.yaml`: no change is expected; modify it only if dependency resolution proves a concrete iOS build prerequisite.

---

### Task 1: Add the FVP Dependency and Platform Registration Boundary

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/foundation/video_backend.dart`
- Create: `test/video_backend_test.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Add FVP as an exact direct dependency**

In `pubspec.yaml`, place FVP beside `video_player`:

```yaml
  fvp: 0.37.3
  video_player: ^2.13.0
```

Run:

```powershell
flutter pub get
```

Expected: exit code 0, `pubspec.lock` contains `fvp` version `0.37.3`, and `video_player` remains available.

- [ ] **Step 2: Write failing backend-selection tests**

Create `test/video_backend_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/foundation/video_backend.dart';

void main() {
  test('iOS selects and registers FVP only for iOS', () {
    dynamic receivedOptions;

    final backend = registerVideoBackend(
      platform: TargetPlatform.iOS,
      registrar: ({dynamic options}) => receivedOptions = options,
    );

    expect(backend, VideoBackend.fvp);
    expect(receivedOptions, <String, dynamic>{
      'platforms': <String>['ios'],
    });
  });

  test('non-iOS platforms retain the official backend', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.android,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      var registerCalls = 0;
      final backend = registerVideoBackend(
        platform: platform,
        registrar: ({dynamic options}) => registerCalls++,
      );

      expect(backend, VideoBackend.official, reason: platform.name);
      expect(registerCalls, 0, reason: platform.name);
    }
  });

  test('FVP registration failure preserves the official backend', () {
    final backend = registerVideoBackend(
      platform: TargetPlatform.iOS,
      registrar: ({dynamic options}) => throw StateError('register failed'),
    );

    expect(backend, VideoBackend.official);
  });

  test('main initializes logging before video backend registration', () {
    final source = File('lib/main.dart').readAsStringSync();
    final logIndex = source.indexOf('await Log.initialize();');
    final backendIndex = source.indexOf('registerVideoBackend();');

    expect(logIndex, greaterThanOrEqualTo(0));
    expect(backendIndex, greaterThan(logIndex));
    expect(backendIndex, lessThan(source.indexOf('runApp(')));
  });
}
```

- [ ] **Step 3: Run the test and verify RED**

Run:

```powershell
flutter test -r compact test/video_backend_test.dart
```

Expected: FAIL because `foundation/video_backend.dart`, `VideoBackend`, and `registerVideoBackend` do not exist.

- [ ] **Step 4: Implement the registration module**

Create `lib/foundation/video_backend.dart`:

```dart
/// Selects and registers the process-wide video_player backend.
library;

import 'package:flutter/foundation.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'log.dart';

enum VideoBackend { official, fvp }

typedef FvpRegistrar = void Function({dynamic options});

VideoBackend registerVideoBackend({
  TargetPlatform? platform,
  FvpRegistrar? registrar,
}) {
  final target = platform ?? defaultTargetPlatform;
  if (target != TargetPlatform.iOS) {
    Log.i(
      'Video backend registered=official platform=${target.name}',
    );
    return VideoBackend.official;
  }

  try {
    final register = registrar ?? fvp.registerWith;
    register(
      options: <String, dynamic>{
        'platforms': <String>['ios'],
      },
    );
    Log.i('Video backend registered=fvp platform=ios');
    return VideoBackend.fvp;
  } catch (error, stackTrace) {
    Log.e(
      'Video backend registration failed platform=ios fallback=official',
      error: error.runtimeType,
      stackTrace: stackTrace,
    );
    return VideoBackend.official;
  }
}
```

Do not add decoder tuning, low-latency settings, certificate bypasses, or global FVP options in this task. The smallest registration contract is `platforms: ['ios']`.

- [ ] **Step 5: Integrate registration into startup**

Add the import in `lib/main.dart`:

```dart
import 'foundation/video_backend.dart';
```

Change the opening of `main()` so logging exists before the one-time backend diagnostic:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Log.initialize();
  registerVideoBackend();
  // Existing image-cache configuration remains here.
```

Remove the old later `await Log.initialize();` call so initialization occurs exactly once. Preserve every other startup operation and its relative order.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```powershell
flutter test -r compact test/video_backend_test.dart
flutter analyze lib/foundation/video_backend.dart lib/main.dart test/video_backend_test.dart
```

Expected: all backend tests pass and analyze reports `No issues found`.

- [ ] **Step 7: Stop for Codex review**

Report the changed files and command results. Do not commit or push.

---

### Task 2: Use the FVP-Compatible iOS Render Path

**Files:**
- Modify: `test/video_page_test.dart`
- Modify: `lib/views/video/video_player_page.dart`

- [ ] **Step 1: Change the platform-view tests first**

Replace the existing iOS/macOS test and update the controller assertion:

```dart
  test('iOS uses FVP texture while macOS keeps the platform view', () {
    expect(nativeVideoViewType(TargetPlatform.iOS), VideoViewType.textureView);
    expect(
      nativeVideoViewType(TargetPlatform.macOS),
      VideoViewType.platformView,
    );
  });

  test('native controller uses the selected view type', () {
    final controller = createNativeVideoController(
      'https://18comic.vip/video/test.m3u8',
      platform: TargetPlatform.iOS,
    );
    addTearDown(controller.dispose);
    expect(controller.viewType, VideoViewType.textureView);
  });
```

Keep the existing Android and Windows texture assertions.

- [ ] **Step 2: Run the targeted tests and verify RED**

Run:

```powershell
flutter test -r compact test/video_page_test.dart --plain-name "iOS uses FVP texture while macOS keeps the platform view"
```

Expected: FAIL because iOS still returns `VideoViewType.platformView`.

- [ ] **Step 3: Implement the minimal view-type change**

Replace `nativeVideoViewType` with:

```dart
VideoViewType nativeVideoViewType(TargetPlatform platform) {
  if (platform == TargetPlatform.macOS) {
    return VideoViewType.platformView;
  }
  return VideoViewType.textureView;
}
```

Do not modify `NativeVideoPlayer`, fullscreen controls, quality selection, controller lifecycle, Direct-HLS, or WebView fallback logic.

- [ ] **Step 4: Run the full video page test and verify GREEN**

Run:

```powershell
flutter test -r compact test/video_page_test.dart
flutter analyze lib/views/video/video_player_page.dart test/video_page_test.dart
```

Expected: all `video_page_test.dart` tests pass and analyze reports no issues.

- [ ] **Step 5: Stop for Codex review**

Report the exact one-function production diff and test results. Do not commit or push.

---

### Task 3: Preserve the Latest Video Diagnostics During Export

**Files:**
- Modify: `test/log_export_test.dart`
- Modify: `lib/foundation/log.dart`

- [ ] **Step 1: Write failing bounded-retention and merge tests**

Append these tests inside `main()` in `test/log_export_test.dart`:

```dart
  test('bounded diagnostics retain only the newest entries', () {
    final entries = <JoyLogEntry>[];
    for (var index = 0; index < 5; index++) {
      appendBoundedDiagnosticEntry(
        entries,
        JoyLogEntry(
          level: 'info',
          message: 'Video event $index',
          time: '2026-07-23 22:00:0$index',
        ),
        maxEntries: 3,
      );
    }

    expect(entries.map((entry) => entry.message), <String>[
      'Video event 2',
      'Video event 3',
      'Video event 4',
    ]);
  });

  test('video diagnostics survive noisy persisted logs without duplicates', () {
    final persisted = <JoyLogEntry>[
      for (var index = 0; index < 62; index++)
        JoyLogEntry(
          level: 'warning',
          message: 'Reader image candidate failed $index',
          time: '2026-07-23 22:56:${index.toString().padLeft(2, '0')}',
        ),
    ];
    const videoEntry = JoyLogEntry(
      level: 'error',
      message: 'Video native initialization failed',
      error: 'host=cdn.example status=tls',
      time: '2026-07-23 22:51:00',
    );

    final merged = mergeDiagnosticLogs(
      persisted,
      const <JoyLogEntry>[videoEntry, videoEntry],
    );

    expect(
      merged.where((entry) => entry.message.startsWith('Video ')),
      hasLength(1),
    );
    expect(merged.first.message, 'Video native initialization failed');
    expect(merged, hasLength(63));
  });
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```powershell
flutter test -r compact test/log_export_test.dart
```

Expected: FAIL because `appendBoundedDiagnosticEntry` and `mergeDiagnosticLogs` do not exist.

- [ ] **Step 3: Add pure bounded-buffer and merge helpers**

Add these top-level functions after `JoyLogEntry` in `lib/foundation/log.dart`:

```dart
void appendBoundedDiagnosticEntry(
  List<JoyLogEntry> entries,
  JoyLogEntry entry, {
  int maxEntries = 80,
}) {
  if (maxEntries <= 0) {
    entries.clear();
    return;
  }
  entries.add(entry);
  final overflow = entries.length - maxEntries;
  if (overflow > 0) entries.removeRange(0, overflow);
}

List<JoyLogEntry> mergeDiagnosticLogs(
  Iterable<JoyLogEntry> persisted,
  Iterable<JoyLogEntry> videoSnapshot,
) {
  final unique = <String, JoyLogEntry>{};
  for (final entry in <JoyLogEntry>[...persisted, ...videoSnapshot]) {
    final key = jsonEncode(<Object?>[
      entry.time,
      entry.level,
      entry.message,
      entry.error,
      entry.stackTrace,
    ]);
    unique.putIfAbsent(key, () => entry);
  }
  final merged = unique.values.toList(growable: false)
    ..sort((left, right) => left.time.compareTo(right.time));
  return List<JoyLogEntry>.unmodifiable(merged);
}
```

- [ ] **Step 4: Capture video-prefixed log entries in memory**

Inside `Log`, add:

```dart
  static const int _maxVideoDiagnosticEntries = 80;
  static final List<JoyLogEntry> _videoDiagnostics = <JoyLogEntry>[];

  static String _timestamp() =>
      Jiffy.now().format(pattern: 'yyyy-MM-dd HH:mm:ss');

  static String _messageWithData(String message, dynamic data) =>
      '$message${data != null ? '\n$data' : ''}';

  static void _captureVideoDiagnostic(
    String level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (!message.startsWith('Video ')) return;
    appendBoundedDiagnosticEntry(
      _videoDiagnostics,
      JoyLogEntry(
        level: level,
        message: message,
        error: error?.toString(),
        stackTrace: stackTrace?.toString(),
        time: _timestamp(),
      ),
      maxEntries: _maxVideoDiagnosticEntries,
    );
  }
```

Replace the `d`, `i`, `w`, `e`, and `f` expression-bodied methods with block bodies. `i`, `w`, `e`, and `f` must call `_captureVideoDiagnostic`; `d` remains uncaptured in release diagnostics. Use these exact shapes:

```dart
  static void d(String message, [dynamic data]) {
    _logger.d(_messageWithData(message, data));
  }

  static void i(String message, [dynamic data]) {
    final text = _messageWithData(message, data);
    _captureVideoDiagnostic('info', text);
    _logger.i(text);
  }

  static void w(String message, {Object? error, StackTrace? stackTrace}) {
    _captureVideoDiagnostic(
      'warning',
      message,
      error: error,
      stackTrace: stackTrace,
    );
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  static void e(String message, {Object? error, StackTrace? stackTrace}) {
    _captureVideoDiagnostic(
      'error',
      message,
      error: error,
      stackTrace: stackTrace,
    );
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  static void f(String message, {Object? error, StackTrace? stackTrace}) {
    _captureVideoDiagnostic(
      'fatal',
      message,
      error: error,
      stackTrace: stackTrace,
    );
    _logger.f(message, error: error, stackTrace: stackTrace);
  }
```

Keep `t` unchanged because it accepts an explicit timestamp and is not used by the video path.

- [ ] **Step 5: Merge the snapshot into log reads and clear it explicitly**

Replace `getLogs()` with this complete implementation so a missing or unreadable
`latest.log` cannot discard the in-memory video snapshot:

```dart
  static Future<List<JoyLogEntry>> getLogs() async {
    try {
      final persisted = <JoyLogEntry>[];
      final path = p.join(_logsPath, 'latest.log');
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        final entries = content
            .split('<<<LOG_START>>>')
            .where((entry) => entry.contains('<<<LOG_END>>>'));

        for (final entry in entries) {
          final jsonStr = entry.replaceAll('<<<LOG_END>>>', '').trim();
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          persisted.add(
            JoyLogEntry(
              level: json['level'] ?? '',
              message: json['message'] ?? '',
              error: json['error']?.toString(),
              stackTrace: json['stackTrace']?.toString(),
              time: json['time'] ?? '',
            ),
          );
        }
      }
      return mergeDiagnosticLogs(persisted, _videoDiagnostics);
    } catch (error, stackTrace) {
      _logger.e(
        'Failed to get logs',
        error: error,
        stackTrace: stackTrace,
      );
      return List<JoyLogEntry>.unmodifiable(_videoDiagnostics);
    }
  }
```

At the start of `clear()`, add:

```dart
    _videoDiagnostics.clear();
```

Update `_JoyPrinter` to reuse `Log._timestamp()` instead of constructing a second timestamp formatter.

- [ ] **Step 6: Run log tests and verify GREEN**

Run:

```powershell
flutter test -r compact test/log_export_test.dart
flutter analyze lib/foundation/log.dart test/log_export_test.dart
```

Expected: all log export tests pass and analyze reports no issues.

- [ ] **Step 7: Stop for Codex review**

Report buffer capacity, merge behavior, and verification output. Do not commit or push.

---

### Task 4: Add Third-Party Notice and Run the Full Verification Gate

**Files:**
- Create: `THIRD_PARTY_NOTICES.md`
- Inspect: `codemagic.yaml`
- Verify: all files changed in Tasks 1-3

- [ ] **Step 1: Add the FVP notice**

Create `THIRD_PARTY_NOTICES.md` with:

```markdown
# Third-Party Notices

## FVP

JoyComic uses FVP 0.37.3 for the iOS video backend.

FVP is distributed under the BSD-3-Clause License.
Copyright 2022 Wang Bin. All rights reserved.

Source and license: https://github.com/wang-bin/fvp

## libmdk and FFmpeg runtime

FVP distributes libmdk and its FFmpeg runtime for media playback. The upstream
libmdk documentation states that use through the Flutter FVP package is free,
including commercial Flutter applications. Distribution requirements include
shipping the libmdk and FFmpeg runtime libraries bundled by FVP.

Upstream distribution terms: https://github.com/wang-bin/mdk-sdk
```

Do not claim that libmdk itself is BSD licensed; its upstream distribution terms are distinct from FVP's source license.

- [ ] **Step 2: Verify Codemagic assumptions without speculative edits**

Inspect `codemagic.yaml` and confirm all of the following:

- `flutter create . --platforms=ios` runs when `ios/` is absent.
- `flutter pub get` runs before `flutter build ios`.
- The build runs on macOS with CocoaPods available through Flutter tooling.
- No `FVP_DEPS_LATEST=1` is set.

Expected: no `codemagic.yaml` change. If `flutter pub get` or package metadata reveals a concrete required configuration, report it to Codex instead of inventing a CI workaround.

- [ ] **Step 3: Run focused and combined regression tests**

Run:

```powershell
flutter test -r compact test/video_backend_test.dart test/video_page_test.dart test/hls_quality_test.dart test/log_export_test.dart test/detail_share_test.dart test/detail_redesign_test.dart
```

Expected: all tests pass with zero failures.

- [ ] **Step 4: Run static and repository checks**

Run:

```powershell
flutter analyze lib/main.dart lib/foundation/video_backend.dart lib/foundation/log.dart lib/views/video/video_player_page.dart test/video_backend_test.dart test/video_page_test.dart test/log_export_test.dart
git diff --check
git status --short --branch
```

Expected:

- `flutter analyze` reports `No issues found`.
- `git diff --check` exits 0.
- Only the planned files are modified or created.
- The pre-existing untracked `.superpowers/` directory remains untouched and untracked.

- [ ] **Step 5: Inspect the dependency lock and native plugin metadata**

Run:

```powershell
flutter pub deps | Select-String -Pattern "fvp|video_player"
git diff -- pubspec.yaml pubspec.lock
```

Expected: `fvp 0.37.3` is a direct locked dependency and official `video_player` remains because the app-facing API is unchanged.

- [ ] **Step 6: Report the iOS-only residual verification requirement**

State explicitly that Windows cannot run `flutter build ios`. The post-push Codemagic acceptance check is:

```bash
flutter build ios --release --build-name="$VERSION" --build-number="$BN"
```

The build must complete Pod resolution and link the FVP/libmdk frameworks. True playback acceptance still requires installing the resulting IPA on iPhone and checking picture, sound, controls, fullscreen, and quality switching.

- [ ] **Step 7: Stop for final Codex review**

Provide a concise report of changed files, test/analyze results, dependency versions, and remaining iOS risks. Do not commit, push, publish, delete `.superpowers/`, or modify files outside this plan.
