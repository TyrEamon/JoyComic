/// JM 精品专区：禁漫去碼&全彩化。
///
/// 数据源：
/// - 专区：`GET /promote_list?id=30`（官方首页运营分区）
/// - 去码：`search_query=禁漫去碼`
/// - 全彩：`search_query=禁漫全彩化`
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../comic_source/comic_source.dart';
import '../../network/jm/jm_network.dart';
import '../../network/res.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_safe_area.dart';
import '../common/widgets/comic_grid.dart';
import '../common/widgets/empty_state.dart';
import '../common/widgets/loading_grid.dart';

/// Injectable loader for tests.
typedef JmPremiumLoader =
    Future<Res<List<JmComicBrief>>> Function({
      required JmPremiumTab tab,
      required int page,
      required String order,
    });

enum JmPremiumTab {
  promote(label: '专区', query: ''),
  demosaic(label: '去码', query: '禁漫去碼'),
  fullColor(label: '全彩', query: '禁漫全彩化');

  const JmPremiumTab({required this.label, required this.query});

  final String label;
  final String query;
}

class JmPremiumPage extends StatefulWidget {
  const JmPremiumPage({
    super.key,
    this.loader,
    this.initialTab = JmPremiumTab.promote,
  });

  final JmPremiumLoader? loader;
  final JmPremiumTab initialTab;

  @override
  State<JmPremiumPage> createState() => _JmPremiumPageState();
}

class _JmPremiumPageState extends State<JmPremiumPage>
    with SingleTickerProviderStateMixin {
  static const _sortOptions = <({String key, String label, String order})>[
    (key: 'latest', label: '最新', order: 'mr'),
    (key: 'hot', label: '热门', order: 'mv'),
    (key: 'likes', label: '喜欢', order: 'tf'),
  ];

  late final TabController _tab = TabController(
    length: JmPremiumTab.values.length,
    vsync: this,
    initialIndex: JmPremiumTab.values
        .indexOf(widget.initialTab)
        .clamp(0, JmPremiumTab.values.length - 1),
  );

  final List<JmComicBrief> _comics = <JmComicBrief>[];
  int _page = 0;
  int? _total;
  int _generation = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String _sortKey = _sortOptions.first.key;

  JmPremiumTab get _currentTab => JmPremiumTab.values[_tab.index];

  String get _order {
    for (final option in _sortOptions) {
      if (option.key == _sortKey) return option.order;
    }
    return 'mr';
  }

  JmPremiumLoader get _loader => widget.loader ?? _defaultLoader;

  static Future<Res<List<JmComicBrief>>> _defaultLoader({
    required JmPremiumTab tab,
    required int page,
    required String order,
  }) {
    final client = JmNetwork();
    switch (tab) {
      case JmPremiumTab.promote:
        // promote_list has no sort param; order is ignored.
        return client.getPromoteList(jmPremiumPromoteId, page);
      case JmPremiumTab.demosaic:
      case JmPremiumTab.fullColor:
        return client.search(tab.query, page, order);
    }
  }

  @override
  void initState() {
    super.initState();
    _tab.addListener(() {
      if (!_tab.indexIsChanging) _reload();
    });
    _reload();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _page = 0;
      _total = null;
      _comics.clear();
    });
    final result = await _loader(tab: _currentTab, page: 1, order: _order);
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      if (result.error) {
        _error = result.errorMessageWithoutNull;
      } else {
        _page = 1;
        _comics
          ..clear()
          ..addAll(result.data);
        _total = result.subData is int ? result.subData as int : null;
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    final result = await _loader(
      tab: _currentTab,
      page: nextPage,
      order: _order,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _loadingMore = false;
      if (result.error) {
        _error = result.errorMessageWithoutNull;
        return;
      }
      _page = nextPage;
      _comics.addAll(result.data);
      if (result.subData is int) {
        _total = result.subData as int;
      }
      // Empty page means end of list when total is unknown.
      if (result.data.isEmpty) {
        _total = _comics.length;
      }
    });
  }

  bool get _hasMore {
    if (_total != null) return _comics.length < _total!;
    // Without total, allow load-more until an empty page arrives.
    return _page == 0 || _comics.isNotEmpty;
  }

  Future<void> _selectSort(String key) async {
    if (key == _sortKey || _loading || _loadingMore) return;
    // promote tab has no server-side sort.
    if (_currentTab == JmPremiumTab.promote) return;
    setState(() => _sortKey = key);
    await _reload();
  }

  List<ComicGridItem> get _gridItems => [
    for (final comic in _comics)
      ComicGridItem(
        id: comic.id,
        title: comic.title,
        coverUrl: comic.cover,
        subtitle: comic.subTitle,
        sourceKey: 'jm',
      ),
  ];

  Map<String, dynamic>? _coverHeaders(ComicGridItem item) {
    final cover = item.coverUrl;
    if (cover == null || cover.isEmpty) return null;
    return ComicSource.find('jm')?.getThumbnailLoadingConfig?.call(cover);
  }

  @override
  Widget build(BuildContext context) {
    final showSort = _currentTab != JmPremiumTab.promote;
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text(jmPremiumPromoteTitle),
        backgroundColor: context.pageBackground,
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: [
            for (final tab in JmPremiumTab.values)
              Tab(key: ValueKey('premium-tab-${tab.name}'), text: tab.label),
          ],
        ),
      ),
      body: Column(
        children: [
          if (showSort)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: _sortOptions.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final option = _sortOptions[index];
                  final selected = option.key == _sortKey;
                  return ChoiceChip(
                    key: ValueKey('premium-sort-${option.key}'),
                    label: Text(option.label),
                    selected: selected,
                    onSelected: (_) => _selectSort(option.key),
                  );
                },
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _comics.isEmpty) {
      return const LoadingGrid();
    }
    if (_error != null && _comics.isEmpty) {
      return EmptyState(title: _error!, actionLabel: '重试', onAction: _reload);
    }
    if (_comics.isEmpty) {
      return EmptyState(title: '暂无内容', actionLabel: '刷新', onAction: _reload);
    }
    return ComicGrid(
      items: _gridItems,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        bottomContentInset(context),
      ),
      loading: _loadingMore,
      hasMore: _hasMore,
      onRefresh: _reload,
      onLoadMore: _loadMore,
      coverHeadersBuilder: _coverHeaders,
      onItemTap: (item) => context.push('/detail/jm/${item.id}'),
    );
  }
}
