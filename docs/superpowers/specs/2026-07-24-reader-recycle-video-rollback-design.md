# Reader Recycling and iOS Video Rollback Design

**Date:** 2026-07-24
**Status:** Approved design, awaiting written-spec review
**Scope:** Reader V2 recycled page images and the iOS JM video backend

## Evidence

The device log `joycomic_logs_1784866150646.txt` shows two independent
failures:

- FVP registers on iOS, opens the HLS source as a `16x16` audio-only texture,
  then the direct-HLS WebView fallback times out.
- Reader pages successfully reach `decode`, `paint-widget`, and `frame`, but
  later report `Null check operator used on a null value` after leaving the
  viewport.

Reader V2 currently gives different page mounts equal `ImageProvider` keys.
`ListView.builder` removes offscreen page widgets because `cacheExtent` is
zero. A later mount can therefore reuse an `ImageStreamCompleter` whose codec
was disposed by the earlier mount. The successful transformed-byte cache is
not the problem; framework image-stream ownership is.

## Goals

- Restore the official iOS `video_player_avfoundation` backend and the
  `platformView` rendering path that previously displayed video frames.
- Remove FVP and its packaged runtime from the application dependencies.
- Preserve current video controls, fullscreen, sharing, quality selection,
  source extraction, fallbacks, and diagnostics.
- Make every Reader V2 widget mount own a fresh framework image stream.
- Reuse transformed image bytes across mounts so returning to a page does not
  download or unscramble it again.
- Preserve retry UI for genuine first-load or decode failures.

## Non-Goals

- Do not retain every decoded page bitmap for an entire 125-page chapter.
- Do not change JM image download, fallback-host, or unscrambling algorithms.
- Do not redesign reader controls, scrolling behavior, or video UI.
- Do not remove general log-export improvements that are independent of FVP.

## Design

### iOS Video

Remove the `fvp` dependency, startup registration, backend selector, dedicated
tests, and FVP-only third-party notice. Restore iOS and macOS selection to
`VideoViewType.platformView` and restore the pre-FVP native-renderability
contract. Keep the rest of the current video page intact.

This is a surgical rollback to the behavior immediately before the FVP
commit, rather than reverting later unrelated reader or logging work.

### Reader Image Ownership

Keep `ReaderV2PageLoader` as the chapter-scoped owner of the bounded 64 MiB LRU
cache containing validated, transformed bytes.

Change `ReaderV2ImageProvider` to use instance identity as its Flutter image
cache key. A `ReaderV2PageImage` state keeps one provider for its lifetime, so
ordinary rebuilds continue using one stream. When `ListView.builder` recycles
the state and later mounts the page again, the new provider creates a new
`ImageStreamCompleter` and codec. Its byte request is served from the LRU cache.

Remove the previous post-frame `errorBuilder` suppression because it only
stored success inside a widget state that is destroyed offscreen. Genuine
errors continue to display the retry action, and manual retry still evicts the
current stream before creating another provider.

## Data Flow

1. A page enters the load window and mounts `ReaderV2PageImage`.
2. Its state creates an identity-scoped `ReaderV2ImageProvider`.
3. The provider asks the scheduler for transformed bytes.
4. `ReaderV2PageLoader` downloads and transforms once, then stores the bytes.
5. Flutter decodes and paints the page.
6. The page leaves the viewport and its widget/image stream may be disposed.
7. On return, a new provider and codec are created; the loader returns cached
   bytes without network or unscrambling work.

## Error Handling

- A failed first mount records `image-error` and shows `重试`.
- Retry evicts only that mount's provider and creates a fresh stream.
- Cancelled sessions suppress retry UI and late error logging as before.
- A recycled mount cannot inherit an earlier mount's disposed or failed
  completer.

## Tests

- RED/GREEN contract: two mounts for the same page/session receive distinct
  provider cache keys.
- RED/GREEN widget regression: dispose and remount a previously rendered page;
  it renders again without `重试`.
- Byte-cache regression: remounting may decode again but fetches and transforms
  only once.
- Video regression: iOS selects `platformView` and project dependencies and
  startup code no longer reference FVP.
- Run focused Reader V2/video tests, static analysis, and `git diff --check`.

## Acceptance Criteria

- On iOS, application logs no longer report FVP registration.
- The IPA no longer includes the FVP dependency or its runtime.
- JM video uses the official iOS platform-view path.
- Scrolling several pages away and returning never changes a previously
  rendered page into `重试`.
- Returning to a cached page does not repeat network fetch or unscrambling.
- Decoded bitmap memory remains bounded by Flutter's configured image cache.
