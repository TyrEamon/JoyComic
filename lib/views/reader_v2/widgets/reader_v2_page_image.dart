import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/reader_v2_scheduler.dart';
import '../core/reader_v2_session.dart';
import '../data/reader_v2_page.dart';
import '../image/reader_v2_image_provider.dart';

final class ReaderV2PageImage extends StatefulWidget {
  const ReaderV2PageImage({
    super.key,
    required this.page,
    required this.session,
    required this.scheduler,
    required this.priority,
    required this.bytesLoader,
    this.height,
    this.placeholderHeight = 300,
    this.fit = BoxFit.contain,
  });

  final ReaderV2Page page;
  final ReaderV2Session session;
  final ReaderV2Scheduler scheduler;
  final ReaderV2Priority priority;
  final ReaderV2BytesLoader bytesLoader;
  final double? height;
  final double placeholderHeight;
  final BoxFit fit;

  @override
  State<ReaderV2PageImage> createState() => _ReaderV2PageImageState();
}

final class _ReaderV2PageImageState extends State<ReaderV2PageImage>
    with WidgetsBindingObserver {
  late DisposableBuildContext<State<ReaderV2PageImage>> _scrollContext;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageStreamCompleterHandle? _keepAlive;
  ImageInfo? _info;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollContext = DisposableBuildContext<State<ReaderV2PageImage>>(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ReaderV2PageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.cacheKey != widget.page.cacheKey ||
        oldWidget.session.traceId != widget.session.traceId ||
        !identical(oldWidget.scheduler, widget.scheduler)) {
      _replaceInfo(null);
      _error = null;
      _resolve();
    }
  }

  void _resolve() {
    final base = ReaderV2ImageProvider(
      page: widget.page,
      session: widget.session,
      scheduler: widget.scheduler,
      priority: widget.priority,
      bytesLoader: widget.bytesLoader,
    );
    final provider = ScrollAwareImageProvider(
      context: _scrollContext,
      imageProvider: base,
    );
    final stream = provider.resolve(
      createLocalImageConfiguration(
        context,
        size: widget.height == null
            ? null
            : Size(MediaQuery.sizeOf(context).width, widget.height!),
      ),
    );
    if (_stream?.key == stream.key) return;
    _detach();
    _stream = stream;
    _listener = ImageStreamListener(
      (info, synchronousCall) {
        if (!mounted || widget.session.isCancelled) return;
        _replaceInfo(info);
        widget.session.record(
          'frame',
          page: widget.page.index,
          detail: '${info.image.width}x${info.image.height}',
        );
        setState(() => _error = null);
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted || widget.session.isCancelled) return;
        widget.session.record(
          'image-error',
          page: widget.page.index,
          detail: '$error',
        );
        setState(() => _error = error);
      },
    );
    stream.addListener(_listener!);
  }

  void _detach() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _keepAlive?.dispose();
    _keepAlive = null;
    _listener = null;
    _stream = null;
  }

  void _replaceInfo(ImageInfo? next) {
    final old = _info;
    _info = next;
    if (old != null && !identical(old, next)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detach();
    _replaceInfo(null);
    _scrollContext.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final fixedHeight = widget.height;
        final info = _info;
        if (info != null) {
          final height =
              fixedHeight ??
              width *
                  info.image.height.toDouble() /
                  info.image.width.toDouble();
          return SizedBox(
            width: width,
            height: height,
            child: RawImage(
              image: info.image,
              fit: fixedHeight == null ? BoxFit.fitWidth : widget.fit,
              alignment: Alignment.topCenter,
              filterQuality: FilterQuality.medium,
              scale: info.scale,
            ),
          );
        }
        return SizedBox(
          width: width,
          height: fixedHeight ?? widget.placeholderHeight,
          child: ColoredBox(
            color: Colors.black,
            child: Center(
              child: _error == null
                  ? const SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white54,
                      ),
                    )
                  : TextButton(
                      onPressed: () {
                        setState(() => _error = null);
                        _resolve();
                      },
                      child: const Text('重试'),
                    ),
            ),
          ),
        );
      },
    );
  }
}
