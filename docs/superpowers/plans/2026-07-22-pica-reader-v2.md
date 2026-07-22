# Pica-Style Reader V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the production reader kernel with a session-isolated, priority-scheduled, Pica-style image lifecycle shared by every reading mode.

**Architecture:** `ReaderV2Session` owns cancellation and diagnostics; `ReaderV2Scheduler` bounds and prioritizes all page work; immutable `ReaderV2Page` descriptors adapt JoyComic sources; one ImageProvider/widget pair renders all modes. The old reader remains untouched until the v2 route shell passes focused tests.

**Tech Stack:** Flutter/Dart, Provider, Dio, ImageStream/ImageCache, ScrollAwareImageProvider, PhotoView, flutter_test.

**Design:** `docs/superpowers/specs/2026-07-22-pica-reader-v2-design.md`

---

### Task 1: Session And Priority Scheduler

**Files:**
- Create: `lib/views/reader_v2/core/reader_v2_session.dart`
- Create: `lib/views/reader_v2/core/reader_v2_scheduler.dart`
- Create: `test/reader_v2_scheduler_test.dart`

- [ ] Write failing tests proving maximum three active jobs, visible priority over preload, duplicate-key deduplication, and cancellation rejection.
- [ ] Run `flutter test --no-pub test/reader_v2_scheduler_test.dart`; expect compile failure because v2 types do not exist.
- [ ] Implement immutable `ReaderV2Event`, `ReaderV2Session`, `ReaderV2Priority`, and `ReaderV2Scheduler`.

```dart
enum ReaderV2Priority { visible, preload }

final class ReaderV2Session {
  ReaderV2Session({String? traceId});
  String get traceId;
  bool get isCancelled;
  List<ReaderV2Event> get events;
  void cancel(String reason);
  void record(String stage, {int? page, String detail = ''});
  void throwIfCancelled();
}

final class ReaderV2Scheduler {
  ReaderV2Scheduler({required ReaderV2Session session, int maxConcurrent = 3});
  Future<T> schedule<T>({required String key, required int page,
    required ReaderV2Priority priority, required Future<T> Function() task});
  int get activeCount;
  int get queuedCount;
  Future<void> get idle;
  void dispose();
}
```

- [ ] Re-run the scheduler test; expect all tests pass.
- [ ] Commit: `feat: add reader v2 session scheduler`.

### Task 2: Page Descriptor And JoyComic Adapter

**Files:**
- Create: `lib/views/reader_v2/data/reader_v2_page.dart`
- Create: `lib/views/reader_v2/data/reader_v2_data_adapter.dart`
- Create: `test/reader_v2_adapter_test.dart`

- [ ] Write failing tests for URL/header/cache/fallback/transform preservation for JM and ordinary Pica descriptors.
- [ ] Run the test; expect compile failure.
- [ ] Implement immutable `ReaderV2Page` and adapter functions using existing `SourceAwareImageDescriptor`, `ReaderImageLoader`, and `ReaderImageConfigResolver`.

```dart
final class ReaderV2Page {
  const ReaderV2Page({required this.index, required this.url,
    required this.cacheKey, this.headers, this.fallbackUrls = const [],
    this.bytesTransformer});
  final int index;
  final String url;
  final String cacheKey;
  final Map<String, String>? headers;
  final List<String> fallbackUrls;
  final ReaderImageBytesTransformer? bytesTransformer;
}
```

- [ ] Re-run adapter tests; expect pass.
- [ ] Commit: `feat: adapt JoyComic pages for reader v2`.

### Task 3: Shared Pica-Style Image Kernel

**Files:**
- Create: `lib/views/reader_v2/image/reader_v2_image_provider.dart`
- Create: `lib/views/reader_v2/widgets/reader_v2_page_image.dart`
- Create: `test/reader_v2_image_test.dart`
- Create: `LICENSE-PicaComic`

- [ ] Write failing provider/widget tests proving serial fallback, transformed bytes validation, one real `RawImage` frame, non-zero placeholder, and disposal cancellation.
- [ ] Run the test; expect compile failure.
- [ ] Adapt PicaComic's MIT StreamImageProvider/ComicImage lifecycle. Route all work through `ReaderV2Scheduler`; use `ScrollAwareImageProvider`; preserve ImageStream handles; defer ImageInfo disposal until the next frame.
- [ ] Add the PicaComic MIT notice without changing JoyComic source ownership.
- [ ] Re-run image tests; expect pass.
- [ ] Commit: `feat: add Pica-style reader v2 image kernel`.

### Task 4: V2 Controller And Lazy Viewports

**Files:**
- Create: `lib/views/reader_v2/reader_v2_controller.dart`
- Create: `lib/views/reader_v2/viewports/reader_v2_vertical.dart`
- Create: `lib/views/reader_v2/viewports/reader_v2_paged.dart`
- Create: `test/reader_v2_viewport_test.dart`

- [ ] Write failing tests using 45 fake pages. After initial pump, assert only page zero and the configured nearby window are scheduled, active work stays at three, page zero frames first, and scroll/paged changes update priority.
- [ ] Run the test; expect compile failure.
- [ ] Implement `ReaderV2Controller` for chapter generation, current page, scheduler window, history callbacks, retry, and session cancellation.
- [ ] Implement lazy vertical and paged builders. Vertical must not set chapter-wide cache extent. Horizontal, vertical-paged, and double-page variants must build `ReaderV2PageImage` only.
- [ ] Re-run viewport tests; expect pass.
- [ ] Commit: `feat: add lazy reader v2 viewports`.

### Task 5: Compatibility Shell And Route Switch

**Files:**
- Create: `lib/views/reader_v2/reader_v2.dart`
- Modify: `lib/main.dart`
- Test: `test/reader_v2_route_test.dart`
- Modify: `test/routes_test.dart`

- [ ] Write failing route/widget tests proving `/reader` creates the v2 shell, preserves `ComicState`, exposes toolbar/drawer/next chapter controls, cancels on dispose, and selects all configured read modes.
- [ ] Run the focused route tests; expect failure while `/reader` uses the old `Reader`.
- [ ] Implement the compatibility shell using existing `ReaderAppBar`, `ReaderBottom`, page number, chapter drawer, history helper, and source resolvers around the v2 controller/viewports.
- [ ] Switch only `/reader` in `main.dart` to `ReaderV2`; keep old files as code rollback.
- [ ] Re-run route and reader-v2 tests; expect pass.
- [ ] Commit: `feat: switch reader route to reader v2`.

### Task 6: Verification

- [ ] Run:

```powershell
flutter test --no-pub test/reader_v2_scheduler_test.dart test/reader_v2_adapter_test.dart test/reader_v2_image_test.dart test/reader_v2_viewport_test.dart test/reader_v2_route_test.dart test/routes_test.dart
flutter analyze --no-pub
git diff --check origin/main...HEAD
```

- [ ] Confirm no old reader image/provider/preload class is imported by `lib/views/reader_v2/`.
- [ ] Confirm a 45-page test starts at most three active jobs and does not instantiate all page providers.
- [ ] Review PicaComic MIT notice and committed file scope.
- [ ] Build through Codemagic and validate JM/Pica first frame, re-entry, all read modes, bounded concurrency, and trace isolation on iPhone before deleting the old kernel.
