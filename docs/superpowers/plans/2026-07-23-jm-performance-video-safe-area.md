# 禁漫源性能、视频与安全区优化实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让禁漫源在失效线路、受保护 HLS 和 iPhone 底部安全区场景下更快、更可诊断且不影响现有解扰结果。

**Architecture:** 在 `JmNetwork` 外围增加进程内的 host 健康状态、single-flight 和显式公开 GET TTL；图片 provider 通过共享图床状态选择候选 URL；视频使用 API HLS 的原生播放器并在 platform view 不可渲染时回退到本地 HLS HTML，而不是打开禁漫网页。页面底部 inset 由一个纯 Flutter helper 统一计算。

**Tech Stack:** Flutter/Dart, Dio, video_player, webview_flutter, cached_network_image_ce, flutter_test。

**Reference inputs:** `clone/JMComic3v2.0.29-analysis.md`, `clone/JMComic-APK`, `clone/JMComic-Crawler-Python`, `clone/joycomic-ios`, `clone/PicaComic`。

---

## File Structure

- Create `lib/network/jm/jm_endpoint_health.dart` — API host 状态、冷却和 single-flight。
- Create `lib/network/jm/jm_request_cache.dart` — 仅公开幂等 GET 的内存 TTL/LRU cache。
- Create `lib/network/jm/jm_image_health.dart` — 图片 host 状态、失败冷却与 URL 请求去重。
- Create `lib/theme/app_safe_area.dart` — 页面底部安全区纯函数。
- Modify `lib/network/jm/jm_network.dart` — 使用 endpoint health、request cache 和显式 GET TTL。
- Modify `lib/network/jm/jm_image.dart` — 暴露规范化 JM image host 候选和 URL 替换工具。
- Modify `lib/views/reader_v2/image/reader_v2_image_provider.dart` — 共享图片 host 健康排序。
- Modify `lib/views/reader/utils/reader_image_provider.dart` — 共享图片 host 健康排序。
- Modify `lib/views/common/widgets/comic_cover.dart` — 封面失败时使用 JM 图床 fallback。
- Modify `lib/views/video/video_player_page.dart` — direct-HLS HTML、生命周期日志和回退状态。
- Modify `lib/views/video/video_page.dart`, `lib/views/detail/detail_chapters_page.dart`, `lib/views/search/search_page.dart`, `lib/views/search/temp_search_page.dart`, `lib/views/history/history_page.dart`, `lib/views/ranking/ranking_page.dart`, `lib/views/image_search/image_search_page.dart`, `lib/views/premium/jm_premium_page.dart`, `lib/views/settings/about_page.dart`, `lib/views/settings/log_viewer_page.dart`, `lib/views/settings/reader_settings_page.dart`, `lib/views/settings/settings_page.dart`, `lib/views/settings/source_manager_page.dart`, `lib/views/settings/source_settings_page.dart`, `lib/views/settings/webdav_settings_page.dart` — 使用统一底部 inset。
- Create `test/jm_endpoint_health_test.dart`, `test/jm_request_cache_test.dart`, `test/jm_image_health_test.dart`, `test/app_safe_area_test.dart`。
- Modify `test/video_page_test.dart` and existing JM network/widget tests。

---

### Task 1: API host 健康状态、single-flight 与公开 GET cache

**Files:**
- Create: `lib/network/jm/jm_endpoint_health.dart`
- Create: `lib/network/jm/jm_request_cache.dart`
- Test: `test/jm_endpoint_health_test.dart`, `test/jm_request_cache_test.dart`

- [ ] **Step 1: Write failing host health tests**

```dart
test('failed host is cooled down and successful host is first', () {
  final health = JmEndpointHealth(
    clock: () => DateTime.fromMillisecondsSinceEpoch(1000),
    baseCooldown: const Duration(seconds: 10),
  );
  health.recordFailure('dead.example', FailureClass.timeout);
  expect(health.order(const ['dead.example', 'ok.example']), ['ok.example', 'dead.example']);
  health.recordSuccess('dead.example');
  expect(health.order(const ['dead.example', 'ok.example']).first, 'dead.example');
});

test('same probe key shares one future', () async {
  final health = JmEndpointHealth();
  var calls = 0;
  Future<int> probe() async {
    calls++;
    return 7;
  }
  final values = await Future.wait([
    health.singleFlight('login-probe', probe),
    health.singleFlight('login-probe', probe),
  ]);
  expect(values, [7, 7]);
  expect(calls, 1);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/jm_endpoint_health_test.dart`  
Expected: FAIL because `JmEndpointHealth`, `FailureClass`, and `singleFlight` do not exist.

- [ ] **Step 3: Implement the host health class**

Implement `JmEndpointHealth` with `Map<String, HostHealth>`, `recordSuccess`, `recordFailure`, `recordBusinessResponse`, `order`, `isCoolingDown`, and `singleFlight<T>(String key, Future<T> Function() operation)`. `recordBusinessResponse` must leave 401 and decoded business errors out of cooldown. Classify only timeout/network/empty/5xx as cooling failures. Cap exponential cooldown at 60 seconds and remove completed single-flight entries in `finally`.

- [ ] **Step 4: Write failing request cache tests**

```dart
test('request cache expires entries and keeps keys isolated', () async {
  var now = DateTime.fromMillisecondsSinceEpoch(1000);
  final cache = JmRequestCache(clock: () => now);
  cache.put(
    'jm:album:1',
    const Res<dynamic>({'id': '1'}),
    const Duration(seconds: 5),
  );
  expect(cache.get('jm:album:1'), isNotNull);
  expect(cache.get('jm:album:2'), isNull);
  now = now.add(const Duration(seconds: 6));
  expect(cache.get('jm:album:1'), isNull);
});
```

- [ ] **Step 5: Implement bounded TTL/LRU cache**

Implement `JmRequestCache` with a 64-entry LRU map, `put`, `get`, `remove`, and `clear`. Never cache errors, login, favorite, comment, or any POST response. Cache values as immutable `Res<dynamic>` snapshots only after a non-error response.

- [ ] **Step 6: Run focused tests**

Run: `flutter test test/jm_endpoint_health_test.dart test/jm_request_cache_test.dart`  
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/network/jm/jm_endpoint_health.dart lib/network/jm/jm_request_cache.dart test/jm_endpoint_health_test.dart test/jm_request_cache_test.dart
git commit -m "feat: add JM host health and request cache"
```

### Task 2: 接入 JmNetwork 并显式标注公开 GET TTL

**Files:**
- Modify: `lib/network/jm/jm_network.dart`
- Test: `test/jm_auth_test.dart`, `test/jm_network_latency_test.dart`, `test/jm_endpoint_health_test.dart`

- [ ] **Step 1: Add failing integration tests**

Extend the existing `_StatusAdapter` pattern in `test/jm_network_latency_test.dart` with a counting adapter. Start two concurrent `selectDomain(const ['one.example'])` calls and assert one underlying probe after endpoint-health injection. Add a `JmEndpointHealth` unit assertion that `recordBusinessResponse('one.example', statusCode: 401)` leaves the host out of cooldown.

- [ ] **Step 2: Run the integration test and verify failure**

Run: `flutter test test/jm_endpoint_health_test.dart test/jm_auth_test.dart test/jm_network_latency_test.dart`  
Expected: FAIL because `JmNetwork` still loops directly over `_domainCandidates`.

- [ ] **Step 3: Wire health ordering and cache into `JmNetwork`**

Add injectable constructor arguments and final fields initialized in `_create`: `JmEndpointHealth? endpointHealth`, `JmRequestCache? requestCache`, `_endpointHealth`, and `_requestCache`. In `_withDomainFailover`, replace `_domainCandidates` with `_endpointHealth.order(_domainCandidates)`, record success for non-error responses, and record only transport failures for null attempts. Keep `waitForLogin` and POST sequencing unchanged. Add optional `Duration? cacheTtl` to `get`; cache only when `cacheTtl != null`, `!isRetry`, and the request is an allowlisted public GET.

- [ ] **Step 4: Mark safe endpoints with explicit TTLs**

Pass these values at the listed callsites, leaving auth/private calls without TTL:

```dart
fetchSetting -> const Duration(minutes: 5)
search / category / latest / hotTags -> const Duration(seconds: 45)
promote / album detail -> const Duration(minutes: 2)
chapter metadata -> const Duration(minutes: 1)
video listing/detail -> const Duration(seconds: 30)
```

The cache key must include the normalized path and query plus `state?.username ?? 'anonymous'` only for responses explicitly classified as account-safe. Do not include token or AVS values in logs or cache keys.

- [ ] **Step 5: Add domain probe single-flight**

Wrap `selectDomain` in `_endpointHealth.singleFlight('select-domain:${domains.join(',')}', () async { ... })`. Ensure the existing timer is cancelled in `finally` and the first successful 401 index wins.

- [ ] **Step 6: Run JM regression tests**

Run: `flutter test test/jm_auth_test.dart test/jm_network_latency_test.dart test/jm_endpoint_health_test.dart`  
Expected: PASS; then run `flutter analyze` and expect no new diagnostics.

- [ ] **Step 7: Commit**

```bash
git add lib/network/jm/jm_network.dart test/jm_auth_test.dart test/jm_network_latency_test.dart test/jm_endpoint_health_test.dart
git commit -m "feat: coalesce JM failover and cache public GETs"
```

### Task 3: 图片 host 健康排序与 fallback

**Files:**
- Create: `lib/network/jm/jm_image_health.dart`
- Modify: `lib/network/jm/jm_image.dart`
- Modify: `lib/views/reader_v2/image/reader_v2_image_provider.dart`
- Modify: `lib/views/reader/utils/reader_image_provider.dart`
- Modify: `lib/views/common/widgets/comic_cover.dart`
- Test: `test/jm_image_health_test.dart` and existing reader image tests

- [ ] **Step 1: Write failing image health tests**

```dart
test('successful image host is preferred and failed host is cooled', () {
  final health = JmImageHealth(clock: () => now);
  health.recordSuccess('cdn-good.example');
  health.recordFailure('cdn-bad.example', ImageFailure.timeout);
  expect(health.order(const ['cdn-bad.example', 'cdn-good.example']).first, 'cdn-good.example');
});

test('same image key shares the download future', () async {
  final health = JmImageHealth();
  var calls = 0;
  final result = await Future.wait([
    health.singleFlight('album/1.jpg', () async { calls++; return 3; }),
    health.singleFlight('album/1.jpg', () async { calls++; return 3; }),
  ]);
  expect(result, [3, 3]);
  expect(calls, 1);
});
```

- [ ] **Step 2: Implement host state and candidate URL helpers**

Create `JmImageHealth` with `recordSuccess`, `recordFailure`, `order`, and `singleFlight`. Add `jmImageBaseCandidates()` and `replaceJmImageHost(Uri uri, String host)` in `jm_image.dart`; preserve the current image path, query, and cache key.

- [ ] **Step 3: Run the image tests to verify the initial failure**

Run: `flutter test test/jm_image_health_test.dart`  
Expected: FAIL before provider integration because no health class exists.

- [ ] **Step 4: Integrate the health policy into both reader providers**

Build the candidate list from the current URL plus JM image candidates only for JM hosts. On transport/timeout/non-image failure, record the host and try the next candidate. On successful byte validation and successful scramble transform, record success. Keep the existing `fallbackUrls`, `cacheKey`, headers, isolate transformer, session cancellation, and image-size checks unchanged.

- [ ] **Step 5: Integrate cover fallback without changing non-JM sources**

For `ComicCover`, keep `CachedNetworkImage` for non-JM URLs. For JM URLs, pass the ordered fallback URLs into the existing JM-aware provider or a small stateful fallback widget; do not convert all covers to data URIs and do not alter the displayed aspect ratio.

- [ ] **Step 6: Run reader and cover tests**

Run: `flutter test test/jm_image_health_test.dart test/reader_v2_image_test.dart test/reader_image_provider_test.dart`  
Expected: PASS, including existing de-scramble and cache-key assertions.

- [ ] **Step 7: Commit**

```bash
git add lib/network/jm/jm_image.dart lib/network/jm/jm_image_health.dart lib/views/reader_v2/image/reader_v2_image_provider.dart lib/views/reader/utils/reader_image_provider.dart lib/views/common/widgets/comic_cover.dart test/jm_image_health_test.dart
git commit -m "feat: add JM image host health fallback"
```

### Task 4: Direct-HLS WebView fallback and diagnostics

**Files:**
- Modify: `lib/views/video/video_player_page.dart`
- Modify: `test/video_page_test.dart`

- [ ] **Step 1: Write failing direct-HLS tests**

```dart
test('direct HLS document contains safe inline video and redacted diagnostics', () {
  const html = buildDirectHlsVideoHtml('https://cdn.example/a.m3u8?token=secret');
  expect(html, contains('<video'));
  expect(html, contains('playsinline'));
  expect(html, contains('loadedmetadata'));
  expect(html, isNot(contains('token=secret')));
});
```

Add a widget test where `directPlayerBuilder` calls `onFailure`, then assert the direct-HLS WebView builder receives the API HLS URL rather than `https://18comic.vip/video/<id>`.

- [ ] **Step 2: Run video tests and verify failure**

Run: `flutter test test/video_page_test.dart`  
Expected: FAIL because the current fallback passes `_fullUrl` to the extracting page WebView.

- [ ] **Step 3: Implement the local HLS HTML builder**

Add `buildDirectHlsVideoHtml(String source)` that HTML-escapes the source, emits one `<video id="player" controls autoplay playsinline preload="metadata">`, and posts redacted JSON events through the existing JavaScript channel. Redact query values before logging and never expose Cookie/AVS/token values to Dart logs.

- [ ] **Step 4: Add a direct-HLS WebView widget**

Create an internal `DirectHlsVideoWebView` using the existing `videoWebViewCreationParams`, `WebViewController`, and `loadHtmlString`. Keep the trusted remote URI validation for the media source; the document itself is local and must not navigate to arbitrary URLs. Report `loadedmetadata`, `canplay`, `playing`, `waiting`, `stalled`, and `error` through a callback.

- [ ] **Step 5: Change fallback state transitions**

When native playback fails or reports a zero render size, set a direct-HLS fallback state if `_directSource` is non-empty. Use the extracting JM page only when no API source exists. Preserve the existing external browser button for a final failure and preserve stale-generation/failed-source loop guards.

- [ ] **Step 6: Run the complete video suite**

Run: `flutter test test/video_page_test.dart`  
Expected: PASS, including URL validation, navigation policy, extraction fallback, orientation restoration, stale detail protection, and the new direct-HLS assertions.

- [ ] **Step 7: Commit**

```bash
git add lib/views/video/video_player_page.dart test/video_page_test.dart
git commit -m "fix: play JM HLS directly after native render failure"
```

### Task 5: 统一独立页面底部安全区

**Files:**
- Create: `lib/theme/app_safe_area.dart`
- Modify: `lib/views/video/video_page.dart`, `lib/views/video/video_player_page.dart`, `lib/views/detail/detail_chapters_page.dart`, `lib/views/search/search_page.dart`, `lib/views/search/temp_search_page.dart`, `lib/views/history/history_page.dart`, `lib/views/ranking/ranking_page.dart`, `lib/views/image_search/image_search_page.dart`, `lib/views/premium/jm_premium_page.dart`, `lib/views/settings/about_page.dart`, `lib/views/settings/log_viewer_page.dart`, `lib/views/settings/reader_settings_page.dart`, `lib/views/settings/settings_page.dart`, `lib/views/settings/source_manager_page.dart`, `lib/views/settings/source_settings_page.dart`, `lib/views/settings/webdav_settings_page.dart`
- Test: `test/app_safe_area_test.dart`

- [ ] **Step 1: Write failing inset tests**

```dart
testWidgets('bottomContentInset combines view padding and design spacing', (tester) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(viewPadding: EdgeInsets.only(bottom: 34)),
      child: Builder(builder: (context) => Text('${bottomContentInset(context)}')),
    ),
  );
  expect(find.text('${34 + AppSpacing.xl}'), findsOneWidget);
});
```

- [ ] **Step 2: Implement the pure helper**

Add `bottomContentInset(BuildContext context, {double spacing = AppSpacing.xl})` using `MediaQuery.viewPaddingOf(context).bottom + spacing`. Do not wrap pages in a second `SafeArea` when their AppBar already owns the top inset.

- [ ] **Step 3: Apply the helper to independent scrollables**

Replace fixed `bottom: AppSpacing.xl` or absent bottom padding with the helper in chapter list, video list/player controls, search results/history, ranking, image search, premium lists, log/source/settings/about/reader settings pages. For slivers use `SliverPadding`; for `ListView` use `EdgeInsets.only(bottom: bottomContentInset(context))`. Leave detail’s existing `detail-bottom-safe-padding` key intact while switching its calculation to the helper.

- [ ] **Step 4: Avoid double inset on tab/root shells**

Check each changed page’s router parent. If a page is inside the main navigation shell that already applies bottom padding, apply only its scroll content spacing and not an additional `SafeArea` around the whole scaffold.

- [ ] **Step 5: Run page and inset tests**

Run: `flutter test test/app_safe_area_test.dart test/detail_page_test.dart test/video_page_test.dart`  
Expected: PASS with no overflow diagnostics.

- [ ] **Step 6: Commit**

```bash
git add lib/theme/app_safe_area.dart lib/views test/app_safe_area_test.dart test/detail_page_test.dart test/video_page_test.dart
git commit -m "fix: apply bottom safe area to standalone pages"
```

### Task 6: Full verification and handoff

**Files:**
- Test: all existing `test/` files

- [ ] **Step 1: Run formatting and static checks**

Run: `dart format lib test`  
Expected: formatter exits 0 and only touched Dart files change.

- [ ] **Step 2: Run focused suites**

Run: `flutter test test/jm_endpoint_health_test.dart test/jm_request_cache_test.dart test/jm_image_health_test.dart test/video_page_test.dart test/app_safe_area_test.dart`  
Expected: PASS.

- [ ] **Step 3: Run the full test suite and analyzer**

Run: `flutter test` then `flutter analyze`  
Expected: all tests pass and analyzer reports no errors or warnings introduced by this work.

- [ ] **Step 4: Check diff and sensitive data**

Run: `git diff --check` and `rg -n "token=|Cookie|AVS|password|cf_clearance" lib test`  
Expected: no whitespace errors and no new sensitive logging or hard-coded credential.

- [ ] **Step 5: Review changes against the reference constraints**

Confirm the diff does not copy source code/source maps from the official APK, `JMComic-APK`, `JMComic-Crawler-Python`, `joycomic-ios`, or `PicaComic`; it only implements the documented behavior in JoyComic’s existing Dart boundaries.

- [ ] **Step 6: Commit verification result and push**

```bash
git status --short
git log -6 --oneline
git push origin codex/pica-reader-v2:main
```

Expected: clean worktree except pre-existing `.superpowers/`, and `origin/main` contains the implementation commits.
