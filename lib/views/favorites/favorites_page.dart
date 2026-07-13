/// 收藏页（= 底部 Tab 3）。
///
/// 结构：
/// 1. 顶栏：标题"收藏" + 搜索图标
/// 2. 源筛选：全部 / 禁漫 / 哔咔
/// 3. 文件夹横滑（多文件夹源）
/// 4. 排序条：最近 / 收藏时间 / 标题
/// 5. 漫画网格 [ComicGrid]
///
/// 功能集成说明：
/// - 数据来自 `source.favoriteData.load(page, folder)`。
/// - 遍历已登录源，按源筛选展示。
/// - 未登录源灰显，点击弹出登录引导。
library favorites_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../database/favorites_helper.dart';
import '../../foundation/log.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../common/utils/source_login_guard.dart';
import '../common/widgets/comic_grid.dart';
import '../common/widgets/empty_state.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  /// 源筛选：null=全部, 'jm'=禁漫, 'picacg'=哔咔。
  String? _filterSource;

  /// 各源的收藏数据。
  Map<String, List<ComicGridItem>> _favData = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    // 监听收藏状态变化通知
    FavoriteNotifier.instance.addListener(_onFavoriteChanged);
  }

  @override
  void dispose() {
    FavoriteNotifier.instance.removeListener(_onFavoriteChanged);
    super.dispose();
  }

  void _onFavoriteChanged() {
    if (FavoriteNotifier.instance.isDirty) {
      FavoriteNotifier.instance.consumeDirty();
      _loadFavorites();
    }
  }

  Future<void> _loadFavorites() async {
    setState(() => _loading = true);
    final data = <String, List<ComicGridItem>>{};

    for (final s in ComicSource.sources) {
      if (!s.isLogin || s.favoriteData == null) continue;
      final res = await s.favoriteData!.load(1);
      if (res.error) continue;
      data[s.key] = res.data.map((b) => ComicGridItem(
            id: b.id,
            title: b.title,
            coverUrl: b.cover,
            subtitle: b.subTitle,
            sourceKey: s.key,
          )).toList();
    }
    Log.i('Favorites loaded',
        '${data.length} sources, total: ${data.values.expand((e) => e).length} items');
    if (!mounted) return;
    setState(() {
      _favData = data;
      _loading = false;
    });
  }

  List<ComicGridItem> get _items {
    if (_filterSource == null) {
      return _favData.values.expand((e) => e).toList();
    }
    return _favData[_filterSource] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopBar(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _SourceFilterBar(
                current: _filterSource,
                onChanged: (s) => setState(() => _filterSource = s),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.brandPink,
                        strokeWidth: 2.5,
                      ),
                    )
                  : items.isEmpty
                      ? const EmptyState(
                          icon: Icons.favorite_border_rounded,
                          title: '还没有收藏',
                          subtitle: '在详情页点收藏，作品会出现在这里',
                          actionLabel: '去发现',
                        )
                      : ComicGrid(
                          items: items,
                          onItemTap: (i) async {
                            final sk = i.sourceKey ?? 'jm';
                            final ok = await ensureSourceLoggedIn(context, sk);
                            if (!ok && sk == 'picacg') return;
                            if (!context.mounted) return;
                            context.push('/detail/$sk/${i.id}');
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Text('收藏',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textHigh)),
          const SizedBox(width: AppSpacing.xs),
          const Text('128',
              style: TextStyle(fontSize: 14, color: AppColors.textLow)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.textHigh),
            onPressed: () => context.push('/search/all'),
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined,
                color: AppColors.textHigh),
            onPressed: () => _showNewFolderDialog(context),
          ),
        ],
      ),
    );
  }

  void _showNewFolderDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('新建文件夹',
            style: TextStyle(color: AppColors.textHigh)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textHigh),
          decoration: InputDecoration(
            hintText: '文件夹名称',
            hintStyle: const TextStyle(color: AppColors.textLow),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: const Color(0xFF221A2B),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: AppColors.textLow)),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              // 给第一个支持多文件夹的源创建
              for (final s in ComicSource.sources) {
                if (s.favoriteData?.addFolder != null && s.isLogin) {
                  await s.favoriteData!.addFolder!(name);
                  break;
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandPink),
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}


/// 源筛选栏：全部 / 禁漫 / 哔咔。
class _SourceFilterBar extends StatelessWidget {
  const _SourceFilterBar({required this.current, required this.onChanged});
  final String? current;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FChip(label: '全部', active: current == null, onTap: () => onChanged(null)),
        const SizedBox(width: 8),
        _FChip(label: '禁漫', active: current == 'jm', onTap: () => onChanged('jm')),
        const SizedBox(width: 8),
        _FChip(label: '哔咔', active: current == 'picacg', onTap: () => onChanged('picacg')),
      ],
    );
  }
}

class _FChip extends StatelessWidget {
  const _FChip({required this.label, required this.active, required this.onTap});
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
          gradient: active
              ? const LinearGradient(colors: [Color(0xFFFF7BA9), Color(0xFFB967FF)])
              : null,
          color: active ? null : const Color(0xFF1B1622),
          borderRadius: BorderRadius.circular(16),
          border: active ? null : Border.all(color: const Color(0xFF2F2740)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFF8A8298),
          ),
        ),
      ),
    );
  }
}
