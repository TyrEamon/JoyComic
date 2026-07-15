/// 搜索页（全局搜索）。
///
/// 结构：
/// 1. 搜索框 + 源切换（默认全部源，可切到单源）
/// 2. 未搜索：历史记录 + 热门搜索词
/// 3. 搜索中：loading
/// 4. 有结果：结果网格
///
/// 功能集成说明：
/// - 搜索调 `source.searchPageData.loadPage(keyword, page, options)`。
/// - 多源并行搜索：遍历 `ComicSource.sources`，每个有 searchPageData 的源
///   并行请求，结果合并去重，按源 chip 标识（sourceKey）。
/// - 热门词：两源 loadHotTags API。
/// - 搜索历史已持久化到 sqlite3。
/// - 当前已集成真实数据。
library;

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../database/search_history_helper.dart';
import '../../foundation/log.dart';
import '../../theme/app_spacing.dart';
import '../common/utils/source_login_guard.dart';
import '../common/widgets/comic_grid.dart';
import '../common/widgets/empty_state.dart';
import '../common/widgets/loading_grid.dart';

String? directJmComicId(String input) {
  return RegExp(
    r'^\s*(?:jm)?\s*(\d+)\s*$',
    caseSensitive: false,
  ).firstMatch(input)?.group(1);
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.sourceKey = 'all', this.initialQuery});

  /// 'all' = 全部源并行；否则单源搜索。
  final String sourceKey;
  final String? initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  List<ComicGridItem> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  /// 当前页码（分页用）。
  int _page = 1;

  /// 是否还有更多结果。
  bool _hasMore = true;

  /// 源筛选：null=全部, 'jm'=禁漫, 'picacg'=哔咔。
  String? _filterSource;

  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialQuery?.trim() ?? '';
    _controller = TextEditingController(text: initialQuery);
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    if (initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _doSearch(initialQuery);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ============================ 搜索逻辑 ============================

  /// 选择要搜索的源。
  List<ComicSource> get _targetSources {
    final filter = _filterSource ?? widget.sourceKey;
    if (filter == 'all') {
      return ComicSource.sources
          .where((s) => s.searchPageData?.loadPage != null)
          .toList();
    }
    final s = ComicSource.find(filter);
    return s != null ? [s] : [];
  }

  bool get _allowsDirectJm {
    final filter = _filterSource ?? widget.sourceKey;
    return filter == 'jm' ||
        (filter == 'all' && ComicSource.find('jm') != null);
  }

  Future<void> _doSearch(String kw) async {
    final normalized = kw.trim();
    if (normalized.isEmpty) return;
    final directId = directJmComicId(normalized);
    if (directId != null && _allowsDirectJm) {
      context.push('/detail/jm/$directId');
      return;
    }
    setState(() {
      _loading = true;
      _searched = true;
      _error = null;
      _results = const [];
      _page = 1;
      _hasMore = true;
    });
    final sources = _targetSources;
    if (sources.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '没有可用的搜索源';
      });
      return;
    }

    // 保存搜索历史
    _saveHistory(normalized);

    final futures = sources.map((s) async {
      final res = await s.searchPageData!.loadPage!(normalized, 1, const []);
      if (res.error) return <ComicGridItem>[];
      final items = res.data.map(
        (b) => ComicGridItem(
          id: b.id,
          title: b.title,
          coverUrl: b.cover,
          subtitle: b.subTitle,
          sourceKey: s.key,
        ),
      );
      return items.toList();
    });

    final results = await Future.wait(futures);
    if (!mounted) return;
    final merged = results.expand((e) => e).toList();
    Log.i('Search', 'keyword="$normalized" → ${merged.length} results');
    setState(() {
      _loading = false;
      _results = merged;
      _hasMore = merged.length >= 20;
      if (merged.isEmpty) _hasMore = false;
    });
  }

  /// 加载更多（分页）。
  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final nextPage = _page + 1;
    final sources = _targetSources;
    final futures = sources.map((s) async {
      final res = await s.searchPageData!.loadPage!(
        _controller.text,
        nextPage,
        const [],
      );
      if (res.error) return <ComicGridItem>[];
      return res.data.map(
        (b) => ComicGridItem(
          id: b.id,
          title: b.title,
          coverUrl: b.cover,
          subtitle: b.subTitle,
          sourceKey: s.key,
        ),
      );
    });
    final results = await Future.wait(futures);
    if (!mounted) return;
    final more = results.expand((e) => e).toList();
    setState(() {
      _loading = false;
      _page = nextPage;
      _results = [..._results, ...more];
      _hasMore = more.length >= 20;
    });
  }

  // ============================ 搜索历史 ============================

  final _historyHelper = SearchHistoryHelper();

  void _saveHistory(String kw) {
    _historyHelper.addKeyword(kw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        backgroundColor: context.pageBackground,
        titleSpacing: 0,
        title: _SearchField(
          controller: _controller,
          focus: _focus,
          onSubmitted: _doSearch,
          onClear: () {
            _controller.clear();
            setState(() {
              _searched = false;
              _results = const [];
            });
          },
        ),
        actions: [
          TextButton(
            onPressed: () => _doSearch(_controller.text),
            child: Text(
              '搜索',
              style: TextStyle(color: context.colorScheme.primary),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && !_searched) {
      return const Center(
        child: SizedBox(
          width: 300,
          height: 400,
          child: LoadingGrid(crossAxisCount: 3, itemCount: 6),
        ),
      );
    }
    if (_searched) {
      if (_error != null) {
        return EmptyState(icon: Icons.error_outline_rounded, title: _error!);
      }
      if (_results.isEmpty) {
        return const EmptyState(
          icon: Icons.search_off_rounded,
          title: '未找到相关漫画',
          subtitle: '换个关键词试试',
        );
      }
      return Column(
        children: [
          _SourceFilterBar(
            current: _filterSource,
            onChanged: (s) {
              setState(() => _filterSource = s);
            },
          ),
          Expanded(
            child: ComicGrid(
              items: _filterSource == null
                  ? _results
                  : _results
                        .where((i) => i.sourceKey == _filterSource)
                        .toList(),
              onLoadMore: _hasMore ? _loadMore : null,
              hasMore: _hasMore,
              onItemTap: (i) => _onItemTap(i),
            ),
          ),
        ],
      );
    }
    return _SearchHome(
      onHistoryTap: (kw) {
        _controller.text = kw;
        _doSearch(kw);
      },
      onHotTap: (kw) {
        _controller.text = kw;
        _doSearch(kw);
      },
    );
  }

  void _onItemTap(ComicGridItem item) async {
    final sk = item.sourceKey ?? 'jm';
    final loggedIn = await ensureSourceLoggedIn(context, sk);
    if (!loggedIn && sk == 'picacg') return;
    if (!mounted) return;
    context.push('/detail/$sk/${item.id}');
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: TextField(
        controller: controller,
        focusNode: focus,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        autofocus: true,
        style: TextStyle(color: context.primaryTextColor, fontSize: 15),
        decoration: InputDecoration(
          hintText: '搜索漫画、作者、标签',
          hintStyle: TextStyle(color: context.tertiaryTextColor),
          prefixIcon: Icon(
            Icons.search,
            color: context.tertiaryTextColor,
            size: 20,
          ),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: context.tertiaryTextColor,
                  ),
                  onPressed: onClear,
                ),
          filled: true,
          fillColor: context.surfaceColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _SearchHome extends StatefulWidget {
  const _SearchHome({required this.onHistoryTap, required this.onHotTap});
  final ValueChanged<String> onHistoryTap;
  final ValueChanged<String> onHotTap;

  @override
  State<_SearchHome> createState() => _SearchHomeState();
}

class _SearchHomeState extends State<_SearchHome> {
  List<String> _hotTags = const [];
  bool _loadingTags = true;
  List<String> _history = const [];
  final _historyHelper = SearchHistoryHelper();

  @override
  void initState() {
    super.initState();
    try {
      _history = _historyHelper.getHistory();
    } catch (_) {
      _history = const <String>[];
    }
    _loadHotTags();
  }

  Future<void> _loadHotTags() async {
    final tags = <String>{};
    for (final s in ComicSource.sources) {
      if (s.searchPageData?.loadHotTags == null) continue;
      final res = await s.searchPageData!.loadHotTags!();
      if (!res.error && res.dataOrNull != null) {
        tags.addAll(res.data);
      }
    }
    if (tags.isEmpty) {
      tags.addAll(['校园恋爱', '奇幻冒险', '同人', '完结佳作', '新番改编', '百合']);
    }
    if (!mounted) return;
    setState(() {
      _hotTags = tags.toList();
      _loadingTags = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Row(
          children: [
            Text(
              '搜索历史',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.primaryTextColor,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: () {
                _historyHelper.clear();
                setState(() => _history = const []);
              },
              child: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: context.tertiaryTextColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _history
              .map((k) => _Chip(label: k, onTap: () => widget.onHistoryTap(k)))
              .toList(),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          '热门搜索',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.primaryTextColor,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (_loadingTags)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(
              color: context.colorScheme.primary,
              strokeWidth: 2,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _hotTags
                .map(
                  (k) => _Chip(
                    label: k,
                    hot: true,
                    onTap: () => widget.onHotTap(k),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap, this.hot = false});
  final String label;
  final VoidCallback onTap;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hot) ...[
              Icon(
                Icons.local_fire_department_rounded,
                size: 13,
                color: context.colorScheme.tertiary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: hot ? context.warningColor : context.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 源筛选栏：全部 / 禁漫 / 哔咔 Tab 切换。
class _SourceFilterBar extends StatelessWidget {
  const _SourceFilterBar({required this.current, required this.onChanged});
  final String? current;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _FilterChip(
            label: '全部',
            active: current == null,
            onTap: () => onChanged(null),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: '禁漫',
            active: current == 'jm',
            onTap: () => onChanged('jm'),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: '哔咔',
            active: current == 'picacg',
            onTap: () => onChanged('picacg'),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? context.colorScheme.primaryContainer
              : context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active
                ? context.colorScheme.onPrimaryContainer
                : context.secondaryTextColor,
          ),
        ),
      ),
    );
  }
}
