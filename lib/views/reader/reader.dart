/// 阅读器主框架。
///
/// 接收 [ComicState] 与可选 [ReaderImageLoader]，创建 [ReaderProvider] 与
/// [ListStateProvider] 后按阅读模式（[ReadMode]）渲染 [VerticalList] 或
/// [HorizontalList]，并叠放工具栏、页码角标、下一章 FAB、菜单锁等 UI。
///
/// ```
/// MultiProvider（ReaderProvider + ListStateProvider）
///   └── Scaffold
///         ├── [listWidget]（VerticalList / HorizontalList）
///         ├── ReaderPageNoTag          ← 页码角标
///         ├── ReaderNextChapter        ← 下一章 FAB
///         ├── MenuLock                 ← 菜单锁按钮
///         ├── ReaderAppBar             ← 顶部工具栏
///         ├── ReaderBottom             ← 底部工具栏
///         └── Drawer                   ← 章节列表
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../comic_source/comic_source.dart';
import '../../database/read_record_helper.dart';
import '../../network/res.dart';
import 'providers/list_state_provider.dart';
import 'providers/reader_provider.dart';
import 'state/comic_state.dart';
import 'state/read_mode.dart';
import 'utils/reader_utils.dart';
import 'widgets/app_bar.dart';
import 'widgets/bottom.dart';
import 'widgets/error_page.dart';
import 'widgets/horizontal_list/horizontal_list.dart';
import 'widgets/menu_lock.dart';
import 'widgets/next_chapter.dart';
import 'widgets/page_no_tag.dart';
import 'widgets/reader_keyboard_listener.dart';
import 'widgets/vertical_list/vertical_list.dart';

/// Returns only a network loader suitable for route injection.
/// Local reader states deliberately receive no source loader.
ReaderImageLoader? readerRouteNetworkLoader(
  ComicState state,
  ComicSource? source,
) {
  if (state.type == ReaderType.local || source?.loadComicPages == null) {
    return null;
  }
  return (String comicId, String? ep) => source!.loadComicPages!(comicId, ep);
}

/// Resolves Reader content with local paths taking precedence over every
/// supplied or source-backed network loader.
ReaderImageLoader? resolveReaderImageLoader({
  required ComicState state,
  ReaderImageLoader? supplied,
  ComicSource? source,
}) {
  if (state.type == ReaderType.local) {
    final paths = List<String>.unmodifiable(state.localPagePaths);
    return (_, __) async => Res<List<String>>(paths);
  }
  return supplied ?? readerRouteNetworkLoader(state, source);
}

/// 阅读器页面。
class Reader extends StatefulWidget {
  /// [comicState] 为进入阅读器的初始状态快照。
  /// [imageLoader] 为外部图片加载回调；不传则尝试从 [ComicSource] 按 key 匹配。
  const Reader({
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
  State<Reader> createState() => _ReaderState();
}

class _ReaderState extends State<Reader> {
  double _scrollAccumulator = 0.0;
  static const double _hideToolbarScrollThreshold = 30.0;

  @override
  void initState() {
    super.initState();
    // 进入沉浸式阅读模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  ReaderImageLoader? _resolveImageLoader() => resolveReaderImageLoader(
    state: widget.comicState,
    supplied: widget.imageLoader,
    source: ComicSource.find(widget.comicState.sourceKey),
  );

  @override
  Widget build(BuildContext context) {
    final imageLoader = _resolveImageLoader();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ReaderProvider(
            state: widget.comicState,
            imageLoader: imageLoader,
            readRecordHelper: widget.readRecordHelper,
            readRecordDebounce: widget.readRecordDebounce,
          ),
        ),
        ChangeNotifierProvider(create: (_) => ListStateProvider()),
      ],
      child: _ReaderContent(
        scrollAccumulator: _scrollAccumulator,
        hideToolbarScrollThreshold: _hideToolbarScrollThreshold,
        onScrollNotification: (notification) {
          if (notification is ScrollUpdateNotification) {
            _scrollAccumulator += (notification.scrollDelta ?? 0.0).abs();
            if (_scrollAccumulator >= _hideToolbarScrollThreshold) {
              if (context.stateReader.lockMenu) {
                context.reader.collapseMenuLock();
              } else {
                context.reader.hideToolbar();
              }
              _scrollAccumulator = 0.0;
            }
          } else if (notification is ScrollEndNotification) {
            _scrollAccumulator = 0.0;
          }
          return false;
        },
      ),
    );
  }
}

class _ReaderContent extends StatelessWidget {
  const _ReaderContent({
    required this.scrollAccumulator,
    required this.hideToolbarScrollThreshold,
    required this.onScrollNotification,
  });

  final double scrollAccumulator;
  final double hideToolbarScrollThreshold;
  final bool Function(ScrollNotification) onScrollNotification;

  @override
  Widget build(BuildContext context) {
    final readMode = context.selector((p) => p.readMode);
    final chapterIndex = context.selector((p) => p.chapterIndex);
    final loadingState = context.selector((p) => p.loadingState);
    final loadingErrorMessage = context.selector((p) => p.loadingErrorMessage);
    final showPageNumbers = context.stateSelector((p) => p.showPageNumbers);
    final chapters = context.selector((p) => p.chapters);
    final prev = context.reader.prev;
    final next = context.reader.next;

    Widget listWidget = NotificationListener<ScrollNotification>(
      onNotification: onScrollNotification,
      child: readMode.isVertical
          ? const VerticalList()
          : const HorizontalList(),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: switch (loadingState) {
              ReaderLoadState.success => ReaderKeyboardListener(
                handlers: {
                  LogicalKeyboardKey.arrowLeft: prev,
                  LogicalKeyboardKey.arrowRight: next,
                  LogicalKeyboardKey.arrowUp: prev,
                  LogicalKeyboardKey.arrowDown: next,
                  LogicalKeyboardKey.pageUp: prev,
                  LogicalKeyboardKey.pageDown: next,
                },
                child: listWidget,
              ),
              ReaderLoadState.error => ErrorPage(
                errorMessage: loadingErrorMessage ?? '加载失败',
                onRetry: context.reader.retry,
                canPop: true,
              ),
              ReaderLoadState.loading => const Center(
                child: CircularProgressIndicator(),
              ),
              ReaderLoadState.idle => const Center(
                child: CircularProgressIndicator(),
              ),
            },
          ),

          if (showPageNumbers) const ReaderPageNoTag(),

          const ReaderNextChapter(),

          const MenuLock(),

          const ReaderAppBar(),

          const ReaderBottom(),
        ],
      ),
      drawer: Drawer(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
                child: Text(
                  '章节列表',
                  textAlign: TextAlign.center,
                  style: context.textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ScrollablePositionedList.builder(
                  initialScrollIndex: chapterIndex,
                  itemBuilder: (context, index) {
                    final chapter = chapters[index];
                    return ListTile(
                      enabled: index != chapterIndex,
                      title: Text(chapter.name),
                      onTap: () {
                        context.pop();
                        context.reader.go(chapter);
                      },
                    );
                  },
                  itemCount: chapters.length,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
