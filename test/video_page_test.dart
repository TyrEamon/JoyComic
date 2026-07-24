import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/network/jm/jm_video_models.dart';
import 'package:joycomic/network/res.dart';
import 'package:joycomic/views/video/video_page.dart';
import 'package:joycomic/views/video/video_player_page.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  test(
    'fullscreen policy changes orientation only after an explicit toggle',
    () async {
      final orientationCalls = <List<DeviceOrientation>>[];
      final uiModeCalls = <SystemUiMode>[];

      await applyVideoFullscreenState(
        fullscreen: true,
        restoreOrientations: const <DeviceOrientation>[
          DeviceOrientation.portraitUp,
        ],
        setOrientations: (orientations) async =>
            orientationCalls.add(orientations),
        setUiMode: (mode) async => uiModeCalls.add(mode),
      );
      await applyVideoFullscreenState(
        fullscreen: false,
        restoreOrientations: const <DeviceOrientation>[
          DeviceOrientation.portraitUp,
        ],
        setOrientations: (orientations) async =>
            orientationCalls.add(orientations),
        setUiMode: (mode) async => uiModeCalls.add(mode),
      );

      expect(orientationCalls, <List<DeviceOrientation>>[
        <DeviceOrientation>[
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        <DeviceOrientation>[DeviceOrientation.portraitUp],
      ]);
      expect(uiModeCalls, <SystemUiMode>[
        SystemUiMode.immersiveSticky,
        SystemUiMode.edgeToEdge,
      ]);
    },
  );

  test('navigation approvals reject stale generations and revoke failures', () {
    final tracker = NavigationApprovalTracker();
    final first = tracker.beginRequest();
    tracker.approve('https://18comic.vip/old', first);

    final second = tracker.beginRequest();
    expect(tracker.consume('https://18comic.vip/old'), isFalse);
    tracker.approve('https://18comic.vip/current', second);
    expect(tracker.consume('https://18comic.vip/current'), isTrue);
    expect(tracker.isLoaded('https://18comic.vip/current'), isTrue);

    final third = tracker.beginRequest();
    expect(tracker.isLoaded('https://18comic.vip/current'), isFalse);
    tracker.approve('https://18comic.vip/failure', third);
    tracker.revoke('https://18comic.vip/failure', third);
    expect(tracker.consume('https://18comic.vip/failure'), isFalse);
  });

  test('only main-frame navigation enters the verified load flow', () {
    expect(
      isMainFrameNavigation(
        const NavigationRequest(
          url: 'https://18comic.vip/frame',
          isMainFrame: false,
        ),
      ),
      isFalse,
    );
    expect(
      isMainFrameNavigation(
        const NavigationRequest(
          url: 'https://18comic.vip/page',
          isMainFrame: true,
        ),
      ),
      isTrue,
    );
  });

  test('video WebView enables inline autoplay on iOS', () {
    expect(videoWebViewPlaybackPolicy.allowsInlineMediaPlayback, isTrue);
    expect(videoWebViewPlaybackPolicy.requiresUserAction, isFalse);
  });

  test('iOS uses FVP texture while macOS keeps the platform view', () {
    expect(nativeVideoViewType(TargetPlatform.iOS), VideoViewType.textureView);
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
    expect(controller.viewType, VideoViewType.textureView);
  });

  test('native video diagnostics describe media and render state', () {
    const value = VideoPlayerValue(
      duration: Duration(seconds: 12),
      size: Size(1920, 1080),
      isInitialized: true,
      isPlaying: true,
    );

    final description = describeNativeVideoState(
      value,
      viewType: VideoViewType.platformView,
      source:
          'https://cdn.example/video/index.m3u8?token=secret#private-fragment',
    );

    expect(
      description,
      contains('source=https://cdn.example/video/index.m3u8'),
    );
    expect(description, isNot(contains('secret')));
    expect(description, isNot(contains('private-fragment')));
    expect(description, contains('view=platformView'));
    expect(description, contains('size=1920.0x1080.0'));
    expect(description, contains('aspect=1.777'));
    expect(description, contains('duration=12000ms'));
    expect(description, contains('playing=true'));
    expect(description, contains('buffering=false'));
  });

  test(
    'direct HLS HTML embeds a local player without leaking query values',
    () {
      const source = 'https://cdn.example/a.m3u8?token=secret';
      final html = buildDirectHlsVideoHtml(source);
      expect(html, contains('<video'));
      expect(html, contains('playsinline'));
      expect(html, contains('loadedmetadata'));
      expect(html, isNot(contains('token=secret')));
    },
  );

  test('direct HLS only becomes visible after a media-ready event', () {
    expect(isDirectHlsReadyEvent('loadedmetadata'), isTrue);
    expect(isDirectHlsReadyEvent('canplay'), isTrue);
    expect(isDirectHlsReadyEvent('playing'), isTrue);
    expect(isDirectHlsReadyEvent('waiting'), isFalse);
    expect(isDirectHlsReadyEvent('stalled'), isFalse);
  });

  testWidgets('video loading surface covers the white platform view', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: VideoLoadingSurface(message: '正在获取视频地址')),
    );

    expect(find.text('正在获取视频地址'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final surface = tester.widget<ColoredBox>(find.byType(ColoredBox).last);
    expect(surface.color, Colors.black);
  });

  test('zero-size initialized media is treated as non-renderable', () {
    const value = VideoPlayerValue(
      duration: Duration(minutes: 5),
      size: Size.zero,
      isInitialized: true,
      isBuffering: true,
    );

    expect(isNativeVideoRenderable(value), isFalse);
  });

  test('FVP audio-only placeholder texture is treated as non-renderable', () {
    const value = VideoPlayerValue(
      duration: Duration(minutes: 5),
      size: Size(16, 16),
      isInitialized: true,
    );

    expect(isNativeVideoRenderable(value), isFalse);
  });

  test('quality changes clamp a saved position to the new duration', () {
    expect(
      clampVideoPosition(
        const Duration(seconds: 12),
        const Duration(seconds: 30),
      ),
      const Duration(seconds: 12),
    );
    expect(
      clampVideoPosition(
        const Duration(seconds: 40),
        const Duration(seconds: 30),
      ),
      const Duration(seconds: 30),
    );
  });

  test('public HTTP subframes require resolved-public approval', () async {
    final checkedHosts = <String>[];
    Future<bool> approve(Uri uri) async {
      checkedHosts.add(uri.host);
      return true;
    }

    expect(
      await shouldAllowVideoSubframeNavigation(
        const NavigationRequest(
          url: 'https://player.example/embed/123',
          isMainFrame: false,
        ),
        remoteUriChecker: approve,
      ),
      isTrue,
    );
    expect(checkedHosts, <String>['player.example']);
    expect(
      await shouldAllowVideoSubframeNavigation(
        const NavigationRequest(
          url: 'http://127.0.0.1/private',
          isMainFrame: false,
        ),
        remoteUriChecker: approve,
      ),
      isFalse,
    );
    expect(
      await shouldAllowVideoSubframeNavigation(
        const NavigationRequest(url: 'javascript:alert(1)', isMainFrame: false),
        remoteUriChecker: approve,
      ),
      isFalse,
    );
    expect(checkedHosts, <String>[
      'player.example',
    ], reason: 'unsafe URLs must be rejected before DNS approval');
  });

  test('async resource completion requires identity and generation', () {
    final current = Object();
    final stale = Object();
    expect(isCurrentGenerationResource(current, current, 2, 2), isTrue);
    expect(isCurrentGenerationResource(stale, current, 2, 2), isFalse);
    expect(isCurrentGenerationResource(current, current, 1, 2), isFalse);
  });

  test('WebView keys isolate different video URLs', () {
    expect(
      videoWebViewKey('https://18comic.vip/video/a'),
      videoWebViewKey('https://18comic.vip/video/a'),
    );
    expect(
      videoWebViewKey('https://18comic.vip/video/a'),
      isNot(videoWebViewKey('https://18comic.vip/video/b')),
    );
  });
  testWidgets('video page uses JM categories, search, and pagination', (
    tester,
  ) async {
    final requests = <String>[];
    Future<Res<({List<JmVideoItem> items, int total})>> loader({
      int page = 1,
      String videoType = '',
      String searchQuery = '',
    }) async {
      requests.add('$page|$videoType|$searchQuery');
      return Res((
        items: <JmVideoItem>[
          JmVideoItem(
            id: 'v$page',
            title: 'Video $page',
            photo: '',
            tags: const <String>[],
            backlink: 'https://18comic.vip/video/v$page',
          ),
        ],
        total: 40,
      ));
    }

    await tester.pumpWidget(MaterialApp(home: VideoPage(loader: loader)));
    await tester.pumpAndSettle();
    expect(requests, contains('1||'));
    expect(find.text('Video 1'), findsOneWidget);

    await tester.tap(find.text('H动漫'));
    await tester.pumpAndSettle();
    expect(requests, contains('1|video|H動漫'));

    await tester.enterText(
      find.byKey(const Key('video-search-field')),
      'keyword',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(requests, contains('1|video|keyword'));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('video-load-more')));
    await tester.pumpAndSettle();
    expect(requests, contains('2|video|keyword'));
    expect(find.text('Video 2'), findsOneWidget);
  });

  testWidgets('video card opens the dedicated player route', (tester) async {
    String? openedId;
    final router = GoRouter(
      initialLocation: '/video',
      routes: <RouteBase>[
        GoRoute(
          path: '/video',
          builder: (_, __) => VideoPage(
            loader: ({page = 1, videoType = '', searchQuery = ''}) async =>
                Res((
                  items: <JmVideoItem>[
                    JmVideoItem(
                      id: 'route-id',
                      title: 'Route Video',
                      photo: '',
                      tags: <String>[],
                      backlink: 'https://18comic.vip/video/route-id',
                    ),
                  ],
                  total: 1,
                )),
          ),
        ),
        GoRoute(
          path: '/video/player/:id',
          builder: (_, state) {
            openedId = state.pathParameters['id'];
            return const Scaffold(body: Text('player-opened'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Route Video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Route Video'));
    await tester.pumpAndSettle();

    expect(openedId, 'route-id');
    expect(find.text('player-opened'), findsOneWidget);
  });

  testWidgets('player uses WebView fallback when direct playback is absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          videoId: 'fallback-id',
          loader: (_) async => Res(
            JmVideoDetail(
              id: 'fallback-id',
              title: 'Fallback Video',
              description: '',
              photo: '',
              videoSrc: '',
              fullUrl: 'https://18comic.vip/video/fallback-id',
              tags: <String>[],
              backlink: '',
              relatedVideos: <JmVideoItem>[],
            ),
          ),
          webViewBuilder: (_, url, __) => Text('web:$url'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('web:https://18comic.vip/video/fallback-id'),
      findsOneWidget,
    );
    expect(find.text('浏览器打开'), findsOneWidget);
  });

  testWidgets('native playback failure switches to WebView fallback', (
    tester,
  ) async {
    VoidCallback? failPlayback;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          videoId: 'direct-id',
          loader: (_) async => Res(
            JmVideoDetail(
              id: 'direct-id',
              title: 'Direct Video',
              description: '',
              photo: '',
              videoSrc: 'https://cdn.example/video.m3u8',
              fullUrl: 'https://18comic.vip/video/direct-id',
              tags: <String>[],
              backlink: '',
              relatedVideos: <JmVideoItem>[],
            ),
          ),
          directPlayerBuilder: (_, __, onFailure) {
            failPlayback = onFailure;
            return const Text('native-player');
          },
          webViewBuilder: (_, url, __) => Text('web:$url'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('native-player'), findsOneWidget);

    failPlayback!();
    await tester.pumpAndSettle();
    expect(
      find.text('web:https://18comic.vip/video/direct-id'),
      findsOneWidget,
    );
  });

  testWidgets('direct HLS failure returns to the detail WebView extractor', (
    tester,
  ) async {
    VoidCallback? failPlayback;
    VoidCallback? failDirectHls;
    final directFallbackSources = <String>[];
    const manifest = '''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=5200000,RESOLUTION=1920x1080
1080/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2600000,RESOLUTION=1280x720
720/index.m3u8
''';
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          hlsManifestLoader: (_) async => manifest,
          videoId: 'direct-fallback-id',
          loader: (_) async => Res(
            JmVideoDetail(
              id: 'direct-fallback-id',
              title: 'Direct fallback',
              description: '',
              photo: '',
              videoSrc: 'https://cdn.example/video.m3u8?token=secret',
              fullUrl: 'https://18comic.vip/video/direct-fallback-id',
              tags: const <String>[],
              backlink: '',
              relatedVideos: const <JmVideoItem>[],
            ),
          ),
          directPlayerBuilder: (_, __, onFailure) {
            failPlayback = onFailure;
            return const Text('native-player');
          },
          directHlsWebViewBuilder: (_, source, onFailure) {
            directFallbackSources.add(source);
            failDirectHls = onFailure;
            return const Text('direct-hls-web');
          },
          webViewBuilder: (_, url, __) => Text('web:$url'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    failPlayback!();
    await tester.pumpAndSettle();

    expect(find.text('direct-hls-web'), findsOneWidget);
    expect(
      directFallbackSources.last,
      'https://cdn.example/video.m3u8?token=secret',
    );

    await tester.tap(find.text('清晰度：自动'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '720p'));
    await tester.pumpAndSettle();

    expect(directFallbackSources.last, 'https://cdn.example/720/index.m3u8');

    failDirectHls!();
    await tester.pumpAndSettle();
    expect(
      find.text('web:https://18comic.vip/video/direct-fallback-id'),
      findsOneWidget,
    );
  });

  testWidgets('HLS master playlist exposes real quality choices', (
    tester,
  ) async {
    final directSources = <String>[];
    const manifest = '''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=640x360
360/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5200000,RESOLUTION=1920x1080
1080/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2600000,RESOLUTION=1280x720
720/index.m3u8
''';

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          hlsManifestLoader: (_) async => manifest,
          videoId: 'quality-id',
          loader: (_) async => Res(
            JmVideoDetail(
              id: 'quality-id',
              title: 'Quality Video',
              description: '',
              photo: '',
              videoSrc: 'https://cdn.example/video/master.m3u8',
              fullUrl: 'https://18comic.vip/video/quality-id',
              tags: const <String>[],
              backlink: '',
              relatedVideos: const <JmVideoItem>[],
            ),
          ),
          directPlayerBuilder: (_, source, __) {
            directSources.add(source);
            return const Text('quality-player');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('清晰度：自动'), findsOneWidget);
    expect(directSources.last, 'https://cdn.example/video/master.m3u8');

    await tester.tap(find.text('清晰度：自动'));
    await tester.pumpAndSettle();
    expect(find.text('1080p'), findsOneWidget);

    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '1080p'));
    await tester.pumpAndSettle();
    expect(find.text('清晰度：1080p'), findsOneWidget);
    expect(directSources.last, 'https://cdn.example/video/1080/index.m3u8');
  });

  testWidgets('relative API video source resolves against the video page', (
    tester,
  ) async {
    String? directSource;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          videoId: 'relative-source',
          loader: (_) async => Res(
            JmVideoDetail(
              id: 'relative-source',
              title: 'Relative source',
              description: '',
              photo: '',
              videoSrc: '/media/movie.m3u8',
              fullUrl: '/video/relative-source',
              tags: const <String>[],
              backlink: '',
              relatedVideos: const <JmVideoItem>[],
            ),
          ),
          directPlayerBuilder: (_, source, __) {
            directSource = source;
            return Text('native:$source');
          },
          webViewBuilder: (_, url, __) => Text('web:$url'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(directSource, 'https://18comic.vip/media/movie.m3u8');
    expect(
      find.text('native:https://18comic.vip/media/movie.m3u8'),
      findsOneWidget,
    );
  });

  test('bridge parser accepts strict public HTTP JSON only', () {
    const pageUrl = 'https://18comic.vip/video/v1';
    expect(
      parseExtractedVideoMessage(
        '{"type":"video_src","src":"/media/video.m3u8"}',
        pageUrl: pageUrl,
      ),
      'https://18comic.vip/media/video.m3u8',
    );
    expect(
      parseExtractedVideoMessage(
        'https://cdn.example/video.m3u8',
        pageUrl: pageUrl,
      ),
      isNull,
    );
    expect(
      parseExtractedVideoMessage(
        '{"type":"video_src","src":"file:///private/video.mp4"}',
        pageUrl: pageUrl,
      ),
      isNull,
    );
    expect(
      parseExtractedVideoMessage(
        '{"type":"video_src","src":"http://127.0.0.1/video.mp4"}',
        pageUrl: pageUrl,
      ),
      isNull,
    );
    for (final source in const <String>[
      'https://[::1]/video.mp4',
      'https://[::ffff:127.0.0.1]/video.mp4',
      'https://2130706433/video.mp4',
      'https://127.1/video.mp4',
      'https://0177.0.0.1/video.mp4',
      'https://0x7f.0.0.1/video.mp4',
    ]) {
      expect(
        parseExtractedVideoMessage(
          '{"type":"video_src","src":"$source"}',
          pageUrl: pageUrl,
        ),
        isNull,
      );
    }
    expect(
      parseExtractedVideoMessage(
        '{"type":"log","src":"https://cdn.example/video.mp4"}',
        pageUrl: pageUrl,
      ),
      isNull,
    );
    expect(
      parseExtractedVideoMessage(
        '{"type":"video_src","src":"https://cdn.example/video.mp4"}',
        pageUrl: pageUrl,
        expectedNonce: 'trusted-nonce',
      ),
      isNull,
    );
    expect(
      parseExtractedVideoMessage(
        '{"type":"video_src","src":"https://cdn.example/video.mp4","token":"trusted-nonce"}',
        pageUrl: pageUrl,
        expectedNonce: 'trusted-nonce',
      ),
      'https://cdn.example/video.mp4',
    );
  });

  test('resolved public URL checks reject local IP literals', () async {
    expect(
      await isResolvedPublicHttpUri(Uri.parse('https://127.0.0.1/video.mp4')),
      isFalse,
    );
    expect(
      await isResolvedPublicHttpUri(
        Uri.parse('https://[::ffff:127.0.0.1]/video.mp4'),
      ),
      isFalse,
    );
  });

  test('trusted JM playback hosts do not depend on DNS preflight', () async {
    var dnsChecks = 0;
    Future<bool> unavailableDns(Uri _) async {
      dnsChecks += 1;
      return false;
    }

    expect(
      await isJmPlaybackRemoteUriAllowed(
        Uri.parse(
          'https://ms18comic-2.iiooxx.rocks/video_path_m3u8/6638/index.m3u8',
        ),
        dnsChecker: unavailableDns,
      ),
      isTrue,
    );
    expect(
      await isJmPlaybackRemoteUriAllowed(
        Uri.parse('https://18comic.vip/video/6638'),
        dnsChecker: unavailableDns,
      ),
      isTrue,
    );
    expect(dnsChecks, 0);
  });

  test(
    'unknown playback hosts remain DNS checked and private URLs fail',
    () async {
      var dnsChecks = 0;
      Future<bool> unavailableDns(Uri _) async {
        dnsChecks += 1;
        return false;
      }

      expect(
        await isJmPlaybackRemoteUriAllowed(
          Uri.parse('https://unknown.example/video.m3u8'),
          dnsChecker: unavailableDns,
        ),
        isFalse,
      );
      expect(
        await isJmPlaybackRemoteUriAllowed(
          Uri.parse('http://127.0.0.1/private.m3u8'),
          dnsChecker: unavailableDns,
        ),
        isFalse,
      );
      expect(dnsChecks, 1);
    },
  );

  test('WebView navigation remains inside trusted JM public hosts', () {
    final initial = Uri.parse('https://18comic.vip/video/v1');
    expect(isTrustedJmPageUri(initial, initial: initial), isTrue);
    expect(
      isTrustedJmPageUri(
        Uri.parse('https://jmcomic1.cc/video/v1'),
        initial: initial,
      ),
      isTrue,
    );
    expect(
      isTrustedJmPageUri(
        Uri.parse('https://evil.example/video/v1'),
        initial: initial,
      ),
      isFalse,
    );
    expect(
      isTrustedJmPageUri(
        Uri.parse('http://127.0.0.1/video/v1'),
        initial: initial,
      ),
      isFalse,
    );
    final untrustedInitial = Uri.parse('https://evil.example/video/v1');
    expect(
      isTrustedJmPageUri(untrustedInitial, initial: untrustedInitial),
      isFalse,
    );
  });

  test('video extraction script observes dynamic DOM and nested payloads', () {
    expect(videoExtractionJavaScript, contains('MutationObserver'));
    expect(videoExtractionJavaScript, contains('setInterval'));
    expect(
      videoExtractionJavaScript,
      contains('value.data && value.data.video && value.data.video.video_src'),
    );
  });

  test('only main-frame or unknown WebView errors fail extraction', () {
    expect(
      shouldFailWebViewForResourceError(
        const WebResourceError(
          errorCode: -1,
          description: 'subresource',
          isForMainFrame: false,
        ),
      ),
      isFalse,
    );
    expect(
      shouldFailWebViewForResourceError(
        const WebResourceError(
          errorCode: -1,
          description: 'main frame',
          isForMainFrame: true,
        ),
      ),
      isTrue,
    );
    expect(
      shouldFailWebViewForResourceError(
        const WebResourceError(errorCode: -1, description: 'unknown frame'),
      ),
      isTrue,
    );
  });

  testWidgets('invalid API direct source falls back without native playback', (
    tester,
  ) async {
    var nativeBuilt = false;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          videoId: 'unsafe-source',
          loader: (_) async => Res(
            JmVideoDetail(
              id: 'unsafe-source',
              title: 'Unsafe',
              description: '',
              photo: '',
              videoSrc: 'file:///private/video.mp4',
              fullUrl: 'https://18comic.vip/video/unsafe-source',
              tags: <String>[],
              backlink: '',
              relatedVideos: <JmVideoItem>[],
            ),
          ),
          directPlayerBuilder: (_, __, ___) {
            nativeBuilt = true;
            return const Text('unsafe-native');
          },
          webViewBuilder: (_, __, ___) => const Text('safe-web-fallback'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(nativeBuilt, isFalse);
    expect(find.text('safe-web-fallback'), findsOneWidget);
  });

  testWidgets('a failed extracted source is rejected without a playback loop', (
    tester,
  ) async {
    const failedSource = 'https://cdn.example/failed.m3u8';
    const replacementSource = 'https://cdn.example/replacement.m3u8';
    VoidCallback? failPlayback;
    ValueChanged<String>? extract;
    final directSources = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          videoId: 'loop-id',
          loader: (_) async => Res(
            JmVideoDetail(
              id: 'loop-id',
              title: 'Loop guard',
              description: '',
              photo: '',
              videoSrc: failedSource,
              fullUrl: 'https://18comic.vip/video/loop-id',
              tags: <String>[],
              backlink: '',
              relatedVideos: <JmVideoItem>[],
            ),
          ),
          directPlayerBuilder: (_, source, onFailure) {
            directSources.add(source);
            failPlayback = onFailure;
            return Text('native:$source');
          },
          webViewBuilder: (_, __, onExtracted) {
            extract = onExtracted;
            return const Text('extracting-web');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('native:$failedSource'), findsOneWidget);

    failPlayback!();
    await tester.pump();
    expect(find.text('extracting-web'), findsOneWidget);

    extract!(failedSource);
    await tester.pump();
    expect(find.text('extracting-web'), findsOneWidget);
    expect(
      directSources.where((source) => source == failedSource),
      hasLength(1),
    );

    extract!(replacementSource);
    await tester.pumpAndSettle();
    expect(find.text('native:$replacementSource'), findsOneWidget);
  });

  testWidgets('external launcher false result shows an actionable error', (
    tester,
  ) async {
    Uri? launched;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          videoId: 'external-id',
          loader: (_) async => Res(
            JmVideoDetail(
              id: 'external-id',
              title: 'External',
              description: '',
              photo: '',
              videoSrc: '',
              fullUrl: 'https://18comic.vip/video/external-id',
              tags: <String>[],
              backlink: '',
              relatedVideos: <JmVideoItem>[],
            ),
          ),
          webViewBuilder: (_, __, ___) => const Text('external-web'),
          externalLauncher: (uri) async {
            launched = uri;
            return false;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '浏览器打开'));
    await tester.pump();

    expect(launched.toString(), 'https://18comic.vip/video/external-id');
    expect(find.text('无法打开外部浏览器'), findsOneWidget);
  });

  testWidgets('external launcher exceptions show an actionable error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          videoId: 'external-throw',
          loader: (_) async => Res(
            JmVideoDetail(
              id: 'external-throw',
              title: 'External throw',
              description: '',
              photo: '',
              videoSrc: '',
              fullUrl: 'https://18comic.vip/video/external-throw',
              tags: <String>[],
              backlink: '',
              relatedVideos: <JmVideoItem>[],
            ),
          ),
          webViewBuilder: (_, __, ___) => const Text('external-web'),
          externalLauncher: (_) => throw StateError('launch failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '浏览器打开'));
    await tester.pump();

    expect(find.text('无法打开外部浏览器'), findsOneWidget);
  });

  testWidgets('player keeps caller orientation until dispose', (tester) async {
    const channel = MethodChannel('flutter/platform', JSONMethodCodec());
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          videoId: 'orientation-id',
          restoreOrientations: const <DeviceOrientation>[
            DeviceOrientation.portraitDown,
          ],
          loader: (_) async => Res(
            JmVideoDetail(
              id: 'orientation-id',
              title: 'Orientation',
              description: '',
              photo: '',
              videoSrc: '',
              fullUrl: 'https://18comic.vip/video/orientation-id',
              tags: <String>[],
              backlink: '',
              relatedVideos: <JmVideoItem>[],
            ),
          ),
          webViewBuilder: (_, __, ___) => const Text('orientation-web'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    final orientationCalls = calls
        .where((call) => call.method == 'SystemChrome.setPreferredOrientations')
        .toList();
    expect(orientationCalls, hasLength(1));
    expect(orientationCalls.single.arguments, <String>[
      'DeviceOrientation.portraitDown',
    ]);
  });

  testWidgets('stale detail results cannot overwrite a newer video', (
    tester,
  ) async {
    final oldResult = Completer<Res<JmVideoDetail>>();
    final newResult = Completer<Res<JmVideoDetail>>();
    Future<Res<JmVideoDetail>> loader(String id) {
      return id == 'old' ? oldResult.future : newResult.future;
    }

    Res<JmVideoDetail> detail(String id) => Res(
      JmVideoDetail(
        id: id,
        title: id,
        description: '',
        photo: '',
        videoSrc: '',
        fullUrl: 'https://18comic.vip/video/$id',
        tags: <String>[],
        backlink: '',
        relatedVideos: <JmVideoItem>[],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          videoId: 'old',
          loader: loader,
          webViewBuilder: (_, __, ___) => const Text('stale-web'),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          videoId: 'new',
          loader: loader,
          webViewBuilder: (_, __, ___) => const Text('stale-web'),
        ),
      ),
    );
    oldResult.complete(detail('old'));
    await tester.pump();
    expect(find.text('old'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    newResult.complete(detail('new'));
    await tester.pumpAndSettle();
    expect(find.text('new'), findsOneWidget);
    expect(find.text('old'), findsNothing);
  });

  testWidgets('detail loader exceptions leave a recoverable fallback state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          remoteUriChecker: (_) async => true,
          videoId: 'throws',
          loader: (_) async => throw StateError('network down'),
          webViewBuilder: (_, __, ___) => const Text('exception-web'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('视频详情加载失败'), findsOneWidget);
    expect(find.text('exception-web'), findsOneWidget);
  });

  testWidgets('concurrent extracted sources serialize until current fails', (
    tester,
  ) async {
    const sourceA = 'https://cdn.example/a.m3u8';
    const sourceB = 'https://cdn.example/b.m3u8';
    final checks = <String, Completer<bool>>{};
    ValueChanged<String>? extract;
    VoidCallback? failPlayback;

    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlayerPage(
          videoId: 'concurrent',
          remoteUriChecker: (uri) {
            return (checks[uri.toString()] ??= Completer<bool>()).future;
          },
          loader: (_) async => Res(
            JmVideoDetail(
              id: 'concurrent',
              title: 'Concurrent',
              description: '',
              photo: '',
              videoSrc: '',
              fullUrl: 'https://18comic.vip/video/concurrent',
              tags: <String>[],
              backlink: '',
              relatedVideos: <JmVideoItem>[],
            ),
          ),
          webViewBuilder: (_, __, onExtracted) {
            extract = onExtracted;
            return const Text('concurrent-web');
          },
          directPlayerBuilder: (_, source, onFailure) {
            failPlayback = onFailure;
            return Text('concurrent-native:$source');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    extract!(sourceA);
    extract!(sourceB);
    await tester.pump();
    expect(checks.keys, <String>[sourceA]);

    checks[sourceA]!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('concurrent-native:$sourceA'), findsOneWidget);
    expect(checks.containsKey(sourceB), isFalse);

    failPlayback!();
    await tester.pump();
    expect(checks.containsKey(sourceB), isTrue);
    checks[sourceB]!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('concurrent-native:$sourceB'), findsOneWidget);
  });
}
