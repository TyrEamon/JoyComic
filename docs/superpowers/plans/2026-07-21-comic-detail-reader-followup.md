# Comic Detail and Reader Follow-up Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the approved comic-detail geometry and responsive presentation, route JM chapter thumbnails through the real descrambling pipeline, and add actionable reader black-screen diagnostics.

**Architecture:** Keep `DetailViewModel` and `ComicSource` as the data boundaries. Extract a small source-aware image descriptor/provider usable by both detail chapter cards and the reader, while keeping the existing reader transformer as the single JM decode implementation. Make hero geometry a shared pure calculation consumed by the success and loading layouts; add trace-scoped logging at reader pipeline boundaries and link errors to the existing `/logs` page.

**Tech Stack:** Flutter/Dart, Provider, GoRouter, `flutter_test`, existing `ReaderNetworkImageProvider`, `jmReaderTransformer`, `Log` persistence/export.

---

## File map and locks

- Modify `lib/views/detail/widgets/hero_header.dart` and `lib/views/detail/widgets/detail_loading_skeleton.dart` for the shared hero geometry.
- Modify `lib/views/detail/widgets/synopsis_block.dart`, `lib/views/detail/widgets/recommendation_carousel.dart`, and `lib/views/detail/detail_page.dart` for the content layout and bottom safe area.
- Modify `lib/views/detail/detail_view_model.dart`, `lib/views/detail/widgets/chapter_thumbnail.dart`, `lib/views/detail/widgets/chapter_grid.dart`, and `lib/views/detail/detail_chapters_page.dart` for source-aware chapter image descriptors.
- Modify `lib/views/reader/providers/reader_provider.dart`, `lib/views/reader/utils/reader_image_provider.dart`, `lib/views/reader/widgets/reader_image.dart`, `lib/views/reader/widgets/error_page.dart`, and `lib/views/reader/widgets/app_bar.dart` for trace logging and log navigation.
- Add or modify focused tests under `test/detail_redesign_test.dart`, `test/detail_subpages_test.dart`, `test/detail_view_model_test.dart`, `test/detail_tabs_test.dart`, `test/routes_test.dart`, and reader image/provider tests.
- No other worker may modify the listed files while this plan is active. Do not commit, push, or alter unrelated worktrees.

### Task 1: Lock the hero geometry with failing tests

**Files:**
- Modify: `test/detail_redesign_test.dart`
- Create or modify: `lib/views/detail/widgets/detail_hero_geometry.dart`

- [ ] **Step 1: Write failing geometry tests.** Add pure tests that calculate a mobile hero with a 3:4 cover and assert: `surfaceTop` is at `coverTop + coverHeight * 2 / 3` within one logical pixel; `coverBottom` is within the content surface; `metadataTop` follows `coverBottom` by only the declared section spacing. Add a large-text test asserting the title band bottom is no lower than the cover bottom and does not overlap the reserved app bar band.

- [ ] **Step 2: Run the focused test and verify the expected failure.**

Run: `flutter test --no-pub test/detail_redesign_test.dart -r expanded`

Expected: FAIL because the geometry helper and the 2/3 seam contract do not exist yet.

- [ ] **Step 3: Implement the minimal pure geometry helper.** Define an immutable calculation input/output in `detail_hero_geometry.dart` with `coverWidth`, `coverAspectRatio`, `backdropHeight`, `appBarReserved`, and responsive surface spacing. Return `coverTop`, `coverBottom`, `surfaceTop`, `totalHeight`, and a safe title band. Use the fixed rule `surfaceTop = coverTop + coverHeight * 2 / 3`; clamp the title band to the available space instead of adding arbitrary blank height.

- [ ] **Step 4: Run the focused test and verify it passes.**

Run: `flutter test --no-pub test/detail_redesign_test.dart -r expanded`

Expected: PASS for the pure geometry tests; existing widget tests may still fail until Task 2 wires the helper into both layouts.

- [ ] **Step 5: Commit the geometry contract.**

```powershell
git add lib/views/detail/widgets/detail_hero_geometry.dart test/detail_redesign_test.dart
git commit -m "test: define detail hero geometry contract"
```

### Task 2: Wire hero, metadata, and synopsis layout

**Files:**
- Modify: `lib/views/detail/widgets/hero_header.dart`
- Modify: `lib/views/detail/widgets/detail_loading_skeleton.dart`
- Modify: `lib/views/detail/detail_page.dart`
- Modify: `lib/views/detail/widgets/synopsis_block.dart`
- Test: `test/detail_redesign_test.dart`

- [ ] **Step 1: Add failing widget assertions.** Assert in a widget test that the success hero surface seam and floating cover geometry use the 2/3 rule at 375, 768, and 1280 logical widths. Add a test that metadata starts near the cover bottom, not after the old `surfaceExtra` gap. Add a long synopsis test that checks the collapsed text reserves a right-side toggle lane and that `展开` does not overlap the final line.

- [ ] **Step 2: Run the tests and verify they fail against the current layout.**

Run: `flutter test --no-pub test/detail_redesign_test.dart -r expanded`

Expected: FAIL on seam/metadata positions and synopsis overlap.

- [ ] **Step 3: Replace inline hero constants with the helper.** Have `HeroHeader` call the pure geometry helper, position the surface and cover from its output, and bottom-align the title/author/tags group to the cover bottom. Keep rating in the content surface and avoid reserving rating space when null. Apply the same helper inputs to `DetailLoadingSkeleton`.

- [ ] **Step 4: Reserve synopsis toggle width before painting text.** Keep three collapsed lines, but build a constrained row/stack where the text's last-line max width subtracts the toggle lane. Put `展开`/`收起` in a separate right-aligned control with a 44px hit target and no opaque overlay over the text.

- [ ] **Step 5: Run the tests and verify the layout passes.**

Run: `flutter test --no-pub test/detail_redesign_test.dart test/detail_theme_test.dart -r expanded`

Expected: PASS with no overflow exceptions at phone, tablet, desktop, and 1.3x text scale.

- [ ] **Step 6: Commit the UI geometry/layout fix.**

```powershell
git add lib/views/detail/widgets/hero_header.dart lib/views/detail/widgets/detail_loading_skeleton.dart lib/views/detail/detail_page.dart lib/views/detail/widgets/synopsis_block.dart test/detail_redesign_test.dart test/detail_theme_test.dart
git commit -m "fix: align detail hero and synopsis layout"
```

### Task 3: Fix recommendation wrapping and bottom safe area

**Files:**
- Modify: `lib/views/detail/widgets/recommendation_carousel.dart`
- Modify: `lib/views/detail/detail_page.dart`
- Modify: `lib/views/common/widgets/comic_card.dart` only if the poster card cannot expose a two-line title without affecting other callers
- Test: `test/detail_redesign_test.dart`

- [ ] **Step 1: Add failing recommendation/safe-area tests.** Pump a recommendation carousel with a long title and assert the title `Text.maxLines == 2` and its card height remains stable. Pump the detail content with a non-zero bottom `MediaQuery.padding` and assert the final padding includes both the system inset and the declared design spacing.

- [ ] **Step 2: Run the tests and verify the expected failure.**

Run: `flutter test --no-pub test/detail_redesign_test.dart -r expanded`

Expected: FAIL because `ComicCard.poster` currently uses one title line and detail content only ends at fixed `AppSpacing.xl`.

- [ ] **Step 3: Implement the smallest scoped fix.** Give the poster card a two-line title option, enabled only by `RecommendationCarousel`, with a fixed title slot height so cards do not resize. In `DetailPage`, append `MediaQuery.paddingOf(context).bottom + AppSpacing.xl` after the recommendation section; do not add a fixed action bar.

- [ ] **Step 4: Run tests and commit.**

Run: `flutter test --no-pub test/detail_redesign_test.dart test/routes_test.dart -r expanded`

Expected: PASS.

```powershell
git add lib/views/detail/widgets/recommendation_carousel.dart lib/views/detail/detail_page.dart lib/views/common/widgets/comic_card.dart test/detail_redesign_test.dart
git commit -m "fix: wrap recommendations and honor detail safe area"
```

### Task 4: Route chapter thumbnails through the JM transform pipeline

**Files:**
- Modify: `lib/views/detail/detail_view_model.dart`
- Modify: `lib/views/detail/widgets/chapter_thumbnail.dart`
- Modify: `lib/views/detail/widgets/chapter_grid.dart`
- Modify: `lib/views/detail/detail_chapters_page.dart`
- Modify: `lib/views/reader/utils/reader_image_provider.dart` or extract a small shared descriptor file if needed
- Test: `test/detail_view_model_test.dart`, `test/detail_subpages_test.dart`, and a focused reader image/provider test

- [ ] **Step 1: Add a failing descriptor test.** Create a fake source whose `getImageLoadingConfig` returns a structured JM transform for a chapter page. Assert `DetailViewModel.loadChapterThumbnailDescriptor` (or the chosen equivalent API) returns the URL, fallback list, cache key, headers, and non-null transformer; assert the raw URL is not passed to `CachedNetworkImage` directly.

- [ ] **Step 2: Run the test and verify it fails.**

Run: `flutter test --no-pub test/detail_view_model_test.dart test/detail_subpages_test.dart -r expanded`

Expected: FAIL because the current thumbnail API returns only `String?` and `ChapterThumbnail` bypasses the source-aware provider.

- [ ] **Step 3: Implement one shared descriptor path.** Reuse the reader's `ReaderImage`/provider-compatible fields or a focused immutable descriptor. Build it through `ComicSource.getImageLoadingConfig` with the chapter ID and first image name, preserving non-JM headers-only fallback. Ensure cache keys include source/chapter/image identity and never reuse an undecoded raw-image cache entry.

- [ ] **Step 4: Render thumbnails with the shared provider.** Update `ChapterThumbnail` and `ChapterGrid` to accept the descriptor and render via `readerImageProvider` (or the extracted equivalent), preserving placeholder, error and retry behavior. Keep chapter taps available if the thumbnail fails.

- [ ] **Step 5: Run focused tests and verify both detail surfaces.**

Run: `flutter test --no-pub test/detail_view_model_test.dart test/detail_subpages_test.dart test/detail_redesign_test.dart -r expanded`

Expected: PASS, including assertions that recent and full chapter pages use the JM transformer path.

- [ ] **Step 6: Commit the image-pipeline fix.**

```powershell
git add lib/views/detail/detail_view_model.dart lib/views/detail/widgets/chapter_thumbnail.dart lib/views/detail/widgets/chapter_grid.dart lib/views/detail/detail_chapters_page.dart lib/views/reader/utils/reader_image_provider.dart test/detail_view_model_test.dart test/detail_subpages_test.dart
git commit -m "fix: descramble JM detail chapter thumbnails"
```

### Task 5: Add reader trace logging and accessible diagnostics

**Files:**
- Modify: `lib/views/reader/providers/reader_provider.dart`
- Modify: `lib/views/reader/utils/reader_image_provider.dart`
- Modify: `lib/views/reader/widgets/reader_image.dart`
- Modify: `lib/views/reader/widgets/error_page.dart`
- Modify: `lib/views/reader/widgets/app_bar.dart`
- Modify: `lib/views/reader/reader.dart`
- Test: reader provider/image tests, `test/routes_test.dart`

- [ ] **Step 1: Add failing logging tests.** Inject or capture the existing `Log` sink in tests and assert a chapter load emits one short trace ID, source/comic/chapter context, URL count, config/transform summary, and final state. Add tests for network candidate failure and transformer failure asserting no Authorization/Cookie/full query URL appears. Add a route/widget test that the reader error/menu exposes navigation to `/logs` or the trace ID.

- [ ] **Step 2: Run tests and verify they fail.**

Run: `flutter test --no-pub test/reader_provider_test.dart test/reader_image_provider_test.dart test/routes_test.dart -r expanded`

Expected: FAIL because current logs have no trace correlation or reader diagnostic action.

- [ ] **Step 3: Implement trace context and redacted fields.** Add a private trace context created per `ReaderProvider.load`, pass it to image resolution/provider callbacks, and log source, comic ID, chapter ID, index, host/status/content type/byte counts/magic only. Redact query strings and all sensitive headers. Keep cache keys as short hashes or stable non-secret summaries.

- [ ] **Step 4: Instrument decode and first-frame boundaries.** Log transformer begin/success/failure in `jmReaderTransformer` or its wrapper, codec failures in `ReaderNetworkImageProvider`, and first resolved dimensions from `ReaderImage`. Preserve existing retry/placeholder behavior so a failed image cannot leave a blank black item.

- [ ] **Step 5: Add the user-visible diagnostics action.** Add “查看诊断日志” to the reader error state and/or more menu, navigating to the existing `/logs` route. Keep a trace ID in the error state for copying when navigation is unavailable.

- [ ] **Step 6: Run focused reader tests and commit.**

Run: `flutter test --no-pub test/reader_provider_test.dart test/reader_image_provider_test.dart test/routes_test.dart -r expanded`

Expected: PASS with redaction assertions.

```powershell
git add lib/views/reader/providers/reader_provider.dart lib/views/reader/utils/reader_image_provider.dart lib/views/reader/widgets/reader_image.dart lib/views/reader/widgets/error_page.dart lib/views/reader/widgets/app_bar.dart lib/views/reader/reader.dart test/reader_provider_test.dart test/reader_image_provider_test.dart test/routes_test.dart
git commit -m "feat: add reader image diagnostic traces"
```

### Task 6: Integration verification and handoff

**Files:**
- Modify: only tests or implementation files if a verified integration failure requires it.

- [ ] **Step 1: Inspect the full diff and check for forbidden UI regressions.** Confirm no rating-count/hot-list/fixed-bottom-bar text or component returned, no detail-page download button returned, and no credentials appear in diagnostic log messages.

- [ ] **Step 2: Run the complete required checks.**

Run:

```powershell
flutter analyze --no-pub
flutter test --no-pub test/detail_redesign_test.dart test/detail_subpages_test.dart test/detail_actions_test.dart test/detail_tabs_test.dart test/detail_theme_test.dart test/detail_view_model_test.dart test/detail_view_model_favorite_test.dart test/detail_domain_test.dart test/routes_test.dart test/download_manager_logic_test.dart test/reader_provider_test.dart test/reader_image_provider_test.dart
git diff --check
```

Expected: analyzer has no issues; all affected tests pass; any pre-existing unrelated full-suite failures are recorded with their baseline evidence.

- [ ] **Step 3: Review responsive invariants manually from test geometry.** Check 375x812, 768x1024, 1280x900, 1.3x text scale, and non-zero bottom safe-area padding. Confirm no overflow exceptions.

- [ ] **Step 4: Leave the branch clean and report changed files, test counts, remaining risks, and the exact commit range.** Do not push or merge; Codex owns final review and publication.
