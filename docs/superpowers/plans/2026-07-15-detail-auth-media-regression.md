# JoyComic 19-Issue Regression Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace placeholder and mis-mapped detail, authentication, ranking, video, and reverse-image-search behavior with tested JM/Pica API-backed implementations covering all 19 approved issues.

**Architecture:** Keep one declarative `ComicSource` abstraction and one shared detail page, but move remote fields into typed domain models at the source boundary. Build the detail UI from slivers and explicit tab state, isolate credentials in secure storage, centralize login guards, and give video/image search dedicated network models instead of reusing comic-search placeholders.

**Tech Stack:** Flutter/Dart, Provider, GoRouter, Dio, flutter_secure_storage, pool, share_plus, image_picker, video_player, webview_flutter, flutter_test.

**Design reference:** `docs/superpowers/specs/2026-07-15-detail-auth-media-regression-design.md`

---

## File Structure

- Create `lib/comic_source/detail_models.dart` for typed detail, chapter, comment-page, and reply-target contracts.
- Create `lib/foundation/detail_rating.dart` and `lib/foundation/detail_text.dart` for pure display-data logic.
- Create `lib/foundation/source_credential_store.dart` and `lib/foundation/sauce_nao_config_store.dart` for secure secrets.
- Create `lib/network/jm/jm_video_models.dart` for real video APIs.
- Split focused detail widgets into `detail_metadata.dart`, `detail_tab_bar.dart`, `chapter_thumbnail.dart`, and `comment_composer.dart`.
- Modify both built-in source adapters, both network stacks, detail/search/home/ranking/auth/video/image-search pages, routes, dependencies, and Codemagic configuration.

---

### Task 1: Introduce typed detail contracts, synopsis normalization, and rating calculation

**Files:**
- Create: `lib/comic_source/detail_models.dart`
- Create: `lib/foundation/detail_rating.dart`
- Create: `lib/foundation/detail_text.dart`
- Modify: `lib/comic_source/comic_source.dart:21-50,128-145,376-454`
- Create: `test/detail_domain_test.dart`

- [ ] **Step 1: Write the failing domain tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:joycomic/comic_source/detail_models.dart';
import 'package:joycomic/foundation/detail_rating.dart';
import 'package:joycomic/foundation/detail_text.dart';

void main() {
  test('normalizes HTML synopsis and entities', () {
    expect(normalizeDetailText('<p>A&amp;B</p><div>C<br>D</div>'), 'A&B\nC\nD');
  });

  test('rating is bounded, monotonic, and absent without metrics', () {
    final low = calculateDetailRating(views: 100000, likes: 1000)!;
    final high = calculateDetailRating(views: 100000, likes: 10000)!;
    expect(low, inInclusiveRange(5.5, 9.8));
    expect(high, greaterThan(low));
    expect(calculateDetailRating(views: null, likes: null), isNull);
  });

  test('comment totals and pages remain independent', () {
    const page = CommentPageData(comments: [], page: 1, totalPages: 3, totalComments: 27);
    expect(page.totalPages, 3);
    expect(page.totalComments, 27);
  });
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/detail_domain_test.dart`
Expected: compilation fails because the new contracts and helpers do not exist.

- [ ] **Step 3: Implement typed contracts and update source typedefs**

Create immutable `ComicChapter`, `CommentReplyTarget`, `Comment`, and `CommentPageData` with these public signatures:

```dart
class ComicChapter {
  const ComicChapter({required this.id, required this.title, required this.order, this.pageCount});
  final String id;
  final String title;
  final int order;
  final int? pageCount;
}

class CommentReplyTarget {
  const CommentReplyTarget({required this.id, required this.userName});
  final String id;
  final String userName;
}

class CommentPageData {
  const CommentPageData({required this.comments, required this.page, required this.totalPages, required this.totalComments});
  final List<Comment> comments;
  final int page;
  final int totalPages;
  final int totalComments;
  bool get hasMore => page < totalPages;
}
```

Move `ComicInfoData` and `Comment` from `comic_source.dart` into the new file while preserving all existing compatibility fields. Add `authors`, `categories`, `labels`, raw metrics, `sourceRating`, `isLiked`, `chapterList`, and `singleChapterPages`.

Change source contracts to:

```dart
typedef CommentsLoader = Future<Res<CommentPageData>> Function(
  String id, String? subId, int page, String? replyToId,
);
typedef SendCommentFunc = Future<Res<bool>> Function(
  String id, String? subId, String content, CommentReplyTarget? replyTo,
);
```

Import and export `detail_models.dart` from `comic_source.dart`.

- [ ] **Step 4: Implement the pure helpers**

`normalizeDetailText` converts `<br>`, paragraph/div endings, strips remaining tags, decodes `amp/lt/gt/quot/apos/nbsp`, normalizes newlines, and removes excessive blank lines.

`calculateDetailRating` implements the approved logarithmic engagement formula with `dart:math`, clamps real source ratings, and returns null when all inputs are absent.

- [ ] **Step 5: Verify Task 1**

Run:

```powershell
flutter test test/detail_domain_test.dart test/source_parsing_test.dart
flutter analyze
```

Expected: tests pass and analyzer reports no issues.

- [ ] **Step 6: Commit Task 1**

```powershell
git add lib/comic_source/detail_models.dart lib/comic_source/comic_source.dart lib/foundation/detail_rating.dart lib/foundation/detail_text.dart test/detail_domain_test.dart
git commit -m "refactor: type comic detail contracts"
```

---

### Task 2: Map JM metrics, synopsis, single chapters, pages, and comments

**Files:**
- Modify: `lib/network/jm/jm_models.dart:93-170`
- Modify: `lib/network/jm/jm_parsing.dart:8-58`
- Modify: `lib/network/jm/jm_network.dart:530-546,670-817`
- Modify: `lib/comic_source/built_in/jm.dart:203-258,332-363`
- Modify: `test/source_parsing_test.dart`
- Create: `test/jm_detail_adapter_test.dart`

- [ ] **Step 1: Add failing JM parser and adapter tests**

Test HTML synopsis, `series_id=0`, inline images, metrics, categories, comment replies, and total. Expose `jmInfoToComicInfoData` with `@visibleForTesting` and assert:

```dart
final info = parseJmComicInfoResponse({
  'name': 'Single', 'author': ['A'], 'description': '<p>Intro</p>',
  'series_id': 0, 'series': [], 'images': ['00001.webp'],
  'total_views': '1200', 'likes': '120', 'comment_total': '7',
}, id: '123')!;
final data = jmInfoToComicInfoData(info);
expect(data.chapterList.single.id, '123');
expect(data.singleChapterPages, hasLength(1));
expect(data.viewCount, 1200);
expect(data.commentCount, 7);
```

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/source_parsing_test.dart test/jm_detail_adapter_test.dart`
Expected: missing fields and typed chapter/comment assertions fail.

- [ ] **Step 3: Extend JM models and parser**

Add `seriesId`, `images`, and `categories` to `JmComicInfo`. Parse scalar/list image forms, category titles, normalized synopsis, raw metrics, and remote chapter order. Generate the synthetic chapter when the approved single-volume condition matches.

- [ ] **Step 4: Implement JM page and comment APIs**

Add:

```dart
Future<Res<List<String>>> getComicPages(String comicId, String? chapterId);
Future<Res<bool>> sendComment(String comicId, String content);
```

Cache inline pages from detail and return them before calling `getChapter`. Parse `replys` into child comments and return `CommentPageData` with the response `total`. Post comments to `/comment` using URL-encoded `video_id`, `comment`, and `status=true`.

- [ ] **Step 5: Update the JM source adapter**

Map typed authors/categories/labels/metrics/chapters/inline pages. Wire `loadComicPages`, typed comments, and:

```dart
sendCommentFunc: (id, subId, content, replyTo) {
  final payload = replyTo == null ? content.trim() : '@${replyTo.userName} ${content.trim()}';
  return JmNetwork().sendComment(id, payload);
},
```

Remove formatted heat, favorite, and evaluation-count compatibility tags.

- [ ] **Step 6: Verify and commit Task 2**

```powershell
flutter test test/source_parsing_test.dart test/jm_detail_adapter_test.dart test/jm_network_latency_test.dart
flutter analyze
git add lib/network/jm lib/comic_source/built_in/jm.dart test/source_parsing_test.dart test/jm_detail_adapter_test.dart
git commit -m "fix: map JM detail and single chapters"
```

---

### Task 3: Map Pica metrics and implement comment totals, children, sending, and replies

**Files:**
- Modify: `lib/network/picacg/picacg_models.dart:122-186`
- Modify: `lib/network/picacg/picacg_network.dart:384-446,515-554`
- Modify: `lib/comic_source/built_in/picacg.dart:200-256,303-330`
- Create: `test/picacg_detail_adapter_test.dart`
- Create: `test/picacg_comments_test.dart`

- [ ] **Step 1: Write failing Pica tests**

Use injectable request callbacks to test `viewsCount`, separate categories/labels, real total/pages, child replies, and endpoint selection:

```dart
expect(detail.viewCount, 4567);
expect(detail.categories, ['青年']);
expect(detail.labels, ['冒险']);
expect(page.totalPages, 4);
expect(page.totalComments, 37);
expect(recordedPath, 'comments/c1');
```

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/picacg_detail_adapter_test.dart test/picacg_comments_test.dart`
Expected: missing metrics, page contract, and send/reply methods fail.

- [ ] **Step 3: Extend Pica models and detail parsing**

Add nullable views parsed from `viewsCount/totalViews/views`. Preserve categories and tagList separately. Map typed metrics, chapter objects, favorites, and likes in `picacgItemToComicInfoData`.

- [ ] **Step 4: Implement typed Pica comment APIs**

Add:

```dart
Future<Res<CommentPageData>> getComments(String id, {int page = 1, String type = 'comics'});
Future<Res<CommentPageData>> getCommentChildren(String commentId, {int page = 1});
Future<Res<bool>> sendComment(String comicId, String content);
Future<Res<bool>> replyComment(String commentId, String content);
```

Parse `total`, `pages`, `page`, `likesCount`, `isLiked`, and `commentsCount`. Map child docs to `Comment.replies`.

- [ ] **Step 5: Wire the source contract**

Use `replyTo.id` for replies and comic ID for top-level comments. Remove formatted heat/evaluation fields from compatibility tags.

- [ ] **Step 6: Verify and commit Task 3**

```powershell
flutter test test/picacg_detail_adapter_test.dart test/picacg_comments_test.dart test/picacg_home_adapter_test.dart
flutter analyze
git add lib/network/picacg lib/comic_source/built_in/picacg.dart test/picacg_detail_adapter_test.dart test/picacg_comments_test.dart
git commit -m "fix: map Pica detail comments and replies"
```

---

### Task 4: Rebuild DetailViewModel around typed chapters, lazy thumbnails, and comments

**Files:**
- Modify: `lib/views/detail/detail_view_model.dart:20-260`
- Modify: the file containing `ReaderChapter.fromChapterMap`
- Create: `test/detail_view_model_test.dart`
- Modify: `test/detail_view_model_favorite_test.dart`

- [ ] **Step 1: Write failing ViewModel tests**

Use fake `ComicSource` functions to prove that comments do not load during `load()`, `activateComments()` loads once, totals do not equal the first page length, send failure preserves state, send success clears reply state, thumbnail calls are cached, concurrency never exceeds three, and inline single-chapter pages bypass the remote loader.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/detail_view_model_test.dart test/detail_view_model_favorite_test.dart`
Expected: failures for auto-loaded comments and missing reply/thumbnail/page APIs.

- [ ] **Step 3: Implement typed derived state**

Expose:

```dart
List<ComicChapter> get chapters;
double? get rating;
int get commentTotal;
CommentReplyTarget? get replyTarget;
bool get commentSending;
String? get commentSendError;
```

Use `calculateDetailRating` and typed fields. Remove tag-key parsing helpers from the page/ViewModel.

- [ ] **Step 4: Implement lazy comments and sending**

Add:

```dart
Future<void> activateComments();
Future<void> loadMoreComments();
void beginReply(Comment comment);
void cancelReply();
Future<bool> sendComment(String content);
```

Reload page 1 after success; preserve error and input state after failure.

- [ ] **Step 5: Implement page and thumbnail caching**

Use `Pool(3)` plus maps keyed by chapter ID:

```dart
Future<String?> loadChapterThumbnail(ComicChapter chapter);
Future<Res<List<String>>> loadChapterPages(ComicChapter chapter);
```

Return `singleChapterPages` before calling the source loader. Add `ReaderChapter.fromComicChapters` and stop deriving reader chapters from the legacy Map.

- [ ] **Step 6: Verify and commit Task 4**

```powershell
flutter test test/detail_view_model_test.dart test/detail_view_model_favorite_test.dart
flutter analyze
git add lib/views/detail/detail_view_model.dart lib/views/reader test/detail_view_model_test.dart test/detail_view_model_favorite_test.dart
git commit -m "refactor: drive detail state from typed data"
```

---

### Task 5: Implement searchable metadata, JM-number navigation, and readable hero content

**Files:**
- Create: `lib/views/detail/detail_navigation.dart`
- Create: `lib/views/detail/widgets/detail_metadata.dart`
- Modify: `lib/views/detail/widgets/hero_header.dart:12-115`
- Modify: `lib/views/detail/widgets/info_overlay.dart:19-134`
- Modify: `lib/views/search/search_page.dart:31-275`
- Modify: `lib/main.dart:44-55,120-130`
- Modify: `test/routes_test.dart`
- Modify: `test/detail_theme_test.dart`
- Create: `test/search_direct_id_test.dart`

- [ ] **Step 1: Add failing navigation and hero tests**

Assert `/search/jm?q=Alice` initializes and submits the query; `JM123`, `jm123`, and `123` resolve to `/detail/jm/123`; light-mode title uses the on-image semantic color; `热度` and `人评价` are absent; and authors/categories/labels/JM number expose tappable semantics.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/routes_test.dart test/detail_theme_test.dart test/search_direct_id_test.dart`

- [ ] **Step 3: Implement query and direct-ID routing**

Extend `SearchPage` with `initialQuery`, initialize the controller, and schedule search after the first frame. Parse `q` in `main.dart`. Add:

```dart
String? directJmComicId(String input) {
  return RegExp(r'^\s*(?:jm)?\s*(\d+)\s*$', caseSensitive: false)
      .firstMatch(input)?.group(1);
}
```

Navigate before normal search when the selected source permits JM.

- [ ] **Step 4: Build metadata navigation and UI**

`detail_navigation.dart` builds encoded keyword/category routes. `DetailMetadata` renders clickable authors, optional rating, four metrics, JM number, categories, and labels using minimum 44px targets and semantics.

Replace hot/favorite/rating-count parameters in `HeroHeader` and `InfoOverlay`. Use `context.onImageColor` for all cover-overlay text.

- [ ] **Step 5: Verify and commit Task 5**

```powershell
flutter test test/routes_test.dart test/detail_theme_test.dart test/search_direct_id_test.dart
flutter analyze
git add lib/views/detail lib/views/search/search_page.dart lib/main.dart test/routes_test.dart test/detail_theme_test.dart test/search_direct_id_test.dart
git commit -m "feat: add searchable detail metadata"
```

---

### Task 6: Build chapter/comment tabs, real toolbar actions, equal buttons, and safe-area layout

**Files:**
- Create: `lib/views/detail/widgets/detail_tab_bar.dart`
- Create: `lib/views/detail/widgets/chapter_thumbnail.dart`
- Create: `lib/views/detail/widgets/comment_composer.dart`
- Modify: `lib/views/detail/detail_page.dart:46-593`
- Modify: `lib/views/detail/widgets/chapter_grid.dart`
- Modify: `lib/views/detail/widgets/comment_section.dart`
- Modify: `lib/views/detail/widgets/detail_app_bar.dart`
- Modify: `lib/views/detail/widgets/sticky_action_bar.dart`
- Modify: `test/detail_actions_test.dart`
- Create: `test/detail_tabs_test.dart`

- [ ] **Step 1: Add failing interaction/layout tests**

Test synopsis-before-tabs ordering, chapter default tab, comments loading on tap, true total in tab text, reply composer state, cached thumbnail invocation, non-null share/more callbacks, both buttons at 52px, one action-bar SafeArea, and dynamic bottom padding without a 96px spacer.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/detail_actions_test.dart test/detail_tabs_test.dart`

- [ ] **Step 3: Replace the long body with active-tab slivers**

Keep one `CustomScrollView`, add a pinned `SliverPersistentHeader`, and build only the active tab. Place recommendations after chapter content. Compute:

```dart
final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
final bodyBottomPadding = StickyActionBar.contentHeight + bottomInset + AppSpacing.md;
```

- [ ] **Step 4: Implement chapter/comment widgets**

`ChapterThumbnail` consumes the ViewModel-cached Future. `ChapterGrid` accepts typed chapters, range selection, explicit download action, and thumbnail callback. `CommentSection` renders reply previews and load-more. `CommentComposer` accepts reply target, sending/error state, cancel, and an async send callback that returns success.

- [ ] **Step 5: Implement real toolbar and bottom actions**

Use `share_plus` for title/author/source/id/JM-number text. More menu contains copy title, copy ID/JM number, author search, download management, and source homepage only. Use Clipboard and `url_launcher`.

Set:

```dart
static const buttonHeight = 52.0;
static const verticalPadding = 8.0;
static const contentHeight = buttonHeight + verticalPadding * 2;
```

Render favorite as horizontal icon/text.

- [ ] **Step 6: Verify and commit Task 6**

```powershell
flutter test test/detail_actions_test.dart test/detail_tabs_test.dart test/detail_theme_test.dart
flutter analyze
git add lib/views/detail test/detail_actions_test.dart test/detail_tabs_test.dart
git commit -m "feat: rebuild detail tabs and actions"
```

---

### Task 7: Move credentials to secure storage and repair JM AVS authentication

**Files:**
- Create: `lib/foundation/source_credential_store.dart`
- Modify: `lib/network/source_state.dart:32-76`
- Modify: `lib/network/jm/jm_headers.dart:74-94`
- Modify: `lib/network/jm/jm_network.dart:159-300,533-546`
- Modify: `lib/comic_source/comic_source.dart:189-194`
- Modify: `lib/comic_source/built_in/jm.dart:19-140`
- Modify: `lib/views/auth/login_page.dart:59-91`
- Create: `test/source_credential_store_test.dart`
- Create: `test/jm_auth_test.dart`

- [ ] **Step 1: Write failing secure-storage and AVS tests**

Test source-keyed credentials, migration/removal of legacy `source.data['account']`, login-response `s`, conditional AVS Cookie, one re-login maximum, AVS clearing on failure, and credential redaction in logs.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/source_credential_store_test.dart test/jm_auth_test.dart`

- [ ] **Step 3: Implement an injectable credential store**

```dart
abstract interface class SecretKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SourceCredentialStore {
  Future<void> saveCredentials(String sourceKey, String user, String password);
  Future<({String user, String password})?> readCredentials(String sourceKey);
  Future<void> saveSession(String sourceKey, String name, String value);
  Future<String?> readSession(String sourceKey, String name);
  Future<void> clearSource(String sourceKey);
}
```

Production wraps `FlutterSecureStorage`; tests use an in-memory map.

- [ ] **Step 4: Add AVS state and request headers**

Extend `JmState` with `avs`, `setAvs`, and `clearAvs`. Add `Cookie: AVS=<value>` only when nonempty. Parse login data as a Map, require nonempty `s`, persist credentials/AVS after success, restore AVS during source initialization, and use secure credentials for `reLogin`.

- [ ] **Step 5: Return login success to callers**

Change successful login navigation to `context.pop(true)`. Never log entered credentials or session values.

- [ ] **Step 6: Verify and commit Task 7**

```powershell
flutter test test/source_credential_store_test.dart test/jm_auth_test.dart test/source_settings_page_test.dart
flutter analyze
git add lib/foundation/source_credential_store.dart lib/network/source_state.dart lib/network/jm lib/comic_source lib/views/auth/login_page.dart test/source_credential_store_test.dart test/jm_auth_test.dart
git commit -m "fix: persist JM AVS securely"
```

---

### Task 8: Repair Pica authentication and centralize login-required UI

**Files:**
- Modify: `lib/network/picacg/picacg_headers.dart:27-76`
- Modify: `lib/network/picacg/picacg_network.dart:110-267`
- Modify: `lib/comic_source/built_in/picacg.dart:125-155`
- Modify: `lib/views/common/utils/source_login_guard.dart:10-50`
- Create: `lib/views/common/widgets/source_login_prompt.dart`
- Modify: `lib/views/home/home_page.dart`
- Modify: `lib/views/common/source_content_models.dart`
- Create: `test/picacg_auth_test.dart`
- Modify: `test/home_content_test.dart`
- Modify: `test/navigation_smoke_test.dart`

- [ ] **Step 1: Write failing auth and prompt tests**

Assert no hardcoded Host, signature includes query, auth 401 never re-logs, normal 401 re-logs/retries once, login tries unique configured/official/proxy bases, home emits one login prompt instead of raw Pica errors, and the guard returns true when `/login` pops true.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/picacg_auth_test.dart test/home_content_test.dart test/navigation_smoke_test.dart`

- [ ] **Step 3: Correct request construction and retry policy**

Remove `Host`. Sign `uri.path` plus query. Refactor requests around:

```dart
Future<Res<Map<String, dynamic>>> request(
  String method,
  Uri uri, {
  Map<String, String>? data,
  bool requiresAuth = true,
  bool allowRelogin = true,
  bool retried = false,
});
```

Only non-auth requests re-login; retry the original request once.

- [ ] **Step 4: Implement login endpoint fallback**

Build an ordered deduplicated list from configured base, official base, and go2778. Sign each URI independently. Save the successful base, Token, profile, and secure credentials.

- [ ] **Step 5: Centralize login-required UI**

Await `context.push<bool>('/login?...')` in `ensureSourceLoggedIn`. Add `SourceLoginPrompt`. Home skips Pica loaders while logged out and emits one typed login-required result rather than `latest/popular: 未登录` errors.

- [ ] **Step 6: Verify and commit Task 8**

```powershell
flutter test test/picacg_auth_test.dart test/home_content_test.dart test/navigation_smoke_test.dart
flutter analyze
git add lib/network/picacg lib/comic_source/built_in/picacg.dart lib/views/common lib/views/home test/picacg_auth_test.dart test/home_content_test.dart test/navigation_smoke_test.dart
git commit -m "fix: repair Pica login and auth prompts"
```

---

### Task 9: Consolidate the home ranking entry and use source-aware ranking loaders

**Files:**
- Modify: `lib/views/home/widgets/home_tool_bar.dart:16-47`
- Modify: `lib/views/ranking/ranking_page.dart`
- Modify: `lib/comic_source/built_in/jm.dart`
- Modify: `lib/comic_source/built_in/picacg.dart`
- Modify: `test/navigation_smoke_test.dart`
- Create: `test/ranking_page_test.dart`

- [ ] **Step 1: Write failing toolbar and ranking tests**

Assert toolbar labels equal:

```dart
['排行榜', '影视', '以图搜图', '收藏库', '下载']
```

Assert JM receives `mr/mp/mv`, Pica receives `dd/ld/da`, logged-out Pica shows the prompt, and JM data remains visible when Pica fails.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/navigation_smoke_test.dart test/ranking_page_test.dart`

- [ ] **Step 3: Populate real ranking contracts**

```dart
// JM
{'latest': 'mr', 'hot': 'mp', 'rating': 'mv'}
// Pica
{'latest': 'dd', 'hot': 'ld', 'rating': 'da'}
```

Use each source's real search/ranking endpoint and preserve `Res` errors.

- [ ] **Step 4: Rebuild ranking aggregation**

Request sources independently, retain successful sections, show `SourceLoginPrompt` for logged-out Pica, and expose retry per failed source. Replace the two home entries with one `/ranking` entry.

- [ ] **Step 5: Verify and commit Task 9**

```powershell
flutter test test/navigation_smoke_test.dart test/ranking_page_test.dart
flutter analyze
git add lib/views/home/widgets/home_tool_bar.dart lib/views/ranking lib/comic_source/built_in test/navigation_smoke_test.dart test/ranking_page_test.dart
git commit -m "feat: consolidate source rankings"
```

---

### Task 10: Replace the placeholder video page with JM video APIs and a real player

**Files:**
- Create: `lib/network/jm/jm_video_models.dart`
- Modify: `lib/network/jm/jm_network.dart`
- Rewrite: `lib/views/video/video_page.dart`
- Create: `lib/views/video/video_player_page.dart`
- Modify: `lib/main.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `test/jm_video_test.dart`
- Create: `test/video_page_test.dart`

- [ ] **Step 1: Add player dependencies**

Run: `flutter pub add video_player webview_flutter`
Expected: compatible versions are added without removing existing dependencies.

- [ ] **Step 2: Write failing video parser/page tests**

Test `id/title/photo/tags/backlink`, detail `video_src/full_url/related_videos`, category query parameters, pagination, search, route construction, and WebView/browser fallback when direct playback is absent.

- [ ] **Step 3: Run tests and verify failure**

Run: `flutter test test/jm_video_test.dart test/video_page_test.dart`

- [ ] **Step 4: Implement JM video models and endpoints**

Create immutable `JmVideoItem` and `JmVideoDetail`. Add:

```dart
Future<Res<({List<JmVideoItem> items, int total})>> getVideos({
  int page = 1, String videoType = '', String searchQuery = '',
});
Future<Res<JmVideoDetail>> getVideoDetail(String videoId);
Future<Res<List<JmVideoItem>>> getLatestHanime();
```

Call `videos`, `video?vid=...`, `video?id=...` fallback, and `latest_hanime`. Normalize covers through the JM image host.

- [ ] **Step 5: Build list and player pages**

`VideoPage` uses `全部/小电影/H动漫/Cos`, real search, refresh, page counters, and load-more; it must not call comic search.

`VideoPlayerPage` initializes `VideoPlayerController.networkUrl` for `videoSrc`. On failure use `WebViewWidget` with a JavaScript channel for extracted video URLs; otherwise show an external-browser action. Dispose controllers and restore orientation.

- [ ] **Step 6: Verify and commit Task 10**

```powershell
flutter test test/jm_video_test.dart test/video_page_test.dart test/theme_application_test.dart
flutter analyze
git add pubspec.yaml pubspec.lock lib/network/jm lib/views/video lib/main.dart test/jm_video_test.dart test/video_page_test.dart
git commit -m "feat: add JM video browsing and playback"
```

---

### Task 11: Complete reverse image search, inject iOS permissions, and run acceptance tests

**Files:**
- Create: `lib/foundation/sauce_nao_config_store.dart`
- Modify: `lib/foundation/sauce_nao_search.dart`
- Rewrite: `lib/views/image_search/image_search_page.dart`
- Modify: `codemagic.yaml`
- Create: `test/sauce_nao_search_test.dart`
- Create: `test/image_search_page_test.dart`
- Modify: `test/theme_source_policy_test.dart`
- Modify: `test/navigation_smoke_test.dart`

- [ ] **Step 1: Write failing SauceNAO/config/page tests**

Test absence of a default Key constant, secure-Key precedence over `String.fromEnvironment`, typed missing-key/403/429/network errors, original results retained without internal matches, external-link launch, picker/permission errors, and source-policy rejection of credential-like constants.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/sauce_nao_search_test.dart test/image_search_page_test.dart test/theme_source_policy_test.dart`

- [ ] **Step 3: Implement secure config and typed errors**

```dart
class SauceNaoConfigStore {
  Future<String?> readApiKey();
  Future<void> saveApiKey(String value);
  Future<void> clearApiKey();
}

enum SauceNaoErrorKind { missingKey, invalidKey, rateLimited, network, malformed }
```

Remove `kDefaultApiKey`, require an injected Key, preserve original results, and make `bestTitle` sort a copy rather than mutate caller data.

- [ ] **Step 4: Rebuild the image-search page**

Render selected image, key configuration, original SauceNAO result cards, and a separate internal JM/Pica match section. Provide gallery, camera, SauceNAO setup, and soutubot actions. Map `PlatformException` and typed service errors to distinct messages. Never log the Key.

- [ ] **Step 5: Add idempotent Codemagic iOS permissions**

After `flutter create . --platforms=ios`, execute:

```bash
/usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryUsageDescription string 选择漫画图片用于以图搜图" ios/Runner/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :NSPhotoLibraryUsageDescription 选择漫画图片用于以图搜图" ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string 拍摄漫画图片用于以图搜图" ios/Runner/Info.plist 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :NSCameraUsageDescription 拍摄漫画图片用于以图搜图" ios/Runner/Info.plist
```

- [ ] **Step 6: Run focused tests**

```powershell
flutter test test/sauce_nao_search_test.dart test/image_search_page_test.dart test/navigation_smoke_test.dart test/theme_source_policy_test.dart
```

- [ ] **Step 7: Run the full acceptance suite**

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
git diff --check
```

Expected: formatting unchanged, no analyzer issues, all tests pass, and diff check is clean.

- [ ] **Step 8: Scan for credentials and removed placeholders**

```powershell
Get-ChildItem lib,test -Recurse -File -Filter '*.dart' | Select-String -Pattern '665000|hhxxttxs|devin-session-token|kDefaultApiKey|人评价|热度' -CaseSensitive:$false
```

Expected: no credential matches and no production-detail matches for removed labels.

- [ ] **Step 9: Perform opt-in live login smoke tests**

Read `JOYCOMIC_TEST_USER` and `JOYCOMIC_TEST_PASSWORD` only from process environment in an untracked diagnostic command. Verify JM login/session/detail/comment-list and Pica login/profile/detail/comment/reply. Redact AVS, Token, password, authorization, nonce, and signature. If variables are absent, report this smoke test as not run without failing unit tests.

- [ ] **Step 10: Commit Task 11 and review coverage**

```powershell
git add lib/foundation/sauce_nao_config_store.dart lib/foundation/sauce_nao_search.dart lib/views/image_search codemagic.yaml test/sauce_nao_search_test.dart test/image_search_page_test.dart test/theme_source_policy_test.dart test/navigation_smoke_test.dart
git commit -m "feat: complete reverse image search and iOS setup"
```

Coverage check:

```text
Tasks 1-6: issues 1-16 except authentication prompting
Tasks 7-8: issues 14 and 17
Task 9: issue 18
Task 10: issue 19 video
Task 11: issue 19 image search and final verification
```

Do not push. Run branch completion review, merge locally into `main`, then make the single final GitHub push requested by the user.
