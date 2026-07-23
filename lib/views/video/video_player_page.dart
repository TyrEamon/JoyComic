/// JM video detail and playback with native, WebView, and browser fallbacks.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../foundation/log.dart';
import '../../network/jm/jm_network.dart';
import '../../network/res.dart';
import '../../theme/app_safe_area.dart';
import '../../theme/app_spacing.dart';
import 'hls_quality.dart';

typedef JmVideoDetailLoader = Future<Res<JmVideoDetail>> Function(String id);
typedef DirectVideoPlayerBuilder =
    Widget Function(
      BuildContext context,
      String source,
      VoidCallback onFailure,
    );
typedef DirectHlsWebViewBuilder =
    Widget Function(
      BuildContext context,
      String source,
      VoidCallback onFailure,
    );
typedef VideoWebViewBuilder =
    Widget Function(
      BuildContext context,
      String url,
      ValueChanged<String> onExtracted,
    );
typedef ExternalVideoLauncher = Future<bool> Function(Uri uri);
typedef RemoteVideoUriChecker = Future<bool> Function(Uri uri);
typedef HlsManifestLoader = Future<String> Function(Uri uri);
typedef VideoOrientationsSetter =
    Future<void> Function(List<DeviceOrientation> orientations);
typedef VideoUiModeSetter = Future<void> Function(SystemUiMode mode);

Future<void> applyVideoFullscreenState({
  required bool fullscreen,
  required List<DeviceOrientation> restoreOrientations,
  VideoOrientationsSetter? setOrientations,
  VideoUiModeSetter? setUiMode,
}) async {
  final orientations = setOrientations ?? SystemChrome.setPreferredOrientations;
  final uiMode =
      setUiMode ?? (mode) => SystemChrome.setEnabledSystemUIMode(mode);
  if (fullscreen) {
    await orientations(const <DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await uiMode(SystemUiMode.immersiveSticky);
    return;
  }
  await orientations(restoreOrientations);
  await uiMode(SystemUiMode.edgeToEdge);
}

class NavigationApprovalTracker {
  int _generation = 0;
  final Map<String, int> _approved = <String, int>{};
  final Map<String, int> _loaded = <String, int>{};

  int get generation => _generation;

  int beginRequest() => ++_generation;

  void approve(String url, int generation) {
    if (generation == _generation) _approved[url] = generation;
  }

  bool consume(String url) {
    final approvedGeneration = _approved.remove(url);
    if (approvedGeneration == null || approvedGeneration != _generation) {
      return false;
    }
    _loaded[url] = approvedGeneration;
    return true;
  }

  void revoke(String url, int generation) {
    if (_approved[url] == generation) _approved.remove(url);
  }

  bool isLoaded(String url) => _loaded[url] == _generation;
}

bool isMainFrameNavigation(NavigationRequest request) => request.isMainFrame;

Future<bool> shouldAllowVideoSubframeNavigation(
  NavigationRequest request, {
  RemoteVideoUriChecker? remoteUriChecker,
}) async {
  if (request.isMainFrame) return false;
  if (request.url == 'about:blank') return true;
  final uri = safeRemoteHttpUri(request.url);
  if (uri == null) return false;
  return (remoteUriChecker ?? isResolvedPublicHttpUri)(uri);
}

const videoWebViewPlaybackPolicy = (
  allowsInlineMediaPlayback: true,
  requiresUserAction: false,
);

PlatformWebViewControllerCreationParams videoWebViewCreationParams({
  required bool useWebKit,
}) {
  if (useWebKit) {
    return WebKitWebViewControllerCreationParams(
      allowsInlineMediaPlayback:
          videoWebViewPlaybackPolicy.allowsInlineMediaPlayback,
      mediaTypesRequiringUserAction:
          videoWebViewPlaybackPolicy.requiresUserAction
          ? const <PlaybackMediaTypes>{
              PlaybackMediaTypes.audio,
              PlaybackMediaTypes.video,
            }
          : const <PlaybackMediaTypes>{},
    );
  }
  return const PlatformWebViewControllerCreationParams();
}

String resolveJmVideoPageUrl(
  String videoId, {
  String fullUrl = '',
  String backlink = '',
  String initialBacklink = '',
}) {
  final fallback = Uri.parse('https://18comic.vip/video/$videoId');
  final publicBase = Uri.parse('https://18comic.vip/');
  for (final raw in <String>[fullUrl, backlink, initialBacklink]) {
    final uri = validatedHttpUri(raw, base: publicBase);
    if (uri != null && isTrustedJmPageUri(uri, initial: uri)) {
      return uri.toString();
    }
  }
  return fallback.toString();
}

String _describeRemoteUri(String raw, {Uri? base}) {
  final uri = validatedHttpUri(raw, base: base);
  if (uri == null) return 'invalid-uri';
  return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
}

bool isCurrentGenerationResource<T extends Object>(
  T candidate,
  T current,
  int generation,
  int currentGeneration,
) => identical(candidate, current) && generation == currentGeneration;

Key videoWebViewKey(String url) => ValueKey<String>(url);

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.videoId,
    this.initialTitle = '',
    this.initialBacklink = '',
    this.loader,
    this.directPlayerBuilder,
    this.directHlsWebViewBuilder,
    this.webViewBuilder,
    this.externalLauncher,
    this.remoteUriChecker,
    this.hlsManifestLoader,
    this.restoreOrientations = const <DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ],
  });

  final String videoId;
  final String initialTitle;
  final String initialBacklink;
  final JmVideoDetailLoader? loader;
  final DirectVideoPlayerBuilder? directPlayerBuilder;
  final DirectHlsWebViewBuilder? directHlsWebViewBuilder;
  final VideoWebViewBuilder? webViewBuilder;
  final ExternalVideoLauncher? externalLauncher;
  final RemoteVideoUriChecker? remoteUriChecker;
  final HlsManifestLoader? hlsManifestLoader;
  final List<DeviceOrientation> restoreOrientations;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  final Set<String> _failedSources = <String>{};
  int _loadGeneration = 0;
  JmVideoDetail? _detail;
  String? _error;
  String? _extractedSource;
  String? _directFallbackSource;
  bool _loading = true;
  bool _useWebView = false;
  bool _webFailed = false;
  final Set<String> _acceptedExtractionSources = <String>{};
  int? _pendingExtractionSession;
  String? _queuedExtractionSource;
  String? _activeExtractedSource;
  List<HlsVariant> _qualityVariants = const <HlsVariant>[];
  Uri? _selectedQualityUri;
  Uri? _qualityMasterUri;
  bool _isFullscreen = false;
  Future<void> _fullscreenTransition = Future<void>.value();
  int _fullscreenGeneration = 0;

  JmVideoDetailLoader get _loader =>
      widget.loader ?? JmNetwork().getVideoDetail;

  String get _fullUrl {
    final detail = _detail;
    return resolveJmVideoPageUrl(
      widget.videoId,
      fullUrl: detail?.fullUrl ?? '',
      backlink: detail?.backlink ?? '',
      initialBacklink: widget.initialBacklink,
    );
  }

  String get _directSource {
    final raw = _extractedSource ?? _detail?.videoSrc ?? '';
    final original = safeRemoteHttpUri(raw, base: Uri.parse(_fullUrl));
    return (_selectedQualityUri ?? _qualityMasterUri ?? original)?.toString() ??
        '';
  }

  HlsManifestLoader get _hlsLoader =>
      widget.hlsManifestLoader ?? _loadHlsManifest;

  Future<String> _loadHlsManifest(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
      request.headers.set(HttpHeaders.refererHeader, _fullUrl);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('manifest status ${response.statusCode}');
      }
      return readHlsManifest(response.timeout(const Duration(seconds: 8)));
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _discoverHlsQualities(Uri source, int generation) async {
    if (!isHlsManifestCandidate(source)) return;
    try {
      final manifest = await _hlsLoader(source);
      final parsed = parseHlsVariants(manifest, source);
      final variants = <HlsVariant>[];
      bool isStale() =>
          !mounted ||
          generation != _loadGeneration ||
          source.toString() != _directSource;
      if (isStale()) return;
      for (final variant in parsed.take(12)) {
        if (isStale()) return;
        if (await _isRemoteUriAllowed(variant.uri)) variants.add(variant);
        if (isStale()) return;
      }
      final selectable = variants.length >= 2 ? variants : const <HlsVariant>[];
      setState(() {
        _qualityMasterUri = source;
        _qualityVariants = selectable;
        _selectedQualityUri = null;
      });
      Log.i(
        'Video HLS quality discovery',
        'source=${_describeRemoteUri(source.toString())} variants=${selectable.length}',
      );
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      Log.w(
        'Video HLS quality discovery failed',
        error: '${_describeRemoteUri(source.toString())} ${error.runtimeType}',
      );
    }
  }

  void _selectQuality(String value) {
    HlsVariant? selected;
    if (value.isNotEmpty) {
      for (final variant in _qualityVariants) {
        if (variant.uri.toString() == value) {
          selected = variant;
          break;
        }
      }
      if (selected == null) return;
    }
    if (selected?.uri == _selectedQualityUri ||
        selected == null && _selectedQualityUri == null) {
      return;
    }
    final nextSource = selected?.uri ?? _qualityMasterUri;
    setState(() {
      _selectedQualityUri = selected?.uri;
      if (_directFallbackSource != null) {
        _directFallbackSource = nextSource?.toString();
      }
    });
    Log.i('Video HLS quality selected', 'quality=${selected?.label ?? 'auto'}');
  }

  Future<bool> _isRemoteUriAllowed(Uri uri) async {
    final checker = widget.remoteUriChecker;
    if (checker != null) return checker(uri);
    return isJmPlaybackRemoteUriAllowed(uri);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final loader = _loader;
    final videoId = widget.videoId;
    Log.i('Video detail load', 'id=$videoId');
    try {
      final result = await loader(videoId);
      var canPlayDirectly = false;
      var sourceDescription = 'n/a';
      Uri? directSource;
      if (!result.error) {
        final pageUrl = resolveJmVideoPageUrl(
          videoId,
          fullUrl: result.data.fullUrl,
          backlink: result.data.backlink,
          initialBacklink: widget.initialBacklink,
        );
        final source = safeRemoteHttpUri(
          result.data.videoSrc,
          base: Uri.parse(pageUrl),
        );
        sourceDescription = _describeRemoteUri(
          result.data.videoSrc,
          base: Uri.parse(pageUrl),
        );
        if (result.data.videoSrc.isNotEmpty && source != null) {
          canPlayDirectly = await _isRemoteUriAllowed(source);
          if (canPlayDirectly) directSource = source;
        }
      }
      if (!mounted || generation != _loadGeneration) return;
      Log.i(
        'Video detail result',
        'id=$videoId error=${result.error} source=$sourceDescription '
            'direct=$canPlayDirectly',
      );
      setState(() {
        _loading = false;
        if (result.error) {
          _error = result.errorMessageWithoutNull;
          _useWebView = true;
        } else {
          _error = null;
          _detail = result.data;
          _useWebView = !canPlayDirectly;
        }
      });
      if (directSource != null) {
        unawaited(_discoverHlsQualities(directSource, generation));
      }
    } catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return;
      Log.e('Video detail exception', error: error, stackTrace: stackTrace);
      setState(() {
        _loading = false;
        _error = '视频详情加载失败';
        _useWebView = true;
      });
    }
  }

  @override
  void didUpdateWidget(covariant VideoPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId == widget.videoId) return;
    if (_isFullscreen) {
      unawaited(_queueFullscreenState(false, rollbackOnError: false));
    }
    _failedSources.clear();
    _detail = null;
    _error = null;
    _extractedSource = null;
    _directFallbackSource = null;
    _acceptedExtractionSources.clear();
    _pendingExtractionSession = null;
    _queuedExtractionSource = null;
    _activeExtractedSource = null;
    _qualityVariants = const <HlsVariant>[];
    _selectedQualityUri = null;
    _qualityMasterUri = null;
    _isFullscreen = false;
    _useWebView = false;
    _webFailed = false;
    _loading = true;
    _load();
  }

  @override
  void dispose() {
    unawaited(_queueFullscreenState(false, rollbackOnError: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _detail?.title.isNotEmpty == true
        ? _detail!.title
        : widget.initialTitle;
    final semantic = context.semanticColors;
    return Scaffold(
      backgroundColor: semantic.readerCanvas,
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: Text(title.isEmpty ? '影视播放' : title),
              backgroundColor: semantic.readerCanvas,
              foregroundColor: semantic.readerControlForeground,
              actions: <Widget>[
                IconButton(
                  tooltip: '浏览器打开',
                  onPressed: _openExternal,
                  icon: const Icon(Icons.open_in_browser),
                ),
              ],
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                Expanded(child: _buildPlayer()),
                if (!_isFullscreen && _qualityVariants.length >= 2)
                  _buildQualitySelector(),
                if (!_isFullscreen && _error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: semantic.readerControlForeground),
                    ),
                  ),
                if (!_isFullscreen)
                  TextButton.icon(
                    onPressed: _openExternal,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('浏览器打开'),
                  ),
                if (!_isFullscreen)
                  SizedBox(
                    height: bottomContentInset(context, spacing: AppSpacing.xs),
                  ),
              ],
            ),
    );
  }

  Widget _buildQualitySelector() {
    final selectedLabel = _selectedQualityUri == null
        ? '自动'
        : _qualityVariants
              .firstWhere(
                (variant) => variant.uri == _selectedQualityUri,
                orElse: () => _qualityVariants.first,
              )
              .label;
    return Align(
      alignment: Alignment.centerRight,
      child: PopupMenuButton<String>(
        tooltip: '选择清晰度',
        onSelected: _selectQuality,
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(value: '', child: Text('自动')),
          ..._qualityVariants.map(
            (variant) => PopupMenuItem<String>(
              value: variant.uri.toString(),
              child: Text(variant.label),
            ),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('清晰度：$selectedLabel'),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleFullscreen() async {
    final next = !_isFullscreen;
    if (!mounted) return;
    setState(() => _isFullscreen = next);
    await _queueFullscreenState(next);
  }

  Future<void> _queueFullscreenState(
    bool fullscreen, {
    bool rollbackOnError = true,
  }) {
    final generation = ++_fullscreenGeneration;
    final restoreOrientations = widget.restoreOrientations;
    _fullscreenTransition = _fullscreenTransition.catchError((_) {}).then((
      _,
    ) async {
      if (generation != _fullscreenGeneration) return;
      try {
        await applyVideoFullscreenState(
          fullscreen: fullscreen,
          restoreOrientations: restoreOrientations,
        );
      } catch (error, stackTrace) {
        Log.e(
          'Video fullscreen transition failed',
          error: error.runtimeType,
          stackTrace: stackTrace,
        );
        if (rollbackOnError &&
            mounted &&
            generation == _fullscreenGeneration &&
            _isFullscreen == fullscreen) {
          setState(() => _isFullscreen = !fullscreen);
        }
      }
    });
    return _fullscreenTransition;
  }

  Widget _buildPlayer() {
    if (!_useWebView && _directSource.isNotEmpty) {
      final source = _directSource;
      final session = _loadGeneration;
      void onFailure() => _onNativeFailureForSource(source, session);
      final builder = widget.directPlayerBuilder;
      if (builder != null) {
        return builder(context, source, onFailure);
      }
      return NativeVideoPlayer(
        source: source,
        onFailure: onFailure,
        isFullscreen: _isFullscreen,
        onToggleFullscreen: _toggleFullscreen,
      );
    }
    final directFallback = _directFallbackSource;
    if (_useWebView && directFallback != null && directFallback.isNotEmpty) {
      final builder = widget.directHlsWebViewBuilder;
      if (builder != null) {
        return builder(context, directFallback, _onDirectWebFailure);
      }
      // Existing widget-test/custom integrations only provide the extracting
      // builder. Production uses the dedicated local direct-HLS document.
      if (widget.webViewBuilder == null) {
        return DirectHlsVideoWebView(
          key: videoWebViewKey('direct:${directFallback.hashCode}'),
          source: directFallback,
          onFailure: _onDirectWebFailure,
        );
      }
    }
    if (_webFailed) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text('网页播放失败，请使用浏览器打开', style: TextStyle(color: Colors.white)),
        ),
      );
    }
    final session = _loadGeneration;
    void onExtracted(String source) => _onExtractedForSession(source, session);
    final builder = widget.webViewBuilder;
    if (builder != null) return builder(context, _fullUrl, onExtracted);
    return ExtractingVideoWebView(
      key: videoWebViewKey(_fullUrl),
      url: _fullUrl,
      onExtracted: onExtracted,
      onFailure: _onWebFailure,
    );
  }

  void _onNativeFailureForSource(String failed, int session) {
    if (!mounted || session != _loadGeneration || failed != _directSource) {
      return;
    }
    if (failed.isNotEmpty) _failedSources.add(failed);
    Log.w('Video native fallback', error: _describeRemoteUri(failed));
    if (_activeExtractedSource == failed) _activeExtractedSource = null;
    setState(() {
      _directFallbackSource = failed.isEmpty ? null : failed;
      _useWebView = true;
    });
    _processQueuedExtraction(session);
  }

  void _processQueuedExtraction(int session) {
    final queued = _queuedExtractionSource;
    _queuedExtractionSource = null;
    if (queued != null && mounted && session == _loadGeneration) {
      scheduleMicrotask(() => _onExtractedForSession(queued, session));
    }
  }

  Future<void> _onExtractedForSession(String source, int session) async {
    final valid = safeRemoteHttpUri(source, base: Uri.parse(_fullUrl));
    if (valid == null ||
        _failedSources.contains(valid.toString()) ||
        _acceptedExtractionSources.contains(valid.toString()) ||
        !mounted ||
        session != _loadGeneration) {
      return;
    }
    if (_pendingExtractionSession == session ||
        _activeExtractedSource != null) {
      _queuedExtractionSource = valid.toString();
      return;
    }

    _pendingExtractionSession = session;
    try {
      if (!await _isRemoteUriAllowed(valid) ||
          !mounted ||
          session != _loadGeneration ||
          _failedSources.contains(valid.toString()) ||
          _acceptedExtractionSources.contains(valid.toString()) ||
          _activeExtractedSource != null) {
        return;
      }
      Log.i('Video source accepted', _describeRemoteUri(valid.toString()));
      _acceptedExtractionSources.add(valid.toString());
      _activeExtractedSource = valid.toString();
      setState(() {
        _extractedSource = valid.toString();
        _directFallbackSource = null;
        _qualityVariants = const <HlsVariant>[];
        _selectedQualityUri = null;
        _qualityMasterUri = null;
        _useWebView = false;
        _webFailed = false;
      });
      unawaited(_discoverHlsQualities(valid, session));
    } finally {
      if (_pendingExtractionSession == session) {
        _pendingExtractionSession = null;
      }
      if (_activeExtractedSource == null) _processQueuedExtraction(session);
    }
  }

  void _onWebFailure() {
    Log.w('Video WebView fallback failed', error: 'id=${widget.videoId}');
    if (mounted) setState(() => _webFailed = true);
  }

  void _onDirectWebFailure() {
    final source = _directFallbackSource;
    Log.w(
      'Video direct HLS fallback failed',
      error: source == null ? 'missing-source' : _describeRemoteUri(source),
    );
    if (mounted) {
      setState(() {
        _directFallbackSource = null;
        _webFailed = true;
      });
    }
  }

  Future<void> _openExternal() async {
    final uri = safeRemoteHttpUri(_fullUrl);
    if (uri == null || !await _isRemoteUriAllowed(uri)) {
      _showLaunchError();
      return;
    }
    try {
      final launcher =
          widget.externalLauncher ??
          (target) => launchUrl(target, mode: LaunchMode.externalApplication);
      if (!await launcher(uri)) _showLaunchError();
    } catch (_) {
      _showLaunchError();
    }
  }

  void _showLaunchError() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('无法打开外部浏览器')));
  }
}

VideoViewType nativeVideoViewType(TargetPlatform platform) {
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return VideoViewType.platformView;
  }
  return VideoViewType.textureView;
}

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

String describeNativeVideoState(
  VideoPlayerValue value, {
  required VideoViewType viewType,
  required String source,
}) {
  final size = value.size;
  return 'source=${_describeRemoteUri(source)} '
      'view=${viewType.name} size=${size.width}x${size.height} '
      'aspect=${value.aspectRatio} '
      'duration=${value.duration.inMilliseconds}ms '
      'playing=${value.isPlaying} buffering=${value.isBuffering}';
}

bool isNativeVideoRenderable(VideoPlayerValue value) {
  final size = value.size;
  return value.isInitialized &&
      !value.hasError &&
      size.width > 0 &&
      size.height > 0 &&
      value.aspectRatio > 0;
}

Duration clampVideoPosition(Duration position, Duration duration) {
  if (position <= Duration.zero) return Duration.zero;
  if (duration <= Duration.zero || position <= duration) return position;
  return duration;
}

class NativeVideoPlayer extends StatefulWidget {
  const NativeVideoPlayer({
    super.key,
    required this.source,
    required this.onFailure,
    this.isFullscreen = false,
    this.onToggleFullscreen,
  });

  final String source;
  final VoidCallback onFailure;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  State<NativeVideoPlayer> createState() => _NativeVideoPlayerState();
}

class _NativeVideoPlayerState extends State<NativeVideoPlayer> {
  late VideoPlayerController _controller;
  int _controllerGeneration = 0;
  bool _ready = false;
  bool _reportedError = false;

  @override
  void initState() {
    super.initState();
    _controller = createNativeVideoController(widget.source)
      ..addListener(_onControllerChanged);
    _startInitialization();
  }

  void _startInitialization({
    Duration? resumePosition,
    bool shouldPlay = true,
  }) {
    final controller = _controller;
    final generation = ++_controllerGeneration;
    _initialize(
      controller,
      generation,
      resumePosition: resumePosition,
      shouldPlay: shouldPlay,
    );
  }

  Future<void> _initialize(
    VideoPlayerController controller,
    int generation, {
    Duration? resumePosition,
    required bool shouldPlay,
  }) async {
    try {
      await controller.initialize();
      if (!mounted ||
          !isCurrentGenerationResource(
            controller,
            _controller,
            generation,
            _controllerGeneration,
          )) {
        return;
      }
      Log.i(
        'Video native initialized',
        describeNativeVideoState(
          controller.value,
          viewType: controller.viewType,
          source: widget.source,
        ),
      );
      if (!isNativeVideoRenderable(controller.value)) {
        Log.w(
          'Video native media is not renderable',
          error: describeNativeVideoState(
            controller.value,
            viewType: controller.viewType,
            source: widget.source,
          ),
        );
        _reportFailure();
        return;
      }
      if (resumePosition != null && resumePosition > Duration.zero) {
        await controller.seekTo(
          clampVideoPosition(resumePosition, controller.value.duration),
        );
      }
      if (shouldPlay) await controller.play();
      Log.i('Video native ready', _describeRemoteUri(widget.source));
      if (mounted &&
          isCurrentGenerationResource(
            controller,
            _controller,
            generation,
            _controllerGeneration,
          )) {
        setState(() => _ready = true);
      }
    } catch (error, stackTrace) {
      if (mounted &&
          isCurrentGenerationResource(
            controller,
            _controller,
            generation,
            _controllerGeneration,
          )) {
        Log.e(
          'Video native initialization failed',
          error: '${_describeRemoteUri(widget.source)} $error',
          stackTrace: stackTrace,
        );
        _reportFailure();
      }
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller.value.hasError) {
      Log.e(
        'Video native controller error',
        error:
            '${_describeRemoteUri(widget.source)} ${_controller.value.errorDescription}',
      );
      _reportFailure();
    }
    if (_ready) setState(() {});
  }

  void _reportFailure() {
    if (_reportedError || !mounted) return;
    _reportedError = true;
    widget.onFailure();
  }

  @override
  void didUpdateWidget(covariant NativeVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source == widget.source) return;
    final resumePosition = _controller.value.position;
    final shouldPlay = _controller.value.isPlaying;
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    _ready = false;
    _reportedError = false;
    _controller = createNativeVideoController(widget.source)
      ..addListener(_onControllerChanged);
    _startInitialization(
      resumePosition: resumePosition,
      shouldPlay: shouldPlay,
    );
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    final foreground = context.semanticColors.readerControlForeground;
    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
        ),
        Row(
          children: <Widget>[
            IconButton(
              color: foreground,
              onPressed: () {
                _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play();
              },
              icon: Icon(
                _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
            Expanded(
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: Theme.of(context).colorScheme.primary,
                  bufferedColor: Theme.of(context).colorScheme.secondary,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            IconButton(
              color: foreground,
              tooltip: widget.isFullscreen ? '退出全屏' : '全屏',
              onPressed: widget.onToggleFullscreen,
              icon: Icon(
                widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String buildDirectHlsVideoHtml(String source) {
  final encodedSource = base64Encode(utf8.encode(source));
  return '''<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
  <style>
    html,body { margin:0; width:100%; height:100%; background:#000; overflow:hidden; }
    video { width:100%; height:100%; object-fit:contain; background:#000; }
  </style>
</head>
<body>
  <video id="player" controls autoplay playsinline preload="metadata"></video>
  <script>
    (() => {
      const player = document.getElementById('player');
      const send = (event, detail = '') => {
        try {
          VideoBridge.postMessage(JSON.stringify({
            type: 'direct_hls', event, detail: String(detail).slice(0, 64)
          }));
        } catch (_) {}
      };
      ['loadedmetadata','canplay','playing','waiting','stalled'].forEach(event => {
        player.addEventListener(event, () => send(event, player.readyState));
      });
      player.addEventListener('error', () => send('error', player.error ? player.error.code : 0));
      player.src = atob('$encodedSource');
      player.load();
      const promise = player.play();
      if (promise && promise.catch) promise.catch(() => send('autoplay-blocked'));
    })();
  </script>
</body>
</html>''';
}

bool isDirectHlsReadyEvent(String event) =>
    const <String>{'loadedmetadata', 'canplay', 'playing'}.contains(event);

class VideoLoadingSurface extends StatelessWidget {
  const VideoLoadingSurface({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class DirectHlsVideoWebView extends StatefulWidget {
  const DirectHlsVideoWebView({
    super.key,
    required this.source,
    required this.onFailure,
  });

  final String source;
  final VoidCallback onFailure;

  @override
  State<DirectHlsVideoWebView> createState() => _DirectHlsVideoWebViewState();
}

class _DirectHlsVideoWebViewState extends State<DirectHlsVideoWebView> {
  WebViewController? _controller;
  bool _failed = false;
  bool _ready = false;
  Timer? _startupTimeout;

  @override
  void initState() {
    super.initState();
    _startupTimeout = Timer(
      const Duration(seconds: 15),
      () => _fail('startup timeout'),
    );
    final source = safeRemoteHttpUri(widget.source);
    if (source == null) {
      scheduleMicrotask(() => _fail('invalid source'));
      return;
    }
    final controller = WebViewController.fromPlatformCreationParams(
      videoWebViewCreationParams(
        useWebKit: WebViewPlatform.instance is WebKitWebViewPlatform,
      ),
    );
    if (controller.platform is AndroidWebViewController) {
      unawaited(
        (controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false),
      );
    }
    _controller = controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'VideoBridge',
        onMessageReceived: (message) {
          if (_failed) return;
          try {
            final decoded = jsonDecode(message.message);
            if (decoded is! Map || decoded['type'] != 'direct_hls') return;
            final event = decoded['event']?.toString() ?? 'unknown';
            final detail = decoded['detail']?.toString() ?? '';
            if (!const <String>{
              'loadedmetadata',
              'canplay',
              'playing',
              'waiting',
              'stalled',
              'error',
              'autoplay-blocked',
            }.contains(event)) {
              return;
            }
            Log.i(
              'Video direct HLS event',
              'event=$event detail=${detail.substring(0, detail.length.clamp(0, 64))}',
            );
            if (isDirectHlsReadyEvent(event)) {
              _startupTimeout?.cancel();
              if (mounted) setState(() => _ready = true);
            }
            if (event == 'error') _fail('media error $detail');
          } catch (_) {
            _fail('invalid bridge message');
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) => request.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onWebResourceError: (error) {
            if (shouldFailWebViewForResourceError(error)) {
              _fail('resource ${error.errorCode}');
            }
          },
        ),
      );
    Log.i('Video direct HLS load', _describeRemoteUri(source.toString()));
    unawaited(_loadHtml(controller, source));
  }

  Future<void> _loadHtml(WebViewController controller, Uri source) async {
    try {
      await controller.loadHtmlString(
        buildDirectHlsVideoHtml(source.toString()),
        baseUrl: 'https://18comic.vip/',
      );
    } catch (error, stackTrace) {
      Log.e(
        'Video direct HLS document failed',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
      _fail('document load failed');
    }
  }

  void _fail(String reason) {
    if (_failed || !mounted) return;
    _failed = true;
    _startupTimeout?.cancel();
    Log.w('Video direct HLS failed', error: reason);
    widget.onFailure();
  }

  @override
  void dispose() {
    _startupTimeout?.cancel();
    Log.i('Video direct HLS dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return controller == null
        ? const VideoLoadingSurface(message: '正在初始化视频')
        : Stack(
            fit: StackFit.expand,
            children: <Widget>[
              WebViewWidget(controller: controller),
              if (!_ready)
                const IgnorePointer(
                  child: VideoLoadingSurface(message: '正在加载视频'),
                ),
            ],
          );
  }
}

const videoExtractionJavaScript = r'''
(() => {
  if (window.__joyComicVideoExtractorInstalled) return;
  window.__joyComicVideoExtractorInstalled = true;
  const bridgeToken = __JOY_BRIDGE_NONCE__;
  const seen = new Set();
  const send = src => {
    if (!src || seen.has(src)) return;
    seen.add(src);
    try {
      VideoBridge.postMessage(
        JSON.stringify({type:'video_src',src,token:bridgeToken})
      );
    } catch (_) {}
  };
  const read = value => {
    if (!value || typeof value !== 'object') return;
    [
      value.video_src,
      value.video && value.video.video_src,
      value.data && value.data.video_src,
      value.data && value.data.video && value.data.video.video_src,
    ].forEach(send);
  };
  const inspect = () => {
    const video = document.querySelector('video');
    send(video && (video.currentSrc || video.src));
    document.querySelectorAll('source').forEach(source => send(source.src));
  };
  const originalFetch = window.fetch;
  if (typeof originalFetch === 'function') {
    window.fetch = async (...args) => {
      const response = await originalFetch(...args);
      response.clone().text().then(text => {
        try { read(JSON.parse(text)); } catch (_) {}
      });
      return response;
    };
  }
  const observer = new MutationObserver(inspect);
  observer.observe(document.documentElement || document, {
    childList: true,
    subtree: true,
    attributes: true,
    attributeFilter: ['src'],
  });
  const interval = window.setInterval(inspect, 500);
  window.setTimeout(() => {
    window.clearInterval(interval);
    observer.disconnect();
  }, 9000);
  inspect();
})();
''';

class ExtractingVideoWebView extends StatefulWidget {
  const ExtractingVideoWebView({
    super.key,
    required this.url,
    required this.onExtracted,
    required this.onFailure,
  });

  final String url;
  final ValueChanged<String> onExtracted;
  final VoidCallback onFailure;

  @override
  State<ExtractingVideoWebView> createState() => _ExtractingVideoWebViewState();
}

class _ExtractingVideoWebViewState extends State<ExtractingVideoWebView> {
  String _bridgeNonce = createVideoBridgeNonce();
  Uri? _currentPage;
  final NavigationApprovalTracker _navigationApprovals =
      NavigationApprovalTracker();
  final Set<String> _pendingHosts = <String>{};
  int _navigationGeneration = 0;
  WebViewController? _controller;
  Timer? _timeout;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    final initial = validatedHttpUri(widget.url);
    if (initial == null || !isTrustedJmPageUri(initial, initial: initial)) {
      scheduleMicrotask(_fail);
      return;
    }
    _currentPage = initial;
    final controller = WebViewController.fromPlatformCreationParams(
      videoWebViewCreationParams(
        useWebKit: WebViewPlatform.instance is WebKitWebViewPlatform,
      ),
    );
    if (controller.platform is AndroidWebViewController) {
      unawaited(
        (controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false),
      );
    }
    _controller = controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'VideoBridge',
        onMessageReceived: (message) {
          if (_completed) return;
          final currentPage = _currentPage;
          if (currentPage == null) return;
          final source = parseExtractedVideoMessage(
            message.message,
            pageUrl: currentPage.toString(),
            expectedNonce: _bridgeNonce,
          );
          if (source == null) {
            Log.w('Video WebView extraction rejected');
            return;
          }
          Log.i('Video WebView extracted', _describeRemoteUri(source));
          // Keep the timeout alive until the parent accepts this source. If
          // it is already known-bad, the parent can reject it and extraction
          // still gets a chance to find another source or time out.
          widget.onExtracted(source);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            if (!isMainFrameNavigation(request)) {
              final allowed = await shouldAllowVideoSubframeNavigation(request);
              if (!mounted || _completed) return NavigationDecision.prevent;
              if (!allowed) {
                Log.w(
                  'Video WebView subframe blocked',
                  error: _describeRemoteUri(request.url),
                );
              }
              return allowed
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            }
            final uri = validatedHttpUri(request.url);
            if (uri == null || !isTrustedJmPageUri(uri, initial: initial)) {
              Log.w(
                'Video WebView navigation blocked',
                error: _describeRemoteUri(request.url),
              );
              return NavigationDecision.prevent;
            }
            final requestUrl = uri.toString();
            if (_navigationApprovals.consume(requestUrl)) {
              return NavigationDecision.navigate;
            }
            _verifyAndLoad(uri, initial);
            return NavigationDecision.prevent;
          },
          onPageStarted: (url) {
            Log.i('Video WebView page started', _describeRemoteUri(url));
            if (!_updateCurrentPage(url, initial, newNavigation: true)) return;
            _startTimeout();
            _installExtractionHooks();
          },
          onPageFinished: (url) {
            Log.i('Video WebView page finished', _describeRemoteUri(url));
            if (!_updateCurrentPage(url, initial)) return;
            _installExtractionHooks();
          },
          onWebResourceError: (error) {
            if (shouldFailWebViewForResourceError(error)) {
              _fail('resource ${error.errorCode}: ${error.description}');
            }
          },
        ),
      );
    Log.i('Video WebView load', _describeRemoteUri(initial.toString()));
    _loadInitialPage(initial);
  }

  Future<void> _loadInitialPage(Uri initial) async {
    final requestGeneration = _navigationApprovals.beginRequest();
    if (!await isJmPlaybackRemoteUriAllowed(initial) ||
        !mounted ||
        requestGeneration != _navigationApprovals.generation) {
      _fail('initial page DNS or lifecycle check failed');
      return;
    }
    final requestUrl = initial.toString();
    _navigationApprovals.approve(requestUrl, requestGeneration);
    _startTimeout();
    try {
      await _controller?.loadRequest(initial);
    } catch (error, stackTrace) {
      _navigationApprovals.revoke(requestUrl, requestGeneration);
      Log.e(
        'Video WebView initial request failed',
        error: error,
        stackTrace: stackTrace,
      );
      _fail('initial request exception');
    }
  }

  Future<void> _verifyAndLoad(Uri uri, Uri initial) async {
    final host = uri.host.toLowerCase();
    final requestGeneration = _navigationApprovals.beginRequest();
    if (!_pendingHosts.add('$host#$requestGeneration')) return;
    try {
      if (!await isJmPlaybackRemoteUriAllowed(uri) ||
          !mounted ||
          _completed ||
          requestGeneration != _navigationApprovals.generation ||
          !isTrustedJmPageUri(uri, initial: initial)) {
        return;
      }
      final requestUrl = uri.toString();
      _navigationApprovals.approve(requestUrl, requestGeneration);
      try {
        await _controller?.loadRequest(uri);
      } catch (error, stackTrace) {
        _navigationApprovals.revoke(requestUrl, requestGeneration);
        Log.e(
          'Video WebView redirect failed',
          error: error,
          stackTrace: stackTrace,
        );
        _fail('redirect request exception');
      }
    } finally {
      _pendingHosts.remove('$host#$requestGeneration');
    }
  }

  void _startTimeout() {
    _timeout?.cancel();
    _timeout = Timer(
      const Duration(seconds: 15),
      () => _fail('extraction timeout'),
    );
  }

  bool _updateCurrentPage(
    String rawUrl,
    Uri initial, {
    bool newNavigation = false,
  }) {
    final page = validatedHttpUri(rawUrl);
    if (page == null ||
        !isTrustedJmPageUri(page, initial: initial) ||
        !_navigationApprovals.isLoaded(page.toString())) {
      _fail('unapproved page callback');
      return false;
    }
    _currentPage = page;
    if (newNavigation) {
      _navigationGeneration++;
      _bridgeNonce = createVideoBridgeNonce();
    }
    return true;
  }

  Future<void> _installExtractionHooks() async {
    final controller = _controller;
    if (controller == null || _completed) return;
    final generation = _navigationGeneration;
    final nonce = _bridgeNonce;
    try {
      await controller.runJavaScript(
        videoExtractionJavaScript.replaceFirst(
          '__JOY_BRIDGE_NONCE__',
          jsonEncode(nonce),
        ),
      );
      if (!mounted || generation != _navigationGeneration) return;
    } catch (error, stackTrace) {
      Log.w(
        'Video WebView script injection deferred',
        error: error,
        stackTrace: stackTrace,
      );
      // The page may not have a JavaScript context yet. The page-finished
      // callback retries, and the bounded timeout remains the final fallback.
    }
  }

  void _fail([String reason = 'unknown']) {
    if (_completed || !mounted) return;
    _completed = true;
    _timeout?.cancel();
    Log.w('Video WebView failed', error: reason);
    widget.onFailure();
  }

  @override
  void dispose() {
    _completed = true;
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const VideoLoadingSurface(message: '正在初始化播放页');
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        WebViewWidget(controller: controller),
        const IgnorePointer(child: VideoLoadingSurface(message: '正在获取视频地址')),
      ],
    );
  }
}

Uri? validatedHttpUri(String value, {Uri? base}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null) return null;
  final resolved = parsed.hasScheme ? parsed : base?.resolveUri(parsed);
  if (resolved == null ||
      (resolved.scheme != 'http' && resolved.scheme != 'https') ||
      resolved.host.isEmpty ||
      resolved.userInfo.isNotEmpty) {
    return null;
  }
  return resolved;
}

Uri? safeRemoteHttpUri(String value, {Uri? base}) {
  final uri = validatedHttpUri(value, base: base);
  return uri != null && isPublicRemoteHttpUri(uri) ? uri : null;
}

bool _isPublicIpv4(List<int> octets) {
  if (octets.length != 4 || octets.any((part) => part < 0 || part > 255)) {
    return false;
  }
  final first = octets[0];
  final second = octets[1];
  if (first == 0 ||
      first == 10 ||
      first == 127 ||
      (first == 100 && second >= 64 && second <= 127) ||
      (first == 169 && second == 254) ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 0) ||
      (first == 192 && second == 168) ||
      (first == 198 && (second == 18 || second == 19)) ||
      (first == 198 && second == 51) ||
      (first == 203 && second == 0) ||
      first >= 224) {
    return false;
  }
  return true;
}

bool _isPublicIpLiteral(String host) {
  if (host.contains('%')) return false;
  final numericIpv4Like =
      host.contains('.') &&
      host
          .split('.')
          .every((part) => RegExp(r'^(?:0x)?[0-9a-fA-F]+$').hasMatch(part));
  if (numericIpv4Like) return false;
  final address = InternetAddress.tryParse(host);
  if (address == null) {
    // Decimal and hexadecimal integer forms can be interpreted as IPv4 by
    // URL clients (for example, 2130706433 == 127.0.0.1).
    if (RegExp(r'^\d+$').hasMatch(host) || host.startsWith('0x')) {
      return false;
    }
    return true;
  }
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  final bytes = address.rawAddress;
  if (bytes.length == 4) return _isPublicIpv4(bytes);
  if (bytes.length != 16) return false;

  final mappedIpv4 =
      bytes.sublist(0, 10).every((byte) => byte == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;
  if (mappedIpv4) return _isPublicIpv4(bytes.sublist(12));

  final first = bytes[0];
  final isUnspecified = bytes.every((byte) => byte == 0);
  final isUniqueLocal = (first & 0xfe) == 0xfc;
  final isLinkLocal = first == 0xfe && (bytes[1] & 0xc0) == 0x80;
  final isMulticast = first == 0xff;
  final isDocumentation =
      first == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8;
  return !(isUnspecified ||
      isUniqueLocal ||
      isLinkLocal ||
      isMulticast ||
      isDocumentation);
}

bool isPublicRemoteHttpUri(Uri uri) {
  if ((uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return false;
  }
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal')) {
    return false;
  }
  return _isPublicIpLiteral(host);
}

bool isTrustedJmPlaybackHost(String rawHost) {
  final host = rawHost.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  final configuredHost = Uri.tryParse(JmNetwork().baseUrl)?.host;
  final imageHosts = <String>{
    for (final raw in jmBuiltInImgUrls)
      if (Uri.tryParse(raw)?.host case final imageHost?) imageHost,
  };
  final hosts = <String>{
    '18comic.vip',
    'iiooxx.rocks',
    ...jmBuiltInDomains,
    ...imageHosts,
    if (configuredHost != null && configuredHost.isNotEmpty)
      configuredHost.toLowerCase(),
  };
  return hosts.any((allowed) {
    final normalized = allowed.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    return host == normalized || host.endsWith('.$normalized');
  });
}

Future<bool> isJmPlaybackRemoteUriAllowed(
  Uri uri, {
  RemoteVideoUriChecker? dnsChecker,
}) async {
  if (!isPublicRemoteHttpUri(uri)) return false;
  // These hosts are returned by the authenticated JM API/page itself. Do not
  // make playback depend on a best-effort client DNS lookup: iOS networking
  // can temporarily report a lookup failure while AVPlayer/WKWebView can
  // resolve the same HTTPS host normally.
  if (isTrustedJmPlaybackHost(uri.host)) return true;
  return (dnsChecker ?? isResolvedPublicHttpUri)(uri);
}

Future<bool> isResolvedPublicHttpUri(Uri uri) async {
  if (!isPublicRemoteHttpUri(uri)) return false;
  if (InternetAddress.tryParse(uri.host) != null) return true;
  try {
    final addresses = await InternetAddress.lookup(
      uri.host,
    ).timeout(const Duration(seconds: 2));
    return addresses.isNotEmpty &&
        addresses.every((address) => _isPublicIpLiteral(address.address));
  } catch (_) {
    return false;
  }
}

bool isTrustedJmPageUri(Uri uri, {required Uri initial}) {
  if (!isPublicRemoteHttpUri(uri)) return false;
  final configuredHost = Uri.tryParse(JmNetwork().baseUrl)?.host;
  final hosts = <String>{
    '18comic.vip',
    ...jmBuiltInDomains,
    if (configuredHost != null && configuredHost.isNotEmpty)
      configuredHost.toLowerCase(),
  };
  bool matchesTrustedHost(String host) =>
      hosts.any((allowed) => host == allowed || host.endsWith('.$allowed'));
  if (!matchesTrustedHost(initial.host.toLowerCase())) return false;
  return matchesTrustedHost(uri.host.toLowerCase());
}

bool shouldFailWebViewForResourceError(WebResourceError error) =>
    error.isForMainFrame != false;

String createVideoBridgeNonce() {
  final random = Random.secure();
  return List<int>.generate(
    24,
    (_) => random.nextInt(256),
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}

String? parseExtractedVideoMessage(
  String message, {
  required String pageUrl,
  String? expectedNonce,
}) {
  try {
    final decoded = jsonDecode(message);
    if (decoded is! Map ||
        decoded['type'] != 'video_src' ||
        decoded['src'] is! String ||
        (expectedNonce != null && decoded['token'] != expectedNonce)) {
      return null;
    }
    return safeRemoteHttpUri(
      decoded['src'] as String,
      base: validatedHttpUri(pageUrl),
    )?.toString();
  } catch (_) {
    return null;
  }
}
