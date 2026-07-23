/// JM video browsing page backed by the dedicated video API.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../network/jm/jm_headers.dart';
import '../../network/jm/jm_network.dart';
import '../../network/res.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_safe_area.dart';

typedef JmVideoLoader =
    Future<Res<({List<JmVideoItem> items, int total})>> Function({
      int page,
      String videoType,
      String searchQuery,
    });

class VideoPage extends StatefulWidget {
  const VideoPage({super.key, this.loader});

  final JmVideoLoader? loader;

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with SingleTickerProviderStateMixin {
  static const _tabs = <({String label, String type, String query})>[
    (label: '全部', type: '', query: ''),
    (label: '小电影', type: 'movie', query: ''),
    (label: 'H动漫', type: 'video', query: 'H動漫'),
    (label: 'Cos', type: 'video', query: 'Cos'),
  ];

  late final TabController _tab = TabController(
    length: _tabs.length,
    vsync: this,
  );
  final _search = TextEditingController();
  List<JmVideoItem> _items = const <JmVideoItem>[];
  int _page = 1;
  int _total = 0;
  int _generation = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  JmVideoLoader get _loader => widget.loader ?? JmNetwork().getVideos;

  @override
  void initState() {
    super.initState();
    _tab.addListener(() {
      if (!_tab.indexIsChanging) _reload();
    });
    _reload();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _page = 1;
    });
    final result = await _loadPage(1);
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      if (result.error) {
        _error = result.errorMessageWithoutNull;
        _items = const <JmVideoItem>[];
        _total = 0;
      } else {
        _items = result.data.items;
        _total = result.data.total;
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _total) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    final result = await _loadPage(nextPage);
    if (!mounted || generation != _generation) return;
    setState(() {
      _loadingMore = false;
      if (result.error) {
        _error = result.errorMessageWithoutNull;
      } else {
        _page = nextPage;
        _items = <JmVideoItem>[..._items, ...result.data.items];
        _total = result.data.total;
      }
    });
  }

  Future<Res<({List<JmVideoItem> items, int total})>> _loadPage(int page) {
    final tab = _tabs[_tab.index];
    final typedQuery = _search.text.trim();
    return _loader(
      page: page,
      videoType: tab.type,
      searchQuery: typedQuery.isEmpty ? tab.query : typedQuery,
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text('影视'),
        backgroundColor: context.pageBackground,
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: <Tab>[for (final tab in _tabs) Tab(text: tab.label)],
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              key: const Key('video-search-field'),
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: '搜索影视',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_error!),
            TextButton(onPressed: _reload, child: const Text('重试')),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
                childAspectRatio: 0.78,
              ),
              itemCount: _items.length,
              itemBuilder: (_, index) => _VideoCard(
                item: _items[index],
                onTap: () {
                  final item = _items[index];
                  context.push(
                    Uri(
                      path: '/video/player/${item.id}',
                      queryParameters: <String, String>{
                        'title': item.title,
                        if (item.backlink.isNotEmpty) 'backlink': item.backlink,
                      },
                    ).toString(),
                  );
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                bottomContentInset(context),
              ),
              child: _items.length < _total
                  ? FilledButton.tonal(
                      key: const Key('video-load-more'),
                      onPressed: _loadingMore ? null : _loadMore,
                      child: Text(_loadingMore ? '加载中…' : '加载更多'),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.item, required this.onTap});

  final JmVideoItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: item.photo.isEmpty
                  ? ColoredBox(
                      color: context.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.movie_outlined),
                    )
                  : Image.network(
                      item.photo,
                      headers: imageHeaders(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: context.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
