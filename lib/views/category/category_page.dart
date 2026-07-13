/// 分类页。
///
/// 结构：
/// 1. 搜索框（点击 push 搜索页）
/// 2. 横滑一级分类 tab：连载/完结/同人/单本 等
/// 3. 分类标签网格（2列卡片，每卡含小封面拼贴 + 分类名 + 数量）
/// 4. 排行入口横滑
/// 5. 随机分类区
///
/// 功能集成说明：
/// - 分类数据来自 `ComicSource.categoryData`（FixedCategoryPart /
///   RandomCategoryPart）。
/// - 点分类卡 push 分类结果页（传 category key），调
///   `source.categoryComicsData.load(category, param, options, page)`。
/// - 当前已集成，遍历所有源的 categoryData 收集分类标签。
library category_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../common/widgets/section_header.dart';

class CategoryPage extends StatelessWidget {
  const CategoryPage({super.key});

  /// 从所有源收集分类标签。
  static List<_Cat> _collectCategories() {
    final seen = <String>{};
    final cats = <_Cat>[];
    for (final s in ComicSource.sources) {
      if (s.categoryData == null) continue;
      final data = s.categoryData!;
      for (final part in data.categories) {
        if (part is FixedCategoryPart) {
          for (final c in part.categories) {
            if (seen.add(c)) {
              cats.add(_Cat(
                key: c,
                name: c,
                count: '',
                cover: 'https://picsum.photos/seed/jc-cat-${c.hashCode}/360/240',
                sourceKey: s.key,
              ));
            }
          }
        }
      }
    }
    return cats;
  }

  @override
  Widget build(BuildContext context) {
    final cats = _collectCategories();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Header()),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
            SliverToBoxAdapter(
              child: SectionHeader(title: '分类标签', actionLabel: '全部', onAction: () {}),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 1.4,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _CategoryCard(item: cats[i], onTap: () => context.push('/detail/${cats[i].sourceKey}/${cats[i].key}')),
                  childCount: cats.length,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
          ],
        ),
      ),
    );
  }
}

class _Cat {
  const _Cat({
    required this.key,
    required this.name,
    required this.count,
    required this.cover,
    required this.sourceKey,
  });
  final String key;
  final String name;
  final String count;
  final String cover;
  final String sourceKey;
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Text('分类',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textHigh)),
          const Spacer(),
          InkWell(
            onTap: () => context.push('/search/all'),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, size: 18, color: AppColors.textLow),
                  SizedBox(width: AppSpacing.xs),
                  Text('搜索漫画',
                      style: TextStyle(color: AppColors.textLow, fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.item, required this.onTap});
  final _Cat item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: AppRadius.brMd,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                AppColors.background.withValues(alpha: 0.55),
                BlendMode.darken,
              ),
              child: Image.network(item.cover,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) => Container(color: AppColors.surface)),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 10,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
