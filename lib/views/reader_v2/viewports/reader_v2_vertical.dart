import 'package:flutter/material.dart';

import '../../../foundation/reader_config.dart';
import '../../reader/providers/reader_provider.dart' hide ReaderImage;
import '../reader_v2_controller.dart';
import '../widgets/reader_v2_page_image.dart';

class ReaderV2Vertical extends StatefulWidget {
  const ReaderV2Vertical({
    super.key,
    required this.controller,
    required this.reader,
    required this.widthRatio,
    required this.physics,
  });

  final ReaderV2Controller controller;
  final ReaderProvider reader;
  final double widthRatio;
  final ScrollPhysics physics;

  @override
  State<ReaderV2Vertical> createState() => _ReaderV2VerticalState();
}

class _ReaderV2VerticalState extends State<ReaderV2Vertical> {
  late final ScrollController _scrollController;
  final Object _scrollOwner = Object();
  TapDownDetails? _tapDown;
  double _layoutWidth = 390;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    widget.reader.attachVerticalScrollActions(
      _scrollOwner,
      VerticalReaderScrollActions(
        isAttached: () => _scrollController.hasClients,
        jumpToIndex: _jumpToIndex,
        scrollBy: _scrollBy,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.reader.pageNo > 0) {
        _jumpToIndex(widget.reader.pageNo);
      }
    });
  }

  @override
  void didUpdateWidget(ReaderV2Vertical oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.reader, widget.reader)) {
      oldWidget.reader.detachVerticalScrollActions(_scrollOwner);
      widget.reader.attachVerticalScrollActions(
        _scrollOwner,
        VerticalReaderScrollActions(
          isAttached: () => _scrollController.hasClients,
          jumpToIndex: _jumpToIndex,
          scrollBy: _scrollBy,
        ),
      );
    }
  }

  double _offsetForIndex(int index) {
    var offset = 0.0;
    for (var page = 0; page < index; page++) {
      offset += widget.controller.pageHeight(page, _layoutWidth);
    }
    return offset;
  }

  int _indexAtOffset(double offset) {
    var cursor = 0.0;
    for (var index = 0; index < widget.controller.pages.length; index++) {
      cursor += widget.controller.pageHeight(index, _layoutWidth);
      if (offset < cursor) return index;
    }
    return widget.controller.pages.isEmpty
        ? 0
        : widget.controller.pages.length - 1;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    widget.controller.setCurrentPage(
      _indexAtOffset(_scrollController.offset + 1),
    );
  }

  void _jumpToIndex(int index) {
    if (!_scrollController.hasClients || widget.controller.pages.isEmpty) {
      return;
    }
    final position = _scrollController.position;
    final target = _offsetForIndex(
      index.clamp(0, widget.controller.pages.length - 1),
    ).clamp(0.0, position.maxScrollExtent);
    _scrollController.jumpTo(target);
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

  void _handleTap() {
    final details = _tapDown;
    if (details == null) return;
    final height = context.size?.height ?? MediaQuery.sizeOf(context).height;
    final conf = ReaderConf.instance;
    if (!conf.enableGesture) {
      widget.reader.openOrCloseToolbar();
      return;
    }
    final edge = height * (1 - conf.verticalCenterFraction) / 2;
    if (details.localPosition.dy < edge) {
      widget.reader.pageTurnForVertical(-height * conf.slipFactor);
    } else if (details.localPosition.dy > height - edge) {
      widget.reader.pageTurnForVertical(height * conf.slipFactor);
    } else {
      widget.reader.openOrCloseToolbar();
    }
  }

  @override
  void dispose() {
    widget.reader.detachVerticalScrollActions(_scrollOwner);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.controller.pages;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 1
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        _layoutWidth = availableWidth * widget.widthRatio.clamp(0.05, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _tapDown = details,
          onTap: _handleTap,
          child: ColoredBox(
            color: Colors.black,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: _layoutWidth,
                child: ListView.builder(
                  controller: _scrollController,
                  physics: widget.physics,
                  padding: EdgeInsets.zero,
                  // ignore: deprecated_member_use
                  cacheExtent: 0,
                  itemCount: pages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == pages.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          '本章完',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }
                    final height = widget.controller.pageHeight(
                      index,
                      _layoutWidth,
                    );
                    if (!widget.controller.shouldLoad(index)) {
                      return SizedBox(height: height);
                    }
                    final page = pages[index];
                    return ReaderV2PageImage(
                      key: ValueKey<String>(
                        '${widget.controller.session.traceId}|${page.cacheKey}',
                      ),
                      page: page,
                      session: widget.controller.session,
                      scheduler: widget.controller.scheduler,
                      priority: widget.controller.priorityFor(index),
                      bytesLoader: widget.controller.bytesLoader,
                      placeholderHeight: height,
                      fit: BoxFit.fitWidth,
                      onImageSize: (size) {
                        widget.controller.recordImageSize(page, size);
                        if (mounted) setState(() {});
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
