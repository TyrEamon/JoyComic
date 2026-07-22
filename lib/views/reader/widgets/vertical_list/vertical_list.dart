/// 竖直连续阅读。
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../providers/list_state_provider.dart';
import '../../providers/reader_provider.dart' hide ReaderImage;
import '../../utils/reader_pipeline.dart';
import '../../utils/reader_utils.dart';
import '../reader_image.dart';
import 'gesture.dart';

Size resolveVerticalReaderViewportSize(
  BoxConstraints constraints,
  Size mediaSize,
  double widthRatio,
) {
  final factor = widthRatio.clamp(0.05, 1.0);
  final availableWidth =
      constraints.maxWidth.isFinite && constraints.maxWidth > 1
      ? constraints.maxWidth
      : (mediaSize.width.isFinite && mediaSize.width > 1
            ? mediaSize.width
            : 390.0);
  final availableHeight =
      constraints.maxHeight.isFinite && constraints.maxHeight > 1
      ? constraints.maxHeight
      : (mediaSize.height.isFinite && mediaSize.height > 1
            ? mediaSize.height
            : 844.0);
  return Size(availableWidth * factor, availableHeight);
}

/// Keeps the actual scrolling viewport paintable when an ancestor temporarily
/// reports a zero-width probe constraint.
class VerticalReaderViewport extends StatelessWidget {
  const VerticalReaderViewport({
    super.key,
    required this.size,
    required this.child,
  });

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasUsableWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 1;
        final hasUsableHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 1;
        if (hasUsableWidth && hasUsableHeight) {
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox.fromSize(size: size, child: child),
          );
        }

        final mediaWidth = MediaQuery.sizeOf(context).width;
        final canvasWidth = mediaWidth.isFinite && mediaWidth > size.width
            ? mediaWidth
            : size.width;
        return SizedBox(
          width: constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : size.width,
          height: constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : size.height,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: canvasWidth,
            maxWidth: canvasWidth,
            minHeight: size.height,
            maxHeight: size.height,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox.fromSize(size: size, child: child),
            ),
          ),
        );
      },
    );
  }
}

class VerticalList extends StatefulWidget {
  const VerticalList({super.key});

  @override
  State<VerticalList> createState() => _VerticalListState();
}

class _VerticalListState extends State<VerticalList> {
  final ScrollController _scrollController = ScrollController();
  final Object _scrollOwner = Object();
  final List<GlobalKey> _itemKeys = <GlobalKey>[];
  ReaderProvider? _attachedReader;
  bool _loggedOpen = false;
  bool _initialPositionScheduled = false;
  double _layoutWidth = 390;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reader = context.reader;
    if (identical(_attachedReader, reader)) return;
    _attachedReader?.detachVerticalScrollActions(_scrollOwner);
    _attachedReader = reader;
    reader.attachVerticalScrollActions(
      _scrollOwner,
      VerticalReaderScrollActions(
        isAttached: () => _scrollController.hasClients,
        jumpToIndex: _jumpToIndex,
        scrollBy: _scrollBy,
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _attachedReader?.detachVerticalScrollActions(_scrollOwner);
    _scrollController.dispose();
    super.dispose();
  }

  double _pageHeight(int index) {
    final reader = _attachedReader;
    if (reader == null || index < 0 || index >= reader.images.length) {
      return _layoutWidth * 4 / 3;
    }
    final cached = ReaderImageSizeCache.get(reader.images[index].cacheKey);
    if (cached != null && cached.width > 0 && cached.height > 0) {
      return _layoutWidth * cached.height / cached.width;
    }
    return _layoutWidth * 1355 / 960;
  }

  double _offsetForIndex(int index) {
    var offset = 0.0;
    for (var page = 0; page < index; page++) {
      offset += _pageHeight(page);
    }
    return offset;
  }

  int _indexAtOffset(double offset, int count) {
    var cursor = 0.0;
    for (var index = 0; index < count; index++) {
      cursor += _pageHeight(index);
      if (offset < cursor) return index;
    }
    return count - 1;
  }

  void _onScroll() {
    final reader = _attachedReader;
    if (reader == null || reader.images.isEmpty) return;
    final index = _indexAtOffset(
      _scrollController.offset + 1,
      reader.images.length,
    );
    reader.onPageNoChanged(index);
  }

  void _jumpToIndex(int index) {
    final reader = _attachedReader;
    if (reader == null ||
        reader.images.isEmpty ||
        !_scrollController.hasClients) {
      return;
    }
    final safeIndex = index.clamp(0, reader.images.length - 1);
    final itemContext = safeIndex < _itemKeys.length
        ? _itemKeys[safeIndex].currentContext
        : null;
    if (itemContext != null) {
      Scrollable.ensureVisible(itemContext, alignment: 0);
      return;
    }
    final position = _scrollController.position;
    final target = _offsetForIndex(
      safeIndex,
    ).clamp(0.0, position.maxScrollExtent);
    _scrollController.jumpTo(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || safeIndex >= _itemKeys.length) return;
      final context = _itemKeys[safeIndex].currentContext;
      if (context != null) Scrollable.ensureVisible(context, alignment: 0);
    });
  }

  void _scrollBy(double offset, Duration duration) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final target = (_scrollController.offset + offset).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if (duration == Duration.zero) {
      _scrollController.jumpTo(target);
    } else {
      _scrollController.animateTo(
        target,
        duration: duration,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final physics = context.stateSelector((p) => p.physics);
    final widthRatio = context.stateSelector((p) => p.verticalListWidthRatio);
    final pageCount = context.selector((p) => p.pageCount);
    final images = context.selector((p) => p.images);
    final traceId = context.reader.traceId;
    final initialPage = context.reader.pageNo;
    final mq = MediaQuery.sizeOf(context);

    while (_itemKeys.length < pageCount) {
      _itemKeys.add(GlobalKey());
    }
    if (_itemKeys.length > pageCount) {
      _itemKeys.removeRange(pageCount, _itemKeys.length);
    }

    return GestureWrapper(
      openOrCloseToolbar: context.reader.openOrCloseToolbar,
      jumpOffset: context.reader.pageTurnForVertical,
      child: ColoredBox(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewportSize = resolveVerticalReaderViewportSize(
              constraints,
              mq,
              widthRatio,
            );
            _layoutWidth = viewportSize.width;
            if (!_loggedOpen) {
              _loggedOpen = true;
              ReaderPipeline.listBuild(pageCount: pageCount, mq: mq);
              ReaderPipeline.mark(
                ReaderStage.listBuild,
                detail:
                    'ListView ratio=$widthRatio '
                    'viewport=${viewportSize.width}x${viewportSize.height} '
                    'constraints=$constraints',
              );
            }
            final cacheWidth = computeImageCacheWidth(
              layoutWidth: viewportSize.width,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
            );
            context.reader.updatePreloadCacheWidth(cacheWidth);

            if (!_initialPositionScheduled && initialPage > 0) {
              _initialPositionScheduled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _jumpToIndex(initialPage);
              });
            }

            return VerticalReaderViewport(
              size: viewportSize,
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.zero,
                physics: physics,
                scrollCacheExtent: ScrollCacheExtent.pixels(mq.height * 2),
                itemCount: pageCount + 1,
                addAutomaticKeepAlives: false,
                itemBuilder: (context, index) {
                  if (index == pageCount) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        '本章完',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white54,
                        ),
                      ),
                    );
                  }

                  final item = images[index];
                  if (index < 5) {
                    ReaderPipeline.tileBuild(index, cacheKey: item.cacheKey);
                  }
                  return KeyedSubtree(
                    key: _itemKeys[index],
                    child: ReaderImage(
                      key: ValueKey(item.cacheKey),
                      url: item.url,
                      cacheKey: item.cacheKey,
                      headers: item.headers,
                      fallbackUrls: item.fallbackUrls,
                      bytesTransformer: item.bytesTransformer,
                      cacheWidth: cacheWidth,
                      placeholderHeight: _pageHeight(index),
                      fit: BoxFit.contain,
                      alignment: Alignment.topCenter,
                      traceId: traceId,
                      imageIndex: index,
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
