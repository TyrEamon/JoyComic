/// 临时搜索页（阶段3 取色实跑验证用）。
///
/// 直接调 `ComicSource.searchPageData.loadPage` 拿 `List<BaseComic>`，
/// 渲染 ComicCard.poster 网格，点击 push 详情页。封面鉴权 headers
/// 由源 `getThumbnailLoadingConfig` 提供。
///
/// 禁漫搜索免登录（token 仅 md5(时间戳+盐)），可直接验证动态取色。
/// 哔咔搜索需登录。本页顶部有源切换。
library temp_search_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../common/widgets/comic_card.dart';

class TempSearchPage extends StatefulWidget {
  const TempSearchPage({super.key, required this.sourceKey});

  final String sourceKey;

  @override
  State<TempSearchPage> createState() => _TempSearchPageState();
}

class _TempSearchPageState extends State<TempSearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<BaseComic> _results = const [];
  bool _loading = false;
  String? _error;

  ComicSource? get _source => ComicSource.find(widget.sourceKey);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    final src = _source;
    if (src?.searchPageData?.loadPage == null) {
      setState(() => _error = '${src?.name} 未支持搜索');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _results = const [];
    });
    final res = await src!.searchPageData!.loadPage!(kw, 1, const []);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.error) {
        _error = res.errorMessage ?? '搜索失败';
      } else {
        _results = res.data;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final src = _source;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${src?.name ?? ""}搜索'),
        backgroundColor: AppColors.background,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _doSearch(),
                    style: const TextStyle(color: AppColors.textHigh),
                    decoration: InputDecoration(
                      hintText: '输入关键词，如：星屑',
                      hintStyle: const TextStyle(color: AppColors.textLow),
                      prefixIcon: const Icon(Icons.search, color: AppColors.textLow),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18, color: AppColors.textLow),
                              onPressed: () {
                                _controller.clear();
                                setState(() => _results = const []);
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _loading ? null : _doSearch,
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandPink, strokeWidth: 2.5),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMedium)),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(
        child: Text('输入关键词后搜索', style: TextStyle(color: AppColors.textLow)),
      );
    }
    // 计算 3 列网格的单元宽度，传给 ComicCard.poster 的固定 width 参数。
    final cellWidth = (MediaQuery.of(context).size.width -
            AppSpacing.md * 2 -
            AppSpacing.sm * 2) /
        3;
    return GridView.builder(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.55,
      ),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final b = _results[i];
        final headers = _source?.getThumbnailLoadingConfig?.call(b.cover);
        return ComicCard.poster(
          title: b.title,
          coverUrl: b.cover,
          subtitle: b.subTitle,
          width: cellWidth,
          headers: headers,
          onTap: () => context.push('/detail/${widget.sourceKey}/${b.id}'),
        );
      },
    );
  }
}
