# Reader Recycling and iOS Video Rollback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop recycled Reader V2 pages from inheriting disposed image streams and restore the official iOS platform-view video backend without FVP.

**Architecture:** Keep validated transformed image bytes in the existing bounded `ReaderV2PageLoader` LRU, but make every `ReaderV2ImageProvider` instance a distinct Flutter image-cache key so recycled widget mounts receive fresh completers/codecs. Remove the FVP dependency and startup registration, then restore iOS `VideoViewType.platformView` while retaining current video controls, fallbacks, and diagnostics.

**Tech Stack:** Flutter/Dart, `ImageProvider`, `ImageCache`, `video_player`, `video_player_avfoundation`, `flutter_test`.

---

## File Structure

- Modify `lib/views/reader_v2/image/reader_v2_image_provider.dart` to make framework stream ownership provider-instance scoped while preserving the byte LRU.
- Modify `lib/views/reader_v2/widgets/reader_v2_page_image.dart` to remove the ineffective widget-local post-frame error suppression.
- Modify `test/reader_v2_image_test.dart` to lock provider identity, remount behavior, and transformed-byte reuse.
- Modify `lib/views/video/video_player_page.dart` to restore iOS platform-view selection and the pre-FVP renderability contract.
- Modify `test/video_page_test.dart` to lock the official iOS view type and remove FVP-only expectations.
- Modify `lib/main.dart`, `pubspec.yaml`, and `pubspec.lock` to remove FVP startup registration and dependency resolution.
- Delete `lib/foundation/video_backend.dart`, `test/video_backend_test.dart`, and `THIRD_PARTY_NOTICES.md`, which exist only for FVP.

### Task 1: Isolate Reader Image Streams Across Widget Mounts

**Files:**
- Modify: `test/reader_v2_image_test.dart`
- Modify: `lib/views/reader_v2/image/reader_v2_image_provider.dart:222-276`

- [ ] **Step 1: Write the failing provider-identity and remount tests**

Add a test that constructs two providers for the same page, session, scheduler,
and byte loader, then requires distinct Flutter cache keys:

```dart
test('separate page mounts use separate framework image streams', () async {
  final session = ReaderV2Session(traceId: 'mount-identity');
  final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 1);
  addTearDown(scheduler.dispose);
  const page = ReaderV2Page(
    index: 0,
    url: 'https://example.test/mount.png',
    cacheKey: 'mount-page',
  );
  Future<Uint8List> load(
    ReaderV2Page page,
    ReaderV2Session session,
  ) async => _png;

  final first = ReaderV2ImageProvider(
    page: page,
    session: session,
    scheduler: scheduler,
    priority: ReaderV2Priority.visible,
    bytesLoader: load,
  );
  final second = ReaderV2ImageProvider(
    page: page,
    session: session,
    scheduler: scheduler,
    priority: ReaderV2Priority.visible,
    bytesLoader: load,
  );

  expect(await first.obtainKey(ImageConfiguration.empty), same(first));
  expect(await second.obtainKey(ImageConfiguration.empty), same(second));
  expect(first, isNot(equals(second)));
});
```

In the same file, use a real `ReaderV2PageLoader` with a counting fetcher.
Mount the page, wait for its frame, replace it with a placeholder, and mount it
again:

```dart
testWidgets('recycled page remounts without retry or another fetch', (
  tester,
) async {
  var fetches = 0;
  final loader = ReaderV2PageLoader(
    candidateFetcher: (_, _, _) async {
      fetches += 1;
      return _png;
    },
  );
  final session = ReaderV2Session(traceId: 'recycled-page');
  final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 1);
  addTearDown(scheduler.dispose);
  const page = ReaderV2Page(
    index: 0,
    url: 'https://example.test/recycled.png',
    cacheKey: 'recycled-page',
  );

  Widget app({required bool visible}) => MaterialApp(
    home: SizedBox(
      width: 200,
      child: visible
          ? ReaderV2PageImage(
              key: const ValueKey('recycled-image'),
              page: page,
              session: session,
              scheduler: scheduler,
              priority: ReaderV2Priority.visible,
              bytesLoader: loader.load,
              placeholderHeight: 200,
            )
          : const SizedBox(height: 200),
    ),
  );

  await tester.pumpWidget(app(visible: true));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
  expect(find.text('重试'), findsNothing);

  await tester.pumpWidget(app(visible: false));
  await tester.pump();
  await tester.pumpWidget(app(visible: true));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();

  expect(find.text('重试'), findsNothing);
  expect(session.events.where((event) => event.stage == 'frame').length, 2);
  expect(
    session.events.any((event) => event.stage == 'bytes-cache-hit'),
    isTrue,
  );
  expect(fetches, 1);
});
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
flutter test -r compact test/reader_v2_image_test.dart --plain-name "separate page mounts use separate framework image streams"
flutter test -r compact test/reader_v2_image_test.dart --plain-name "recycled page remounts without retry or another fetch"
```

Expected: FAIL because the current `operator ==` compares the shared
`traceId|cacheKey` string and treats the two providers as equal. The remount
test also fails to record a second fresh frame/byte-cache hit because it reuses
the first mount's framework completer.

- [ ] **Step 3: Implement instance-scoped provider keys**

Remove the content-derived equality and hash code from
`ReaderV2ImageProvider`:

```dart
final class ReaderV2ImageProvider extends ImageProvider<ReaderV2ImageProvider> {
  // Keep constructor, fields, obtainKey, loadImage, and _loadCodec unchanged.
  // Do not override operator == or hashCode: Object identity is the cache key.
}
```

The provider instance remains stable for ordinary rebuilds because
`ReaderV2PageImage` stores it in State. A recycled mount creates a new instance.

- [ ] **Step 4: Run the focused test to verify GREEN**

Run both commands from Step 2.

Expected: both PASS; the remount test records two frames, one
`bytes-cache-hit`, and only one network fetch.

- [ ] **Step 5: Commit the isolated cache-key change**

```powershell
git add -- test/reader_v2_image_test.dart lib/views/reader_v2/image/reader_v2_image_provider.dart
git commit -m "fix: isolate recycled reader image streams"
```

### Task 2: Remove the Ineffective Widget-Local Error Mask

**Files:**
- Modify: `test/reader_v2_image_test.dart`
- Modify: `lib/views/reader_v2/widgets/reader_v2_page_image.dart:39-260`

- [ ] **Step 1: Replace the symptom test with the desired error contract**

Replace `successful page image no longer exposes retry error UI` with a test
that renders a successful frame and verifies the widget still owns a handler
for future genuine decode errors:

```dart
testWidgets('successful page image retains genuine retry error handling', (
  tester,
) async {
  final session = ReaderV2Session(traceId: 'post-frame-error');
  final scheduler = ReaderV2Scheduler(session: session, maxConcurrent: 1);
  addTearDown(scheduler.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: SizedBox(
        width: 200,
        child: ReaderV2PageImage(
          page: const ReaderV2Page(
            index: 0,
            url: 'https://example.test/post-frame.png',
            cacheKey: 'post-frame-page',
          ),
          session: session,
          scheduler: scheduler,
          priority: ReaderV2Priority.visible,
          bytesLoader: (_, _) async => _png,
          placeholderHeight: 200,
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }

  expect(session.events.any((event) => event.stage == 'frame'), isTrue);
  expect(tester.widget<Image>(find.byType(Image)).errorBuilder, isNotNull);
  expect(find.text('重试'), findsNothing);
});
```

- [ ] **Step 2: Run the error-contract test to verify RED**

Run:

```powershell
flutter test -r compact test/reader_v2_image_test.dart --plain-name "successful page image retains genuine retry error handling"
```

Expected: FAIL because `_hasRenderedFrame` currently changes `errorBuilder` to
null after the first successful frame.

- [ ] **Step 3: Remove the ineffective post-frame suppression**

In `ReaderV2PageImage`, remove `_hasRenderedFrame`, all resets/assignments to
it, and restore the unconditional genuine-error builder:

```dart
errorBuilder: (context, error, stackTrace) {
  if (widget.session.isCancelled) return const SizedBox.shrink();
  if (_loggedErrorGeneration != _retryGeneration) {
    _loggedErrorGeneration = _retryGeneration;
    widget.session.record(
      'image-error',
      page: widget.page.index,
      detail: '$error',
    );
  }
  return Center(
    child: TextButton(
      key: ValueKey('reader-v2-retry-$_retryGeneration'),
      onPressed: _retry,
      child: const Text('重试'),
    ),
  );
},
```

Keep the natural-aspect-ratio update, but set it directly when a decoded frame
reports a new valid ratio.

- [ ] **Step 4: Run all Reader V2 image and viewport tests**

Run:

```powershell
flutter test -r compact test/reader_v2_image_test.dart test/reader_v2_viewport_test.dart test/reader_v2_route_test.dart test/reader_preload_test.dart
```

Expected: all tests pass; the remount test records two frames, one
`bytes-cache-hit`, and one network fetch.

- [ ] **Step 5: Commit the remount regression and cleanup**

```powershell
git add -- test/reader_v2_image_test.dart lib/views/reader_v2/widgets/reader_v2_page_image.dart
git commit -m "fix: preserve genuine reader error handling"
```

### Task 3: Remove FVP and Restore the Official iOS Platform View

**Files:**
- Modify: `test/video_page_test.dart`
- Modify: `lib/views/video/video_player_page.dart:724-764`
- Modify: `lib/main.dart:1-50`
- Modify: `pubspec.yaml:70-90`
- Modify: `pubspec.lock`
- Delete: `lib/foundation/video_backend.dart`
- Delete: `test/video_backend_test.dart`
- Delete: `THIRD_PARTY_NOTICES.md`

- [ ] **Step 1: Change video tests to the desired official-backend contract**

Replace the FVP view-selection test and controller expectation:

```dart
test('iOS and macOS select the native platform view backend', () {
  expect(nativeVideoViewType(TargetPlatform.iOS), VideoViewType.platformView);
  expect(nativeVideoViewType(TargetPlatform.macOS), VideoViewType.platformView);
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

Delete the test named
`FVP audio-only placeholder texture is treated as non-renderable`.

- [ ] **Step 2: Run the platform-view tests to verify RED**

Run:

```powershell
flutter test -r compact test/video_page_test.dart --plain-name "iOS and macOS select the native platform view backend"
```

Expected: FAIL because iOS currently selects `textureView`.

- [ ] **Step 3: Restore pre-FVP native video behavior**

Update the two pure helpers:

```dart
VideoViewType nativeVideoViewType(TargetPlatform platform) {
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return VideoViewType.platformView;
  }
  return VideoViewType.textureView;
}

bool isNativeVideoRenderable(VideoPlayerValue value) {
  final size = value.size;
  return value.isInitialized &&
      !value.hasError &&
      size.width > 0 &&
      size.height > 0 &&
      value.aspectRatio > 0;
}
```

- [ ] **Step 4: Remove FVP registration and dependency files**

Delete the `foundation/video_backend.dart` import and
`registerVideoBackend();` call from `lib/main.dart`. Remove `fvp: 0.37.3` from
`pubspec.yaml`. Delete the FVP-only Dart files and notice with `apply_patch`,
then refresh dependency resolution:

```powershell
flutter pub get
```

`flutter pub get` must remove the `fvp` package entry from `pubspec.lock`.

- [ ] **Step 5: Verify FVP is absent and video tests are GREEN**

Run:

```powershell
rg -n -i "package:fvp|registerVideoBackend|\bfvp:" lib test pubspec.yaml pubspec.lock
flutter test -r compact test/video_page_test.dart test/jm_video_test.dart
```

Expected: `rg` finds no FVP code/dependency references; all video tests pass.
Historical design and plan documents may still mention FVP and are not runtime
dependencies.

- [ ] **Step 6: Commit the video rollback**

```powershell
git add -- lib/main.dart lib/views/video/video_player_page.dart pubspec.yaml pubspec.lock test/video_page_test.dart
git add -u -- lib/foundation/video_backend.dart test/video_backend_test.dart THIRD_PARTY_NOTICES.md
git commit -m "fix: restore official iOS video backend"
```

### Task 4: Full Verification and Delivery

**Files:**
- Verify all files changed in Tasks 1-3.

- [ ] **Step 1: Run the focused regression suite**

```powershell
flutter test -r compact test/reader_v2_image_test.dart test/reader_v2_viewport_test.dart test/reader_v2_route_test.dart test/reader_preload_test.dart test/video_page_test.dart test/jm_video_test.dart
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Run static analysis on changed Dart files**

```powershell
flutter analyze lib/main.dart lib/views/reader_v2/image/reader_v2_image_provider.dart lib/views/reader_v2/widgets/reader_v2_page_image.dart lib/views/video/video_player_page.dart test/reader_v2_image_test.dart test/video_page_test.dart
```

Expected: `No issues found!`.

- [ ] **Step 3: Inspect the final diff and dependency state**

```powershell
git diff --check origin/main...HEAD
git status --short
git diff --stat origin/main...HEAD
```

Expected: only the design/plan, Reader fix/tests, and FVP rollback files are
tracked. `.superpowers/` remains untracked and is not staged.

- [ ] **Step 4: Push the verified branch to main**

```powershell
git push origin HEAD:main
git rev-parse HEAD
git rev-parse origin/main
```

Expected: push succeeds and both revisions are identical.
