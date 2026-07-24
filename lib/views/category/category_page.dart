/// Dual-source category browser with independent source state.
library;

import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/log.dart';
import '../../foundation/source_session_notifier.dart';
import '../../theme/app_spacing.dart';
import '../common/source_content_models.dart';
import '../common/widgets/empty_state.dart';

const _categorySourceKeys = {'jm', 'picacg'};

String buildCategoryContentLocation({
  required String sourceKey,
  required SourceCategory category,
}) {
  final sort = category.sortOptions.isEmpty
      ? null
      : category.sortOptions.first.key;
  return Uri(
    pathSegments: ['', 'content', sourceKey],
    queryParameters: {
      'kind': 'category',
      'category': category.key,
      if (category.param != null) 'param': category.param,
      if (sort != null) 'sort': sort,
    },
  ).toString();
}

class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    with SingleTickerProviderStateMixin {
  late final List<ComicSource> _sources;
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _sources = ComicSource.sources
        .where(
          (source) =>
              _categorySourceKeys.contains(source.key) &&
              source.loadSourceCategories != null,
        )
        .toList(growable: false);
    if (_sources.isNotEmpty) {
      _tabController = TabController(length: _sources.length, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sources.isEmpty) {
      return Scaffold(
        backgroundColor: context.pageBackground,
        body: const SafeArea(
          child: EmptyState(
            icon: Icons.category_outlined,
            title: '暂无可用分类源',
            subtitle: '请先在设置中启用支持分类的漫画源',
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text('分类'),
        backgroundColor: context.pageBackground,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            for (final source in _sources)
              Tab(
                key: ValueKey('category-source-tab-${source.key}'),
                text: source.name,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '搜索漫画',
            onPressed: () => context.push('/search'),
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          for (final source in _sources)
            _SourceCategoryView(
              key: PageStorageKey('category-source-${source.key}'),
              source: source,
            ),
        ],
      ),
    );
  }
}

class _SourceCategoryView extends StatefulWidget {
  const _SourceCategoryView({super.key, required this.source});

  final ComicSource source;

  @override
  State<_SourceCategoryView> createState() => _SourceCategoryViewState();
}

class _SourceCategoryViewState extends State<_SourceCategoryView>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  List<SourceCategory> _categories = const [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  int _loadGeneration = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    SourceSessionNotifier.instance.addListener(_onSourceSessionChanged);
    _load();
  }

  void _onSourceSessionChanged() {
    final sourceKey = SourceSessionNotifier.instance.lastChangedSourceKey;
    if (sourceKey != widget.source.key) return;
    Log.i('Category refresh after source session change', sourceKey);
    unawaited(_load());
  }

  @override
  void dispose() {
    SourceSessionNotifier.instance.removeListener(_onSourceSessionChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool refreshing = false}) async {
    if (refreshing && (_loading || _refreshing)) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = !refreshing;
      _refreshing = refreshing;
      _error = null;
    });
    try {
      final response = await widget.source.loadSourceCategories!();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (response.error) {
          _error = response.errorMessageWithoutNull;
        } else {
          _categories = response.data;
        }
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading && _categories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _categories.isEmpty) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: '${widget.source.name}分类加载失败',
        subtitle: _error,
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (_categories.isEmpty) {
      return EmptyState(
        icon: Icons.category_outlined,
        title: '${widget.source.name}暂无分类',
        subtitle: '下拉或点击刷新重新加载',
        actionLabel: '刷新',
        onAction: () => _load(refreshing: true),
      );
    }

    final bottomPadding =
        60 + MediaQuery.paddingOf(context).bottom + AppSpacing.lg;
    return RefreshIndicator(
      onRefresh: () => _load(refreshing: true),
      child: GridView.builder(
        key: PageStorageKey('category-scroll-${widget.source.key}'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        scrollCacheExtent: ScrollCacheExtent.pixels(
          MediaQuery.sizeOf(context).height * 1.5,
        ),
        padding: EdgeInsets.fromLTRB(8, AppSpacing.md, 8, bottomPadding),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          mainAxisSpacing: 5,
          crossAxisSpacing: 3,
          childAspectRatio: 1 / 1.35,
        ),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          return _CategoryGridItem(
            source: widget.source,
            category: category,
            onTap: () => context.push(
              buildCategoryContentLocation(
                sourceKey: widget.source.key,
                category: category,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryGridItem extends StatelessWidget {
  const _CategoryGridItem({
    required this.source,
    required this.category,
    required this.onTap,
  });

  final ComicSource source;
  final SourceCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = category.cover?.trim();
    final config = cover == null || cover.isEmpty
        ? null
        : source.getThumbnailLoadingConfig?.call(cover);
    final requestUrl = config?['url'] is String
        ? config!['url'] as String
        : cover;
    final headers = _stringHeaders(config?['headers'] ?? config);

    return InkWell(
      key: ValueKey('category-${source.key}-${category.key}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        children: <Widget>[
          AspectRatio(
            aspectRatio: 1,
            child: Card(
              clipBehavior: Clip.hardEdge,
              elevation: 0,
              margin: EdgeInsets.zero,
              child: requestUrl == null || requestUrl.isEmpty
                  ? _CategoryPlaceholder(title: category.title)
                  : CachedNetworkImage(
                      imageUrl: requestUrl,
                      httpHeaders: headers,
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      placeholder: (_, __) =>
                          _CategoryPlaceholder(title: category.title),
                      errorBuilder: (_, __, ___) =>
                          _CategoryPlaceholder(title: category.title),
                    ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            category.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}

class _CategoryPlaceholder extends StatelessWidget {
  const _CategoryPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.semanticColors.surfaceMuted,
    child: Center(
      child: Icon(
        Icons.collections_bookmark_rounded,
        size: 38,
        color: context.colorScheme.primary,
        semanticLabel: '$title 分类图片',
      ),
    ),
  );
}

Map<String, String>? _stringHeaders(Object? value) {
  if (value is! Map) return null;
  final headers = <String, String>{};
  for (final entry in value.entries) {
    if (entry.key is String && entry.value != null) {
      if (entry.key == 'url' ||
          entry.key == 'cacheKey' ||
          entry.key == 'method') {
        continue;
      }
      headers[entry.key as String] = entry.value.toString();
    }
  }
  return headers.isEmpty ? null : headers;
}
