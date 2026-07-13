/// 影视聚合页。
///
/// 展示影视化作品网格：小说改编、动画化、真人化等标签分类筛选。
/// 顶部 Tab 按影视类型切换：全部 / 动画 / 真人 / 广播剧。
///
/// 功能集成说明：
/// - 用源搜索标签筛选：各 tab 对应关键词搜索两源：
///   全部→空关键词（最新），动画→"动画化"，真人→"真人化"，广播剧→"广播剧"
/// - 禁漫 search(keyword, page, order) + 哔咔 search(keyword, sort, page)
///   并行搜索合并结果。
/// - 若禁漫 videos 端点未来实现（JmNetwork.fetchMovies），可切换为专用端点。
/// - 当前已集成真实搜索。
library video_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../common/widgets/comic_grid.dart';
import '../common/widgets/loading_grid.dart';

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 4, vsync: this);

  /// 各 Tab 缓存的数据，避免切 Tab 重复加载。
  final _data = <int, List<ComicGridItem>>{};
  final _loading = <int, bool>{};

  static const _tabKeywords = ['', '动画化', '真人化', '广播剧'];

  @override
  void initState() {
    super.initState();
    _loadTab(0);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) _loadTab(_tab.index);
    });
  }

  Future<void> _loadTab(int tabIndex) async {
    if (_data[tabIndex] != null) return;
    setState(() => _loading[tabIndex] = true);

    final keyword = _tabKeywords[tabIndex];
    final items = <ComicGridItem>[];

    for (final s in ComicSource.sources) {
      if (s.searchPageData?.loadPage == null) continue;
      final res = await s.searchPageData!.loadPage!(keyword, 1, const []);
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
      _data[tabIndex] = items;
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
        title: const Text('影视'),
        backgroundColor: AppColors.background,
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: AppColors.brandPink,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: AppColors.textHigh,
          unselectedLabelColor: AppColors.textLow,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: '全部'),
            Tab(text: '动画'),
            Tab(text: '真人'),
            Tab(text: '广播剧'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: List.generate(4, (i) {
          if (_loading[i] == true && _data[i] == null) {
            return const Center(
              child: SizedBox(
                width: 300,
                height: 400,
                child: LoadingGrid(crossAxisCount: 3, itemCount: 6),
              ),
            );
          }
          return ComicGrid(
            items: _data[i] ?? const [],
            onItemTap: (item) =>
                context.push('/detail/${item.sourceKey ?? 'jm'}/${item.id}'),
          );
        }),
      ),
    );
  }
}
