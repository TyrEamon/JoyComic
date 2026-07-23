import 'package:flutter/material.dart';

import '../../../foundation/reader_config.dart';
import '../../reader/providers/reader_provider.dart' hide ReaderImage;
import '../../reader/state/read_mode.dart';
import '../reader_v2_controller.dart';
import '../widgets/reader_v2_page_image.dart';

class ReaderV2Paged extends StatefulWidget {
  const ReaderV2Paged({
    super.key,
    required this.controller,
    required this.reader,
    required this.mode,
  });

  final ReaderV2Controller controller;
  final ReaderProvider reader;
  final ReadMode mode;

  @override
  State<ReaderV2Paged> createState() => _ReaderV2PagedState();
}

class _ReaderV2PagedState extends State<ReaderV2Paged> {
  TapDownDetails? _tapDown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restorePage());
  }

  @override
  void didUpdateWidget(ReaderV2Paged oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode ||
        oldWidget.controller.session.traceId !=
            widget.controller.session.traceId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restorePage());
    }
  }

  void _restorePage() {
    if (!mounted || !widget.reader.pageController.hasClients) return;
    final target = widget.mode.isDoublePage
        ? widget.controller.currentPage ~/ 2
        : widget.controller.currentPage;
    widget.reader.pageController.jumpToPage(target);
  }

  void _handleTap() {
    final details = _tapDown;
    if (details == null) return;
    final width = context.size?.width ?? MediaQuery.sizeOf(context).width;
    final conf = ReaderConf.instance;
    if (!conf.enableGesture) {
      widget.reader.openOrCloseToolbar();
      return;
    }
    final edge = width * (1 - conf.horizontalCenterFraction) / 2;
    if (details.localPosition.dx < edge) {
      widget.reader.pageTurnForHorizontal(widget.mode.isReverse);
    } else if (details.localPosition.dx > width - edge) {
      widget.reader.pageTurnForHorizontal(!widget.mode.isReverse);
    } else {
      widget.reader.openOrCloseToolbar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = widget.controller.pages;
    final doublePage = widget.mode.isDoublePage;
    final itemCount = doublePage ? (pages.length + 1) ~/ 2 : pages.length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _tapDown = details,
      onTap: _handleTap,
      child: ColoredBox(
        color: Colors.black,
        child: PageView.builder(
          controller: widget.reader.pageController,
          reverse: widget.mode.isReverse,
          itemCount: itemCount,
          onPageChanged: (index) =>
              widget.controller.setCurrentPage(doublePage ? index * 2 : index),
          itemBuilder: (context, index) {
            final first = doublePage ? index * 2 : index;
            final indexes = <int>[
              first,
              if (doublePage && first + 1 < pages.length) first + 1,
            ];
            final ordered = widget.mode.isReverse
                ? indexes.reversed.toList(growable: false)
                : indexes;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final pageIndex in ordered)
                  Expanded(child: _buildPage(pageIndex)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPage(int index) {
    if (!widget.controller.shouldLoad(index)) {
      return const SizedBox.expand();
    }
    final page = widget.controller.pages[index];
    return LayoutBuilder(
      builder: (context, constraints) => ReaderV2PageImage(
        key: ValueKey<String>(
          '${widget.controller.session.traceId}|${page.cacheKey}',
        ),
        page: page,
        session: widget.controller.session,
        scheduler: widget.controller.scheduler,
        priority: widget.controller.priorityFor(index),
        bytesLoader: widget.controller.bytesLoader,
        height: constraints.maxHeight,
        placeholderHeight: constraints.maxHeight,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        onImageSize: (size) => widget.controller.recordImageSize(page, size),
      ),
    );
  }
}
