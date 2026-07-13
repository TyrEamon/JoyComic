/// 排行榜页。
///
/// 顶部 3 个 Tab：最新 / 热门 / 评分。每个 Tab 下是漫画网格，
/// 顶部一排排序筛选条（按周/月/总）。
///
/// 功能集成说明：
/// - 禁漫：search 接口支持 order 参数（'mr'最新/'mp'最多/'mv'评分），
///   排行榜可用 search('', 1, order) 近似（空关键词返回全站最新）。
/// - 哔咔：RankingData 契约提供排行端点（见 ComicSource.categoryComicsData.rankingData）。
/// - query 参数 tab=latest|hot|rating 决定初始 Tab。
/// - 当前：集成真实数据，禁漫用 search order，时间窗口对禁漫无效。
library ranking_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/log.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../common/widgets/comic_grid.dart';

class RankingPage extends StatefulWidget {
  const RankingPage({super.key, this.initialTab = 0});

  /// 0=最新 1=热门 2=评分
  final int initialTab;

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
  int _range = 1; // 0=日 1=周 2=月 3=总

  /// 各 Tab 各自的数据与加载状态。
  final _data = <int, _TabData>{};
  final _loading = <int, bool>{};

  @override
  void initState() {
    super.initState();
    _loadTab(_tab.index);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) {
        _loadTab(_tab.index);
      }
    });
  }

  /// 每个 tab 的 order 参数。
  String get _order {
    return switch (_tab.index) {
      0 => 'mr', // 最新
      1 => 'mp', // 最多（热门）
      2 => 'mv', // 评分
      _ => 'mr',
    };
  }

  Future<void> _loadTab(int tabIndex) async {
    if (_data[tabIndex] != null) return; // 已加载
    setState(() => _loading[tabIndex] = true);

    final items = <ComicGridItem>[];
    for (final s in ComicSource.sources) {
      if (s.searchPageData?.loadPage == null) continue;
      final res = await s.searchPageData!.loadPage!('', 1, [_order]);
      if (res.error) continue;
      items.addAll(res.data.map((b) => ComicGridItem(
            id: b.id,
            title: b.title,
            coverUrl: b.cover,
            subtitle: b.subTitle,
            sourceKey: s.key,
          )));
    }

    if (!mounted) return;
    setState(() {
      _data[tabIndex] = _TabData(items: items);
      _loading[tabIndex] = false;
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('排行榜'),
        backgroundColor: AppColors.background,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.brandPink,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: AppColors.textHigh,
          unselectedLabelColor: AppColors.textLow,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: '最新'),
            Tab(text: '热门'),
            Tab(text: '评分'),
          ],
        ),
      ),
      body: Column(
        children: [
          _RangeBar(
            index: _range,
            onChanged: (i) => setState(() => _range = i),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: List.generate(3, (i) {
                if (_loading[i] == true && _data[i] == null) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.brandPink,
                      strokeWidth: 2.5,
                    ),
                  );
                }
                return _RankList(
                  key: ValueKey(i),
                  items: _data[i]?.items ?? const [],
                  onItemTap: (item) =>
                      context.push('/detail/${item.sourceKey ?? 'jm'}/${item.id}'),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabData {
  const _TabData({required this.items});
  final List<ComicGridItem> items;
}

class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  static const _labels = ['日榜', '周榜', '月榜', '总榜'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: _RangeChip(
                label: _labels[i],
                active: i == index,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(colors: [AppColors.brandPink, AppColors.brandViolet])
              : null,
          color: active ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: active ? null : Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.textMedium,
          ),
        ),
      ),
    );
  }
}

class _RankList extends StatelessWidget {
  const _RankList({super.key, required this.items, required this.onItemTap});
  final List<ComicGridItem> items;
  final void Function(ComicGridItem) onItemTap;

  @override
  Widget build(BuildContext context) {
    return ComicGrid(
      items: items,
      onItemTap: onItemTap,
    );
  }
}
