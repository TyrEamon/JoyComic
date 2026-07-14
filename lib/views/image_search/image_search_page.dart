/// 以图搜图页。
///
/// 流程：上传图片/拍照 → 显示选择预览 + "搜索中" → 结果网格。
/// 顶部有大图预览区 + 两个入口（相册/相机）。
///
/// 功能集成说明：
/// - 使用 SauceNAO 第三方服务做反向图片搜索。
/// - 拿到 SauceNAO 结果后，通过两源 search 二次匹配定位到禁漫/哔咔作品。
/// - 未匹配的结果展示外部链接。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/log.dart';
import '../../foundation/sauce_nao_search.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../common/widgets/comic_grid.dart';
import '../common/widgets/empty_state.dart';

class ImageSearchPage extends StatefulWidget {
  const ImageSearchPage({super.key});

  @override
  State<ImageSearchPage> createState() => _ImageSearchPageState();
}

class _ImageSearchPageState extends State<ImageSearchPage> {
  File? _picked;
  bool _searching = false;
  List<ComicGridItem> _results = const [];

  Future<void> _pick(bool fromCamera) async {
    final picker = ImagePicker();
    final x = fromCamera
        ? await picker.pickImage(source: ImageSource.camera)
        : await picker.pickImage(source: ImageSource.gallery);
    if (x == null) return;

    setState(() {
      _picked = File(x.path);
      _searching = true;
      _results = const [];
    });

    await _sauceSearch(File(x.path));
  }

  Future<void> _sauceSearch(File image) async {
    try {
      final sauceResults = await SauceNaoSearch.search(image);
      if (!mounted) return;
      Log.i('SauceNAO', '${sauceResults.length} results');

      // 二次匹配：用 SauceNAO 结果标题在两源搜
      final matched = <ComicGridItem>{};
      final title = SauceNaoSearch.bestTitle(sauceResults);
      if (title != null) {
        for (final s in ComicSource.sources) {
          if (s.searchPageData?.loadPage == null) continue;
          final res = await s.searchPageData!.loadPage!(title, 1, const []);
          if (res.error) continue;
          for (final b in res.data) {
            matched.add(
              ComicGridItem(
                id: b.id,
                title: b.title,
                coverUrl: b.cover,
                subtitle: b.subTitle,
                sourceKey: s.key,
              ),
            );
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _results = matched.toList();
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('搜索失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text('以图搜图'),
        backgroundColor: context.pageBackground,
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _PickerArea(picked: _picked, onPick: _pick),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                '相似结果',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.primaryTextColor,
                ),
              ),
            ),
          ),
          if (_searching)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: CircularProgressIndicator(
                    color: context.colorScheme.primary,
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            )
          else if (_results.isEmpty && _picked == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.image_search_outlined,
                title: '上传图片找相似漫画',
                subtitle: '支持相册选取或直接拍摄',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              sliver: SliverToBoxAdapter(
                child: ComicGrid(
                  items: _results,
                  onItemTap: (i) =>
                      context.push('/detail/${i.sourceKey ?? 'jm'}/${i.id}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PickerArea extends StatelessWidget {
  const _PickerArea({required this.picked, required this.onPick});
  final File? picked;
  final void Function(bool fromCamera) onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: AppRadius.brLg,
                border: Border.all(
                  color: context.colorScheme.primary.withValues(alpha: 0.3),
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
              ),
              child: picked == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 48,
                            color: context.tertiaryTextColor,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '选择一张漫画截图',
                            style: TextStyle(color: context.tertiaryTextColor),
                          ),
                        ],
                      ),
                    )
                  : ClipRRect(
                      borderRadius: AppRadius.brLg,
                      child: Image.file(picked!, fit: BoxFit.contain),
                    ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _PickerButton(
                  icon: Icons.photo_outlined,
                  label: '从相册选择',
                  onTap: () => onPick(false),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _PickerButton(
                  icon: Icons.camera_alt_outlined,
                  label: '拍摄',
                  onTap: () => onPick(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: context.elevatedSurfaceColor,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: context.borderColor),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: context.colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.primaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
