# JoyComic Full Feature Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every functional placeholder with real dual-source discovery, local content management, settings, cache, and about functionality while fixing unstable remote JSON parsing.

**Architecture:** Extend the existing declarative `ComicSource` contract so UI pages consume source-neutral home/category/list capabilities. Keep Provider/ChangeNotifier and hand-written SQLite, add idempotent migrations, and isolate remote parsing behind typed helpers. Build each subsystem test-first and create local commits; push `main` only once after all available verification succeeds.

**Tech Stack:** Dart 3.10, Flutter 3.32+, go_router, provider, dio, sqlite3, shared_preferences, cached_network_image_ce, path_provider, flutter_test.

---

## File map

New focused files:

- `lib/network/json_value.dart` — safe remote scalar/list/map conversion.
- `lib/views/common/source_content_models.dart` — source-neutral home/category/list models.
- `lib/views/common/source_content_page.dart` — paginated category/home “more” results.
- `lib/views/history/history_page.dart` — history UI and continue-reading navigation.
- `lib/views/settings/about_page.dart` — about, disclaimer, licenses and project link.
- `lib/foundation/cache_manager.dart` — safe cache sizing and clearing boundaries.
- `test/json_value_test.dart` — unstable JSON scalar regression coverage.
- `test/source_content_models_test.dart` — category mapping/filtering coverage.
- `test/database_helpers_test.dart` — migration, favorites and history behavior.
- `test/download_manager_logic_test.dart` — download deduplication/state transitions.
- `test/app_data_test.dart` — theme migration behavior.

Primary modified files:

- `lib/comic_source/comic_source.dart`, `lib/comic_source/built_in/jm.dart`, `lib/comic_source/built_in/picacg.dart`
- `lib/network/jm/jm_network.dart`, `lib/network/jm/jm_models.dart`, `lib/network/picacg/picacg_network.dart`, `lib/network/picacg/picacg_models.dart`
- `lib/database/joy_database.dart`, `lib/database/favorites_helper.dart`, `lib/database/read_record_helper.dart`, `lib/database/download_helper.dart`
- `lib/foundation/app_data.dart`, `lib/foundation/download_manager.dart`, `lib/foundation/download_task.dart`
- `lib/views/home/home_page.dart`, `lib/views/category/category_page.dart`, `lib/views/favorites/favorites_page.dart`, `lib/views/download/download_page.dart`, `lib/views/mine/mine_page.dart`
- `lib/views/detail/detail_page.dart`, `lib/views/detail/detail_view_model.dart`, `lib/views/reader/providers/reader_provider.dart`
- `lib/views/settings/settings_page.dart`, `lib/views/settings/reader_settings_page.dart`, `lib/main.dart`

### Task 1: Safe remote JSON parsing and detail crash regression

**Files:**
- Create: `lib/network/json_value.dart`
- Create: `test/json_value_test.dart`
- Modify: `lib/network/jm/jm_network.dart`
- Modify: `lib/network/jm/jm_models.dart`
- Modify: `lib/network/picacg/picacg_network.dart`
- Modify: `lib/network/picacg/picacg_models.dart`
- Test: `test/crypto_logic_test.dart`

- [ ] **Step 1: Write failing scalar conversion tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/network/json_value.dart';

void main() {
  test('jsonInt accepts server numeric variants', () {
    expect(jsonInt(12), 12);
    expect(jsonInt('12'), 12);
    expect(jsonInt(12.8), 12);
    expect(jsonInt(null, fallback: 7), 7);
    expect(jsonInt('bad', fallback: 3), 3);
  });

  test('jsonStringList drops null and stringifies scalar values', () {
    expect(jsonStringList(['a', 2, null]), ['a', '2']);
    expect(jsonStringList(null), isEmpty);
  });
}
```

- [ ] **Step 2: Run the regression test and verify red**

Run: `flutter test test/json_value_test.dart`
Expected: FAIL because `network/json_value.dart` does not exist.

- [ ] **Step 3: Implement centralized converters**

```dart
int jsonInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String jsonString(Object? value, {String fallback = ''}) =>
    value == null ? fallback : value.toString();

List<String> jsonStringList(Object? value) => value is List
    ? value.where((e) => e != null).map((e) => e.toString()).toList()
    : const [];
```

- [ ] **Step 4: Replace unstable remote casts**

Replace all remote `as int`, `as int?`, and string-only casts in JM/Picacg response parsing with `jsonInt`, `jsonString`, `jsonStringList`, and guarded map/list conversion. Preserve strict casts only for values created locally by JoyComic.

- [ ] **Step 5: Run focused and existing crypto tests**

Run: `flutter test test/json_value_test.dart test/crypto_logic_test.dart`
Expected: PASS with zero failures.

- [ ] **Step 6: Commit locally**

```bash
git add lib/network test/json_value_test.dart test/crypto_logic_test.dart
git commit -m "fix: harden remote response parsing"
```

### Task 2: Source-neutral discovery contract and dual-source category adapters

**Files:**
- Create: `lib/views/common/source_content_models.dart`
- Create: `test/source_content_models_test.dart`
- Modify: `lib/comic_source/comic_source.dart`
- Modify: `lib/comic_source/built_in/jm.dart`
- Modify: `lib/comic_source/built_in/picacg.dart`
- Modify: `lib/network/jm/jm_network.dart`
- Modify: `lib/network/picacg/picacg_network.dart`

- [ ] **Step 1: Write failing category normalization tests**

```dart
test('visible categories reject empty and web-only entries', () {
  final values = normalizeCategories([
    const SourceCategory(key: '', title: 'empty'),
    const SourceCategory(key: 'web', title: 'Web', webOnly: true),
    const SourceCategory(key: 'love', title: '恋爱'),
  ]);
  expect(values.map((e) => e.key), ['love']);
});
```

- [ ] **Step 2: Run test and verify red**

Run: `flutter test test/source_content_models_test.dart`
Expected: FAIL because the model file does not exist.

- [ ] **Step 3: Add source-neutral models and callbacks**

Define `SourceCategory`, `SourceContentSection`, `SourceContentQuery`, `SourceContentPage`, `LoadSourceCategories`, `LoadSourceContent`, and `LoadHomeSections`. Add nullable callbacks to `ComicSource` without source-specific fields in UI models.

- [ ] **Step 4: Implement real Picacg categories**

Add `PicacgNetwork.getCategories()` using the authenticated `categories` endpoint. Map `_id/title/thumb/isWeb` safely, remove empty and web-only values, and load results through the existing comics/category endpoint with page and sort parameters.

- [ ] **Step 5: Implement real JM categories**

Use JM category/setting endpoints already represented by `JmCategory` and source responses. Preserve parent/subcategory identifiers and adapt JM order keys to source-neutral sort options.

- [ ] **Step 6: Run model and parsing tests**

Run: `flutter test test/source_content_models_test.dart test/json_value_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit locally**

```bash
git add lib/comic_source lib/network lib/views/common/source_content_models.dart test/source_content_models_test.dart
git commit -m "feat: add dual-source discovery contract"
```

### Task 3: Real home sections and paginated content page

**Files:**
- Create: `lib/views/common/source_content_page.dart`
- Modify: `lib/views/home/home_page.dart`
- Modify: `lib/views/home/widgets/featured_carousel.dart`
- Modify: `lib/views/common/widgets/comic_card.dart`
- Modify: `lib/views/common/widgets/comic_grid.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Add aggregation behavior test**

Test a pure `mergeHomeSections` helper with one successful source and one failed source; assert successful sections remain visible and errors are source-scoped.

- [ ] **Step 2: Run test and verify red**

Run: `flutter test test/source_content_models_test.dart`
Expected: FAIL because `mergeHomeSections` is missing.

- [ ] **Step 3: Implement home aggregation**

Load both source section callbacks concurrently with `Future.wait`, convert each failure into a source error section, retain successful sections, and expose refresh completion only after every request settles.

- [ ] **Step 4: Rebuild home UI around real sections**

Keep the featured carousel, render recent/hot/recommended sections below it, add source badges, per-section retry, global pull-to-refresh, empty state, and functional “更多” navigation.

- [ ] **Step 5: Add paginated generic result page and route**

Register `/content/:sourceKey` with query parameters `kind`, `category`, `param`, and `sort`. Implement page loading, refresh, load-more guard, max-page handling, retry and empty state.

- [ ] **Step 6: Run tests and commit locally**

Run: `flutter test test/source_content_models_test.dart`
Expected: PASS.

```bash
git add lib/views/home lib/views/common lib/main.dart test/source_content_models_test.dart
git commit -m "feat: populate home with real source sections"
```

### Task 4: Dual-source category UI

**Files:**
- Modify: `lib/views/category/category_page.dart`
- Modify: `lib/views/common/source_content_page.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Add widget test for source tabs and category navigation**

Pump the category page with two fake source adapters, assert “禁漫” and “哔咔” tabs exist, switch tabs, tap a category, and verify the generated content route targets the selected source/category rather than `/detail`.

- [ ] **Step 2: Run test and verify red**

Run: `flutter test test/category_page_test.dart`
Expected: FAIL under the current hard-coded category page.

- [ ] **Step 3: Implement retained dual-source tab state**

Use `DefaultTabController` or explicit `TabController`; create one stateful category body per enabled source in an `IndexedStack`, preserving each list and scroll controller.

- [ ] **Step 4: Connect category cards to the generic content page**

Pass category key, optional parent parameter and default sort through encoded URI query parameters. Show login action only when the selected source endpoint requires authentication.

- [ ] **Step 5: Run test and commit locally**

Run: `flutter test test/category_page_test.dart test/source_content_models_test.dart`
Expected: PASS.

```bash
git add lib/views/category lib/views/common/source_content_page.dart lib/main.dart test/category_page_test.dart
git commit -m "feat: implement dual-source categories"
```

### Task 5: Database migration, favorites, and reading history

**Files:**
- Modify: `lib/database/joy_database.dart`
- Modify: `lib/database/favorites_helper.dart`
- Modify: `lib/database/read_record_helper.dart`
- Create: `test/database_helpers_test.dart`

- [ ] **Step 1: Write migration and CRUD tests**

Create temporary SQLite databases; initialize schema; assert old tables gain `title`, `cover_url`, `chapter_title`, `page_count` and `updated_at` where required. Assert favorite/history upsert, list, delete and clear behavior.

- [ ] **Step 2: Run tests and verify red**

Run: `flutter test test/database_helpers_test.dart`
Expected: FAIL because complete metadata columns and APIs are absent.

- [ ] **Step 3: Add idempotent schema migration helpers**

Use `PRAGMA table_info(table)` before each `ALTER TABLE ... ADD COLUMN`. Store a `schema_meta` version and run migrations in order without deleting existing rows.

- [ ] **Step 4: Expand favorites and history records**

Return typed records containing source, comic id, title, cover, author, chapter id/title, page number/count and timestamp. Add counts for the Mine page.

- [ ] **Step 5: Run database tests and commit locally**

Run: `flutter test test/database_helpers_test.dart`
Expected: PASS.

```bash
git add lib/database test/database_helpers_test.dart
git commit -m "feat: persist complete library metadata"
```

### Task 6: Real favorites and history pages

**Files:**
- Modify: `lib/views/favorites/favorites_page.dart`
- Create: `lib/views/history/history_page.dart`
- Modify: `lib/views/detail/detail_view_model.dart`
- Modify: `lib/views/reader/providers/reader_provider.dart`
- Modify: `lib/views/reader/state/comic_state.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: Write favorite consistency and history navigation tests**

Verify remote favorite failure leaves local state unchanged; remote success upserts local metadata. Verify a history record creates a `ComicState` with the stored chapter and page.

- [ ] **Step 2: Run tests and verify red**

Run: `flutter test test/library_pages_test.dart`
Expected: FAIL under current local-first toggle and missing history page.

- [ ] **Step 3: Make favorite updates remote-first**

For sources with remote favorite capability, call remote API first; only mutate SQLite and notify listeners after success. For unavailable remote capability, use local-only behavior explicitly.

- [ ] **Step 4: Implement favorites page**

Merge local records with remote pages when logged in, deduplicate by `sourceKey/comicId`, support source filters, refresh, removal, detail navigation, offline local display and source-specific login prompts.

- [ ] **Step 5: Implement history page and reader persistence**

Add resume, detail, delete and clear actions. Save full metadata on chapter/page changes with a debounce; restore stored initial page when opening the reader.

- [ ] **Step 6: Register `/favorites` and `/history` routes**

Use real pages and remove their placeholder fallthrough.

- [ ] **Step 7: Run tests and commit locally**

Run: `flutter test test/library_pages_test.dart test/database_helpers_test.dart`
Expected: PASS.

```bash
git add lib/views/favorites lib/views/history lib/views/detail lib/views/reader lib/main.dart test/library_pages_test.dart
git commit -m "feat: implement favorites and reading history"
```

### Task 7: Chapter download pipeline and offline reading

**Files:**
- Modify: `lib/foundation/download_task.dart`
- Modify: `lib/foundation/download_manager.dart`
- Modify: `lib/database/download_helper.dart`
- Modify: `lib/views/download/download_page.dart`
- Modify: `lib/views/detail/detail_page.dart`
- Modify: `lib/views/reader/reader.dart`
- Create: `test/download_manager_logic_test.dart`

- [ ] **Step 1: Write download identity/state tests**

Assert `(sourceKey, comicId, chapterId)` is unique, duplicate enqueue returns the existing task, and only valid transitions occur: pending→downloading, downloading→paused/completed/failed, paused/failed→downloading.

- [ ] **Step 2: Run test and verify red**

Run: `flutter test test/download_manager_logic_test.dart`
Expected: FAIL because chapter identity and transition guards are incomplete.

- [ ] **Step 3: Expand download task persistence**

Store title, cover, chapter title, ordered page URLs, completed page count, directory and failure message. Add an idempotent unique index and migrate old rows.

- [ ] **Step 4: Implement source-aware chapter worker**

Resolve pages from `ComicSource.loadComicPages`, apply image headers/config, download to a temporary chapter directory, perform JM recombination where required, atomically rename on completion, and persist after every page.

- [ ] **Step 5: Add detail chapter selection and download controls**

Show a chapter selection sheet with queued/completed state. Prevent duplicates and report source/login/network errors.

- [ ] **Step 6: Implement real download page and offline reader entry**

Group tasks by comic, expose pause/resume/retry/delete, distinguish task deletion from file deletion, and open completed local page paths through the reader.

- [ ] **Step 7: Run tests and commit locally**

Run: `flutter test test/download_manager_logic_test.dart test/database_helpers_test.dart`
Expected: PASS.

```bash
git add lib/foundation lib/database/download_helper.dart lib/views/download lib/views/detail/detail_page.dart lib/views/reader test/download_manager_logic_test.dart
git commit -m "feat: implement chapter downloads and offline reading"
```

### Task 8: Theme persistence and real reader settings

**Files:**
- Modify: `lib/foundation/app_data.dart`
- Modify: `lib/foundation/reader_config.dart`
- Modify: `lib/main.dart`
- Modify: `lib/views/settings/settings_page.dart`
- Modify: `lib/views/settings/reader_settings_page.dart`
- Create: `test/app_data_test.dart`

- [ ] **Step 1: Write theme migration tests**

Verify legacy `enableDarkMode=true/false` maps to dark/light, absent legacy value maps to system, and setting `ThemeMode.system/light/dark` persists its string name.

- [ ] **Step 2: Run test and verify red**

Run: `flutter test test/app_data_test.dart`
Expected: FAIL because only a boolean dark setting exists.

- [ ] **Step 3: Implement theme mode storage and notifier**

Expose `ThemeMode get themeMode`, persist `themeMode.name`, migrate once from the old boolean, and notify `MaterialApp.router` immediately.

- [ ] **Step 4: Connect every reader setting to ReaderConf**

Initialize controls from persisted values and write changes immediately. Remove mock state and stale comments; unsupported iOS volume-key control must not be presented as functional.

- [ ] **Step 5: Run tests and commit locally**

Run: `flutter test test/app_data_test.dart`
Expected: PASS.

```bash
git add lib/foundation/app_data.dart lib/foundation/reader_config.dart lib/main.dart lib/views/settings test/app_data_test.dart
git commit -m "feat: persist theme and reader settings"
```

### Task 9: Cache management and About page

**Files:**
- Create: `lib/foundation/cache_manager.dart`
- Create: `lib/views/settings/about_page.dart`
- Modify: `lib/views/settings/settings_page.dart`
- Modify: `lib/main.dart`
- Test: `test/cache_manager_test.dart`

- [ ] **Step 1: Write cache boundary tests**

Build temporary `cache`, `temp-download`, `completed-download`, `db` and `source-data` directories. Assert `clearSafeCaches()` deletes only cache/temp/log content and preserves completed downloads, databases and source account files.

- [ ] **Step 2: Run test and verify red**

Run: `flutter test test/cache_manager_test.dart`
Expected: FAIL because `CacheManager` does not exist.

- [ ] **Step 3: Implement safe size calculation and clearing**

Recursively count regular files with error isolation, clear disk caches plus Flutter `PaintingBinding.instance.imageCache`, and expose separate completed-download deletion.

- [ ] **Step 4: Connect settings UI**

Display calculated size, show confirmation, disable action while clearing, refresh the value afterward, and provide a distinct destructive download deletion row.

- [ ] **Step 5: Implement `/about`**

Show app/version constants, purpose and copyright disclaimer, `showLicensePage`, project URL via `url_launcher`, and diagnostics navigation.

- [ ] **Step 6: Run tests and commit locally**

Run: `flutter test test/cache_manager_test.dart`
Expected: PASS.

```bash
git add lib/foundation/cache_manager.dart lib/views/settings/about_page.dart lib/views/settings/settings_page.dart lib/main.dart test/cache_manager_test.dart
git commit -m "feat: add cache management and about page"
```

### Task 10: Real Mine page, route cleanup, and placeholder eradication

**Files:**
- Modify: `lib/views/mine/mine_page.dart`
- Modify: `lib/views/settings/settings_page.dart`
- Modify: `lib/main.dart`
- Delete: `lib/views/detail/detail_demo_data.dart` if no production imports remain
- Test: `test/navigation_smoke_test.dart`

- [ ] **Step 1: Write navigation smoke test**

Pump the app with initialized test stores and navigate every visible Mine/Home/Settings menu item. Assert no destination contains “功能待集成” and unknown routes show a 404 page with a back action.

- [ ] **Step 2: Run test and verify red**

Run: `flutter test test/navigation_smoke_test.dart`
Expected: FAIL because history/about/favorites and other menu routes currently hit `_PlaceholderPage`.

- [ ] **Step 3: Populate Mine with real source/account and database state**

Read each enabled source’s account/user map defensively, display actual login state, avatar/name/level when available, and calculate favorite/history/completed-download counts from helpers.

- [ ] **Step 4: Remove fake values and dead actions**

Replace hard-coded login levels, no-op `onAction`, fake category/detail links and stale mock comments. Remove demo detail injection and its data file when unused.

- [ ] **Step 5: Replace generic placeholder routing with explicit 404**

Register every visible route. Keep `errorBuilder`, but render “页面不存在” with URI, home and back actions rather than claiming a feature awaits integration.

- [ ] **Step 6: Run smoke test and commit locally**

Run: `flutter test test/navigation_smoke_test.dart`
Expected: PASS and no visible route reaches a functional placeholder.

```bash
git add -A lib test/navigation_smoke_test.dart
git commit -m "feat: complete mine navigation and remove placeholders"
```

### Task 11: Full verification and single remote push

**Files:**
- Modify only files required by verification failures.

- [ ] **Step 1: Scan source for unresolved placeholders and dangerous casts**

Run:

```powershell
Get-ChildItem lib -Recurse -Filter *.dart |
  Select-String -Pattern '功能待集成|当前全 mock|改动不落盘|onAction:\s*\(\)\s*\{\}|as int\??'
```

Expected: no functional placeholders or unguarded remote integer casts; comments referring to legitimate loading placeholders may remain.

- [ ] **Step 2: Verify every project-local Dart URI**

Run the repository-local import resolution scan across `lib` and `test`.
Expected: `0 unresolved project-local Dart URIs`.

- [ ] **Step 3: Run formatter, analyzer and full tests**

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Expected: all commands exit 0. If Flutter remains unavailable on the workstation, record that limitation explicitly and run the static import and diff checks instead; do not claim compiler success.

- [ ] **Step 4: Review final diff and repository state**

```bash
git diff origin/main...HEAD --check
git status --short
git log --oneline origin/main..HEAD
```

Expected: no whitespace errors, no uncommitted production changes, and all local feature commits listed.

- [ ] **Step 5: Perform the only remote push**

```bash
gh auth status
gh auth setup-git
git push origin main
```

Expected: `main -> main`; verify `git rev-parse HEAD` equals `git rev-parse origin/main`.
