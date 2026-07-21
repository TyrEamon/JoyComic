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

import '../../foundation/log_export.dart';

import '../../comic_source/comic_source.dart';
import '../../database/read_record_helper.dart';
import '../../network/res.dart';
import 'providers/list_state_provider.dart';
import 'providers/reader_provider.dart';
import 'state/comic_state.dart';
import 'state/read_mode.dart';
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

  ReaderImageLoader? _resolveImageLoader(ComicSource? source) =>
      resolveReaderImageLoader(
        state: widget.comicState,
        supplied: widget.imageLoader,
        source: source,
      );

  ReaderImageConfigResolver? _resolveImageConfig(ComicSource? source) {
    if (widget.comicState.type == ReaderType.local) return null;
    return source?.getImageLoadingConfig;
  }

  @override
  Widget build(BuildContext context) {
    final source = ComicSource.find(widget.comicState.sourceKey);
    final imageLoader = _resolveImageLoader(source);
    final imageConfigResolver = _resolveImageConfig(source);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ReaderProvider(
            state: widget.comicState,
            imageLoader: imageLoader,
            imageConfigResolver: imageConfigResolver,
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

    // Pure black canvas for manga contrast once frames paint.
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
                traceId: context.reader.traceId,
                onOpenLogs: () {
                  try {
                    context.push('/logs');
                  } catch (_) {
                    // Navigation unavailable — trace ID remains copyable.
                  }
                },
              ),
              ReaderLoadState.loading => _ReaderLoadingView(
                message: '正在加载章节图片…',
                traceId: context.reader.traceId,
                onOpenLogs: () {
                  try {
                    context.push('/logs');
                  } catch (_) {}
                },
              ),
              ReaderLoadState.idle => _ReaderLoadingView(
                message: '正在准备阅读器…',
                traceId: context.reader.traceId,
                onOpenLogs: () {
                  try {
                    context.push('/logs');
                  } catch (_) {}
                },
              ),
            },
          ),

          // Page chrome is always painted above content so black canvas never
          // hides back / diagnostics while loading or after a silent failure.
          if (showPageNumbers && loadingState == ReaderLoadState.success)
            const ReaderPageNoTag(),

          if (loadingState == ReaderLoadState.success) ...[
            const ReaderNextChapter(),
            const MenuLock(),
          ],

          const ReaderAppBar(),

          if (loadingState == ReaderLoadState.success) const ReaderBottom(),
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
                  style: Theme.of(context).textTheme.titleLarge,
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

class _ReaderLoadingView extends StatefulWidget {
  const _ReaderLoadingView({
    required this.message,
    this.traceId,
    this.onOpenLogs,
  });

  final String message;
  final String? traceId;
  final VoidCallback? onOpenLogs;

  @override
  State<_ReaderLoadingView> createState() => _ReaderLoadingViewState();
}

class _ReaderLoadingViewState extends State<_ReaderLoadingView> {
  bool _exporting = false;

  Future<void> _exportTxt() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final note = widget.traceId == null || widget.traceId!.isEmpty
          ? 'from reader loading view'
          : 'from reader loading view; trace=${widget.traceId}';
      final ok = await exportJoyComicLogsTxt(context: context, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '已生成 TXT，请选择发送方式' : '暂无日志可导出'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$error')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // readerCanvas is pure black — force light controls so loading is not
    // perceived as a frozen black screen, and always expose diagnostics.
    const onDark = Color(0xFFECECEC);
    return Stack(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: onDark,
                  strokeWidth: 3,
                ),
                const SizedBox(height: 16),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: onDark,
                  ),
                ),
                if (widget.traceId != null && widget.traceId!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    'trace ${widget.traceId}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: onDark.withValues(alpha: 0.72),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        foregroundColor: onDark,
                        backgroundColor: const Color(0x33FFFFFF),
                      ),
                      onPressed: widget.onOpenLogs,
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('打开日志页'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        foregroundColor: const Color(0xFF111111),
                        backgroundColor: onDark,
                      ),
                      onPressed: _exporting ? null : _exportTxt,
                      icon: _exporting
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.ios_share_rounded),
                      label: Text(_exporting ? '导出中…' : '导出 TXT'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              tooltip: '返回',
              color: onDark,
              onPressed: context.canPop() ? () => context.pop() : null,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
        ),
      ],
    );
  }
}
