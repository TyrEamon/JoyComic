import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// 全局图片缓存管理器：阅读器与预加载共用，保证缓存命中。
///
/// stalePeriod 15 天、最多 5000 对象。
final cacheManager = DefaultCacheManager(
  stalePeriod: const Duration(days: 15),
  maxNrOfCacheObjects: 5000,
);

/// 当前 [RetryForImage] 订阅的图片状态快照，传给 [RetryForImageBuilder]。
class RetryImageStatus {
  const RetryImageStatus({
    required this.provider,
    required this.attempt,
    required this.maxAttempts,
    required this.isLoaded,
    required this.retry,
    this.chunk,
    this.error,
  });

  /// 当前正在加载的 [ImageProvider]。builder 渲染实际图片时直接用它即可。
  final ImageProvider provider;

  /// 当前尝试次数（0 = 首次加载，N = 第 N 次自动重试）。
  final int attempt;

  /// 允许的最大自动重试次数。
  final int maxAttempts;

  /// 是否已经有至少一次解码成功（出现过 [ImageInfo]）。
  final bool isLoaded;

  /// 最近一次下载进度事件，加载成功后会被清空。仅网络图会有值。
  final ImageChunkEvent? chunk;

  /// 最近一次错误；成功或新一轮重试开始后会被清空。
  final Object? error;

  /// 手动重试。调用后计数器归零，并重新拉取图片。
  final VoidCallback retry;

  /// 处于自动重试过程中（有错误但还有自动重试余量）。
  bool get isRetrying => error != null && attempt < maxAttempts;

  /// 自动重试已耗尽，等待用户手动点击重试。
  bool get isExhausted => error != null && attempt >= maxAttempts && !isLoaded;
}

typedef RetryForImageBuilder =
    Widget Function(BuildContext context, RetryImageStatus status);

/// 只负责重试逻辑的图片包装。
///
/// - 订阅 [imageProvider]，监听错误 / 进度 / 解码完成
/// - 解码成功后设 [RetryImageStatus.isLoaded]，builder 用 [Image] 上屏
/// - 不持有 [ImageInfo]（避免与 ImageCache 生命周期打架导致黑屏）
class RetryForImage extends StatefulWidget {
  const RetryForImage({
    super.key,
    required this.imageProvider,
    required this.builder,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 200),
    this.fadeDuration = Duration.zero,
    this.fadeCurve = Curves.easeOutQuad,
    this.onImageResolved,
  });

  final ImageProvider imageProvider;
  final RetryForImageBuilder builder;
  final int maxAttempts;
  final Duration retryDelay;
  final Duration fadeDuration;
  final Curve fadeCurve;
  final void Function(ImageInfo info)? onImageResolved;

  @override
  State<RetryForImage> createState() => _RetryForImageState();
}

class _RetryForImageState extends State<RetryForImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageStreamCompleterHandle? _completerHandle;

  int _attempt = 0;
  bool _isLoaded = false;
  bool _resolvedFired = false;
  ImageChunkEvent? _chunk;
  Object? _error;
  Timer? _retryTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listener == null) {
      _subscribe();
    }
  }

  @override
  void didUpdateWidget(covariant RetryForImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageProvider != oldWidget.imageProvider) {
      _resetForNewProvider();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _unsubscribe();
    _completerHandle?.dispose();
    _completerHandle = null;
    super.dispose();
  }

  void _subscribe() {
    final config = createLocalImageConfiguration(context);
    final stream = widget.imageProvider.resolve(config);
    final listener = ImageStreamListener(
      _handleImage,
      onChunk: _handleChunk,
      onError: _handleError,
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
    // Keep decoded frames resident while this widget is mounted (iOS thrash).
    _completerHandle?.dispose();
    _completerHandle = stream.completer?.keepAlive();
  }

  void _unsubscribe() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  void _resetForNewProvider() {
    _retryTimer?.cancel();
    _unsubscribe();
    _completerHandle?.dispose();
    _completerHandle = null;
    _attempt = 0;
    _isLoaded = false;
    _resolvedFired = false;
    _chunk = null;
    _error = null;
  }

  void _handleImage(ImageInfo info, bool synchronousCall) {
    if (!mounted) return;
    final firstResolve = !_resolvedFired;
    _resolvedFired = true;
    setState(() {
      _isLoaded = true;
      _error = null;
      _chunk = null;
    });
    if (firstResolve) {
      widget.onImageResolved?.call(info);
    }
  }

  void _handleChunk(ImageChunkEvent event) {
    if (!mounted) return;
    setState(() => _chunk = event);
  }

  void _handleError(Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    final shouldSchedule =
        _attempt < widget.maxAttempts && _retryTimer?.isActive != true;
    setState(() {
      _error = error;
      _chunk = null;
      if (shouldSchedule) _attempt++;
    });
    if (shouldSchedule) {
      _retryTimer = Timer(widget.retryDelay, _performRetry);
    }
  }

  Future<void> _performRetry() async {
    if (!mounted) return;
    _unsubscribe();
    setState(() {
      _error = null;
      _chunk = null;
    });
    if (!mounted) return;
    _subscribe();
  }

  Future<void> _manualRetry() async {
    _retryTimer?.cancel();
    _unsubscribe();
    setState(() {
      _attempt = 0;
      _isLoaded = false;
      _resolvedFired = false;
      _error = null;
      _chunk = null;
    });
    await widget.imageProvider.evict();
    if (!mounted) return;
    _subscribe();
  }

  _RetryPhase get _phase {
    if (_isLoaded) return _RetryPhase.loaded;
    if (_error != null && _attempt >= widget.maxAttempts) {
      return _RetryPhase.exhausted;
    }
    return _RetryPhase.loading;
  }

  @override
  Widget build(BuildContext context) {
    final status = RetryImageStatus(
      provider: widget.imageProvider,
      attempt: _attempt,
      maxAttempts: widget.maxAttempts,
      isLoaded: _isLoaded,
      chunk: _chunk,
      error: _error,
      retry: _manualRetry,
    );

    final child = KeyedSubtree(
      key: ValueKey(_phase),
      child: widget.builder(context, status),
    );

    if (widget.fadeDuration == Duration.zero) {
      return child;
    }

    return AnimatedSwitcher(
      duration: widget.fadeDuration,
      switchInCurve: widget.fadeCurve,
      switchOutCurve: widget.fadeCurve,
      layoutBuilder: _passthroughLayoutBuilder,
      child: child,
    );
  }

  static Widget _passthroughLayoutBuilder(
    Widget? currentChild,
    List<Widget> previousChildren,
  ) {
    return Stack(
      fit: StackFit.passthrough,
      alignment: Alignment.center,
      children: <Widget>[...previousChildren, ?currentChild],
    );
  }
}

enum _RetryPhase { loading, loaded, exhausted }
