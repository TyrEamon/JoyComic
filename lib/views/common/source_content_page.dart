/// Generic paginated content page backed by a single [ComicSource].
library source_content_page;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/log.dart';
import '../../network/base_comic.dart';
import 'source_content_models.dart' as models;
import 'widgets/comic_grid.dart';
import 'widgets/empty_state.dart';
import 'widgets/loading_grid.dart';

class SourceContentPage extends StatefulWidget {
  const SourceContentPage({
    super.key,
    required this.sourceKey,
    required this.kind,
    required this.category,
    this.param,
    this.sort,
  });

  final String sourceKey;
  final String kind;
  final String category;
  final String? param;
  final String? sort;

  @override
  State<SourceContentPage> createState() => _SourceContentPageState();
}

class _SourceContentPageState extends State<SourceContentPage> {
  List<BaseComic> _comics = const [];
  List<models.SourceSortOption> _sortOptions = const [];
  late String? _selectedSort;
  int _currentPage = 0;
  int _requestGeneration = 0;
  bool _loadingInitial = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _reachedEnd = false;
  String? _initialError;
  String? _loadMoreError;

  ComicSource? get _source => ComicSource.find(widget.sourceKey);

  @override
  void initState() {
    super.initState();
    _selectedSort = widget.sort;
    _loadCategoryMetadata();
    _loadInitial();
  }

  Future<void> _loadCategoryMetadata() async {
    if (widget.kind != 'category') return;
    final loader = _source?.loadSourceCategories;
    if (loader == null) return;
    try {
      final response = await loader();
      if (!mounted || response.error) return;
      models.SourceCategory? match;
      for (final category in response.data) {
        if (category.key == widget.category) {
          match = category;
          break;
        }
      }
      final sortOptions = match?.sortOptions;
      if (sortOptions == null) return;
      setState(() {
        _sortOptions = sortOptions;
        if (_selectedSort == null && _sortOptions.isNotEmpty) {
          _selectedSort = _sortOptions.first.key;
        }
      });
    } catch (error, stackTrace) {
      Log.e(
        'Failed to load ${widget.sourceKey} category metadata',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _selectSort(String sort) async {
    if (sort == _selectedSort ||
        _loadingInitial ||
        _refreshing ||
        _loadingMore) {
      return;
    }
    setState(() {
      _selectedSort = sort;
      _comics = const [];
      _currentPage = 0;
      _reachedEnd = false;
      _initialError = null;
      _loadMoreError = null;
    });
    await _loadPage(1, replace: true);
  }

  Future<void> _loadInitial() => _loadPage(1, replace: true);

  Future<void> _refresh() async {
    if (_refreshing || _loadingInitial || _loadingMore) return;
    await _loadPage(1, replace: true, refreshing: true);
  }

  Future<void> _loadMore() async {
    if (_loadingInitial ||
        _refreshing ||
        _loadingMore ||
        _reachedEnd ||
        _loadMoreError != null) {
      return;
    }
    await _loadPage(_currentPage + 1, replace: false);
  }

  Future<void> _retryLoadMore() async {
    if (_loadingMore) return;
    setState(() => _loadMoreError = null);
    await _loadMore();
  }

  Future<void> _loadPage(
    int page, {
    required bool replace,
    bool refreshing = false,
  }) async {
    final generation = ++_requestGeneration;
    final source = _source;
    final loader = source?.loadSourceContent;
    if (loader == null) {
      if (!mounted) return;
      setState(() {
        _loadingInitial = false;
        _refreshing = false;
        _loadingMore = false;
        _initialError = source == null ? '漫画源不可用' : '${source.name}暂不支持此列表';
      });
      return;
    }

    setState(() {
      if (replace) {
        _refreshing = refreshing;
        _loadingInitial = !refreshing && _comics.isEmpty;
        _initialError = null;
        _loadMoreError = null;
      } else {
        _loadingMore = true;
        _loadMoreError = null;
      }
    });

    final query = models.SourceContentQuery(
      categoryKey: widget.category,
      param: widget.param,
      page: page,
      sort: _selectedSort,
    );

    try {
      final response = await loader(query);
      if (!mounted || generation != _requestGeneration) return;
      if (response.error) {
        setState(() {
          if (replace) {
            _initialError = response.errorMessageWithoutNull;
          } else {
            _loadMoreError = response.errorMessageWithoutNull;
          }
        });
        return;
      }

      final contentPage = response.data;
      final merged = models.mergeSourceContentPage(
        existingComics: _comics,
        incomingComics: contentPage.comics,
        previousPage: _currentPage,
        requestedPage: page,
        maxPage: contentPage.maxPage,
        replace: replace,
      );
      setState(() {
        _comics = merged.comics;
        _currentPage = merged.currentPage;
        _reachedEnd = merged.reachedEnd;
        _initialError = null;
        _loadMoreError = null;
      });
    } catch (error, stackTrace) {
      Log.e(
        'Failed to load ${widget.sourceKey} content page $page',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        if (replace) {
          _initialError = error.toString();
        } else {
          _loadMoreError = error.toString();
        }
      });
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _loadingInitial = false;
          _refreshing = false;
          _loadingMore = false;
        });
      }
    }
  }

  Map<String, dynamic>? _coverHeaders(ComicGridItem item) {
    final cover = item.coverUrl;
    if (cover == null || cover.isEmpty) return null;
    return _source?.getThumbnailLoadingConfig?.call(cover);
  }

  String get _pageTitle {
    final sourceName = _source?.name ?? widget.sourceKey;
    final category = widget.category.trim();
    if (category.isEmpty || widget.kind == 'home') return '$sourceName内容';
    return '$sourceName · $category';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: Text(_pageTitle),
        backgroundColor: context.pageBackground,
      ),
      body: Column(
        children: [
          if (_sortOptions.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  for (final option in _sortOptions)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        key: ValueKey('source-content-sort-${option.key}'),
                        label: Text(option.title),
                        selected: option.key == _selectedSort,
                        onSelected: (_) => _selectSort(option.key),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingInitial && _comics.isEmpty) {
      return const LoadingGrid();
    }
    if (_initialError != null && _comics.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: '加载失败',
        subtitle: _initialError,
        actionLabel: '重试',
        onAction: _loadInitial,
      );
    }
    if (_comics.isEmpty) {
      return EmptyState(
        title: '暂无内容',
        subtitle: '该分区暂时没有可显示的漫画',
        actionLabel: '刷新',
        onAction: _refresh,
      );
    }

    final items = [
      for (final comic in _comics)
        ComicGridItem(
          id: comic.id,
          title: comic.title,
          coverUrl: comic.cover,
          subtitle: comic.subTitle,
          sourceKey: widget.sourceKey,
        ),
    ];
    return Column(
      children: [
        Expanded(
          child: ComicGrid(
            items: items,
            loading: _loadingMore,
            onRefresh: _refresh,
            onLoadMore: _loadMore,
            hasMore: !_reachedEnd && _loadMoreError == null,
            coverHeadersBuilder: _coverHeaders,
            onItemTap: (item) => context.push(_detailLocation(item.id)),
          ),
        ),
        if (_initialError != null)
          _PageFooter(
            child: TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('刷新失败，点击重试'),
            ),
          )
        else if (_loadMoreError != null)
          _PageFooter(
            child: TextButton.icon(
              onPressed: _retryLoadMore,
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: const Text('加载失败，点击重试'),
            ),
          )
        else if (_reachedEnd)
          _PageFooter(
            child: Text(
              '已经到底了',
              style: TextStyle(color: context.tertiaryTextColor, fontSize: 12),
            ),
          ),
      ],
    );
  }

  String _detailLocation(String comicId) =>
      Uri(pathSegments: ['', 'detail', widget.sourceKey, comicId]).toString();
}

class _PageFooter extends StatelessWidget {
  const _PageFooter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(height: 44, child: Center(child: child)),
    );
  }
}
