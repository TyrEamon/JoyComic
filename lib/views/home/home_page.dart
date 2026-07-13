/// 首页。
///
/// 结构（自顶向下）：
/// 1. 顶部栏：Logo 文字 + 搜索图标（push /search）
/// 2. 工具栏 [HomeToolBar]：最新/热门排行/影视/以图搜图/收藏库/下载
/// 3. 编辑推荐 [FeaturedCarousel]：大幅封面横滑
/// 4. 最近更新网格 [ComicGrid]
/// 5. 编辑精选网格
///
/// 功能集成说明：
/// - 推荐/精选数据来自各源的推荐内容（弹窗搜索热门、推荐端点）。
///   当前：搜索两源热门作品（禁漫 search('',1,'mp') + 哔咔 search('','ua',1)）
///   作为编辑推荐轮播的兜底数据。
/// - 最近更新已集成：遍历各 source.searchPageData.loadPage('', 1, []) 取最新。
/// - 当前：已集成真实数据，首页所有区块均走真实源接口。'
library home_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/log.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../common/widgets/comic_grid.dart';
import '../common/widgets/section_header.dart';
import 'widgets/featured_carousel.dart';
import 'widgets/home_tool_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<ComicGridItem>? _recentItems;
  bool _loadingRecent = true;
  List<FeaturedItem> _featuredItems = const [];
  bool _loadingFeatured = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _loadFeatured();
  }

  Future<void> _loadFeatured() async {
    final items = <FeaturedItem>[];
    // 禁漫：搜索热门（mp=最多）
    for (final s in ComicSource.sources) {
      if (s.searchPageData?.loadPage == null) continue;
      final order = s.key == 'jm' ? 'mp' : 'ua';
      final res = await s.searchPageData!.loadPage!('', 1, [order]);
      if (res.error) continue;
      final sourceItems = res.data.take(8).map((b) => FeaturedItem(
            id: b.id,
            title: b.title,
            coverUrl: b.cover,
            tag: b.subTitle,
            sourceKey: s.key,
          ));
      items.addAll(sourceItems);
    }
    Log.i('Home featured', '${items.length} items');
    if (!mounted) return;
    setState(() {
      _featuredItems = items;
      _loadingFeatured = false;
    });
  }

  Future<void> _loadRecent() async {
    final items = <ComicGridItem>[];
    for (final s in ComicSource.sources) {
      if (s.searchPageData?.loadPage == null) continue;
      final res = await s.searchPageData!.loadPage!('', 1, const []);
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
      _recentItems = items;
      _loadingRecent = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _TopBar()),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
            // 工具栏：6 个功能入口横滑。
            SliverToBoxAdapter(
              child: HomeToolBar(entries: HomeToolBar.defaults(context)),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
            // 编辑推荐横滑。
            SliverToBoxAdapter(
              child: SectionHeader(
                title: '编辑推荐',
                actionLabel: '更多',
                onAction: () {}, // → push 推荐列表页
              ),
            ),
            SliverToBoxAdapter(
              child: _loadingFeatured
                  ? const SizedBox(
                      height: 200,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.brandPink,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : FeaturedCarousel(
                      items: _featuredItems,
                      onTap: (item) => context.push(
                          '/detail/${item.sourceKey ?? 'jm'}/${item.id}'),
                    ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
            // 最近更新网格。
            SliverToBoxAdapter(
              child: SectionHeader(
                title: '最近更新',
                actionLabel: '最新',
                onAction: () => context.push('/ranking?tab=latest'),
              ),
            ),
            SliverToBoxAdapter(
              child: _loadingRecent
                  ? const SizedBox(
                      height: 200,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.brandPink,
                          strokeWidth: 2.5,
                        ),
                      ),
                    )
                  : ComicGrid(
                      items: _recentItems ?? const [],
                      onItemTap: (i) => context.push(
                          '/detail/${i.sourceKey ?? 'jm'}/${i.id}'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页顶栏：Logo + 搜索入口。
class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [AppColors.brandPink, AppColors.brandViolet],
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: const Text(
              'JoyComic',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          InkWell(
            onTap: () => context.push('/search/all'),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.search, color: AppColors.textHigh, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
