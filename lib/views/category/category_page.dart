/// Dual-source category browser with independent source state.
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool refreshing = false}) async {
    if (refreshing && (_loading || _refreshing)) return;
    setState(() {
      _loading = !refreshing;
      _refreshing = refreshing;
      _error = null;
    });
    try {
      final response = await widget.source.loadSourceCategories!();
      if (!mounted) return;
      setState(() {
        if (response.error) {
          _error = response.errorMessageWithoutNull;
        } else {
          _categories = response.data;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
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

    final byParent = <String, List<SourceCategory>>{};
    final keys = {for (final category in _categories) category.key};
    final roots = <SourceCategory>[];
    for (final category in _categories) {
      final parentKey = category.parentKey;
      if (parentKey == null || !keys.contains(parentKey)) {
        roots.add(category);
      } else {
        byParent.putIfAbsent(parentKey, () => []).add(category);
      }
    }

    return RefreshIndicator(
      onRefresh: () => _load(refreshing: true),
      child: ListView.builder(
        key: PageStorageKey('category-scroll-${widget.source.key}'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        itemCount: roots.length + (_error == null ? 0 : 1),
        itemBuilder: (context, index) {
          if (index == roots.length) {
            return Center(
              child: TextButton.icon(
                onPressed: () => _load(refreshing: true),
                icon: const Icon(Icons.refresh_rounded),
                label: Text('刷新失败：$_error，点击重试'),
              ),
            );
          }
          final parent = roots[index];
          final children = byParent[parent.key] ?? const <SourceCategory>[];
          return _CategoryGroup(
            sourceKey: widget.source.key,
            parent: parent,
            children: children,
          );
        },
      ),
    );
  }
}

class _CategoryGroup extends StatelessWidget {
  const _CategoryGroup({
    required this.sourceKey,
    required this.parent,
    required this.children,
  });

  final String sourceKey;
  final SourceCategory parent;
  final List<SourceCategory> children;

  @override
  Widget build(BuildContext context) {
    void open(SourceCategory category) => context.push(
      buildCategoryContentLocation(sourceKey: sourceKey, category: category),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              parent.title,
              style: TextStyle(
                color: context.primaryTextColor,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => open(parent),
          ),
          if (children.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final child in children)
                    ActionChip(
                      key: ValueKey('category-$sourceKey-${child.key}'),
                      label: Text(child.title),
                      avatar: const Icon(
                        Icons.subdirectory_arrow_right,
                        size: 16,
                      ),
                      onPressed: () => open(child),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
