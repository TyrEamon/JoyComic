import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../comic_source/comic_source.dart';
import '../../database/read_record_helper.dart';
import '../../foundation/reader_config.dart';
import '../../network/res.dart';
import '../reader/providers/list_state_provider.dart';
import '../reader/providers/reader_provider.dart';
import '../reader/state/comic_state.dart';
import '../reader/widgets/app_bar.dart';
import '../reader/widgets/bottom.dart';
import '../reader/widgets/error_page.dart';
import '../reader/widgets/next_chapter.dart';
import '../reader/widgets/page_no_tag.dart';
import '../reader/widgets/reader_keyboard_listener.dart';
import 'reader_v2_controller.dart';
import 'viewports/reader_v2_paged.dart';
import 'viewports/reader_v2_vertical.dart';

class ReaderV2 extends StatefulWidget {
  const ReaderV2({
    super.key,
    required this.comicState,
    this.imageLoader,
    this.readRecordHelper,
    this.readRecordDebounce = const Duration(milliseconds: 250),
  });

  final ComicState comicState;
  final ReaderImageLoader? imageLoader;
  final ReadRecordHelper? readRecordHelper;
  final Duration readRecordDebounce;

  @override
  State<ReaderV2> createState() => _ReaderV2State();
}

class _ReaderV2State extends State<ReaderV2> {
  double _scrollAccumulator = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  ReaderImageLoader? _resolveImageLoader(ComicSource? source) {
    if (widget.comicState.type == ReaderType.local) {
      final paths = List<String>.unmodifiable(widget.comicState.localPagePaths);
      return (_, __) async => Res<List<String>>(paths);
    }
    if (widget.imageLoader != null) return widget.imageLoader;
    final sourceLoader = source?.loadComicPages;
    if (sourceLoader == null) return null;
    return (comicId, episodeId) => sourceLoader(comicId, episodeId);
  }

  @override
  Widget build(BuildContext context) {
    final source = ComicSource.find(widget.comicState.sourceKey);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ReaderProvider>(
          create: (_) => ReaderProvider(
            state: widget.comicState,
            imageLoader: _resolveImageLoader(source),
            imageConfigResolver: widget.comicState.type == ReaderType.local
                ? null
                : source?.getImageLoadingConfig,
            readRecordHelper: widget.readRecordHelper,
            readRecordDebounce: widget.readRecordDebounce,
          ),
        ),
        ChangeNotifierProvider<ListStateProvider>(
          create: (_) => ListStateProvider(),
        ),
        ChangeNotifierProvider<ReaderV2Controller>(
          create: (context) => ReaderV2Controller(
            reader: context.read<ReaderProvider>(),
            preloadCount: ReaderConf.instance.preloadImageCount,
          ),
        ),
      ],
      child: _ReaderV2Content(
        onScrollNotification: (notification, reader, listState) {
          if (notification is ScrollUpdateNotification) {
            _scrollAccumulator += (notification.scrollDelta ?? 0).abs();
            if (_scrollAccumulator >= 30) {
              if (!listState.lockMenu) {
                reader.hideToolbar();
              }
              _scrollAccumulator = 0;
            }
          } else if (notification is ScrollEndNotification) {
            _scrollAccumulator = 0;
          }
          return false;
        },
      ),
    );
  }
}

class _ReaderV2Content extends StatelessWidget {
  const _ReaderV2Content({required this.onScrollNotification});

  final bool Function(ScrollNotification, ReaderProvider, ListStateProvider)
  onScrollNotification;

  @override
  Widget build(BuildContext context) {
    final reader = context.watch<ReaderProvider>();
    final controller = context.watch<ReaderV2Controller>();
    final listState = context.watch<ListStateProvider>();
    final ready =
        reader.loadingState == ReaderLoadState.success &&
        controller.pages.isNotEmpty;

    final viewport = reader.readMode.isVertical
        ? ReaderV2Vertical(
            key: ValueKey<String>(controller.session.traceId),
            controller: controller,
            reader: reader,
            widthRatio: listState.verticalListWidthRatio,
            physics: listState.physics,
          )
        : ReaderV2Paged(
            key: ValueKey<String>(
              '${controller.session.traceId}|${reader.readMode.name}',
            ),
            controller: controller,
            reader: reader,
            mode: reader.readMode,
          );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        key: const ValueKey<String>('reader-v2-stack'),
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: switch (reader.loadingState) {
              ReaderLoadState.success when ready =>
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) =>
                      onScrollNotification(notification, reader, listState),
                  child: ReaderKeyboardListener(
                    handlers: {
                      LogicalKeyboardKey.arrowLeft: reader.prev,
                      LogicalKeyboardKey.arrowRight: reader.next,
                      LogicalKeyboardKey.arrowUp: reader.prev,
                      LogicalKeyboardKey.arrowDown: reader.next,
                      LogicalKeyboardKey.pageUp: reader.prev,
                      LogicalKeyboardKey.pageDown: reader.next,
                    },
                    child: viewport,
                  ),
                ),
              ReaderLoadState.error => ErrorPage(
                errorMessage: reader.loadingErrorMessage ?? '加载失败',
                onRetry: reader.retry,
                canPop: true,
                traceId: reader.traceId,
                onOpenLogs: () => _openLogs(context),
              ),
              _ => _ReaderV2Loading(
                traceId: reader.traceId,
                onOpenLogs: () => _openLogs(context),
              ),
            },
          ),
          if (ready && !reader.showToolbar)
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: IconButton(
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  style: IconButton.styleFrom(backgroundColor: Colors.black54),
                  onPressed: () {
                    reader.stopPageTurn();
                    context.pop();
                  },
                ),
              ),
            ),
          if (ready && listState.showPageNumbers) const ReaderPageNoTag(),
          if (ready) const ReaderNextChapter(),
          const ReaderAppBar(),
          if (ready) const ReaderBottom(),
        ],
      ),
      drawer: Drawer(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '章节列表',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: reader.chapters.length,
                  itemBuilder: (context, index) {
                    final chapter = reader.chapters[index];
                    return ListTile(
                      selected: index == reader.chapterIndex,
                      title: Text(chapter.name),
                      onTap: index == reader.chapterIndex
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              reader.go(chapter);
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _openLogs(BuildContext context) {
    try {
      context.push('/logs');
    } catch (_) {}
  }
}

class _ReaderV2Loading extends StatelessWidget {
  const _ReaderV2Loading({this.traceId, required this.onOpenLogs});

  final String? traceId;
  final VoidCallback onOpenLogs;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 16),
            const Text('正在加载章节图片…', style: TextStyle(color: Colors.white70)),
            if (traceId != null) ...[
              const SizedBox(height: 8),
              Text(
                'trace=$traceId',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(onPressed: onOpenLogs, child: const Text('查看日志')),
          ],
        ),
      ),
    );
  }
}
