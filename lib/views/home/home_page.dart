/// Home page populated from each source's real discovery sections.
library home_page;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../foundation/log.dart';
import '../../network/res.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../common/source_content_models.dart';
import '../common/widgets/comic_grid.dart';
import '../common/widgets/empty_state.dart';
import '../common/widgets/section_header.dart';
import 'widgets/featured_carousel.dart';
import 'widgets/home_tool_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<HomeSourceResult> _sourceResults = const [];
  final Set<String> _retryingSources = <String>{};
  bool _loading = true;

  HomeContent get _content => mergeHomeSections(_sourceResults);

  @override
  void initState() {
    super.initState();
    _loadHome();
  }

  Future<HomeSourceResult> _loadSource(ComicSource source) async {
    final loader = source.loadHomeSections;
    if (loader == null) {
      return HomeSourceResult(
        sourceKey: source.key,
        sourceName: source.name,
        result: const Res.error('该源暂不支持首页内容'),
      );
    }
    try {
      return HomeSourceResult(
        sourceKey: source.key,
        sourceName: source.name,
        result: await loader(),
      );
    } catch (error, stackTrace) {
      Log.e(
        'Failed to load ${source.key} home sections',
        error: error,
        stackTrace: stackTrace,
      );
      return HomeSourceResult(
        sourceKey: source.key,
        sourceName: source.name,
        result: Res.error(error.toString()),
      );
    }
  }

  Future<void> _loadHome() async {
    final sources = ComicSource.sources
        .where((source) => source.loadHomeSections != null)
        .toList(growable: false);
    if (mounted) setState(() => _loading = true);
    final results = await Future.wait(sources.map(_loadSource));
    if (!mounted) return;
    setState(() {
      _sourceResults = results;
      _loading = false;
    });
  }

  Future<void> _retrySource(String sourceKey) async {
    if (!_retryingSources.add(sourceKey)) return;
    if (mounted) setState(() {});
    final source = ComicSource.find(sourceKey);
    if (source == null) {
      _retryingSources.remove(sourceKey);
      if (mounted) setState(() {});
      return;
    }
    final replacement = await _loadSource(source);
    if (!mounted) return;
    setState(() {
      final index = _sourceResults.indexWhere(
        (result) => result.sourceKey == sourceKey,
      );
      if (index < 0) {
        _sourceResults = [..._sourceResults, replacement];
      } else {
        final updated = [..._sourceResults];
        updated[index] = replacement;
        _sourceResults = updated;
      }
      _retryingSources.remove(sourceKey);
    });
  }

  HomeContentSection? _featuredSection(List<HomeContentSection> sections) {
    for (final section in sections) {
      final identity = '${section.key} ${section.title}'.toLowerCase();
      if (identity.contains('推荐') || identity.contains('recommend')) {
        return section;
      }
    }
    return sections.isEmpty ? null : sections.first;
  }

  Map<String, dynamic>? _coverHeaders(ComicGridItem item) {
    final cover = item.coverUrl;
    if (cover == null || cover.isEmpty || item.sourceKey == null) return null;
    return ComicSource.find(item.sourceKey!)
        ?.getThumbnailLoadingConfig
        ?.call(cover);
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;
    final featured = _featuredSection(content.sections);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.brandPink,
          onRefresh: _loadHome,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _TopBar()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.sm)),
              SliverToBoxAdapter(
                child: HomeToolBar(entries: HomeToolBar.defaults(context)),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
              if (_loading && content.sections.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: AppColors.brandPink,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              else ...[
                if (content.errors.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _SourceErrors(
                      errors: content.errors,
                      retryingSources: _retryingSources,
                      onRetry: _retrySource,
                    ),
                  ),
                if (featured != null) ...[
                  SliverToBoxAdapter(child: _sectionHeader(featured)),
                  SliverToBoxAdapter(
                    child: FeaturedCarousel(
                      items: [
                        for (final comic in featured.comics)
                          FeaturedItem(
                            id: comic.id,
                            title: comic.title,
                            coverUrl: comic.cover,
                            tag: comic.subTitle,
                            badge: featured.sourceName,
                            sourceKey: featured.sourceKey,
                            headers: ComicSource.find(featured.sourceKey)
                                ?.getThumbnailLoadingConfig
                                ?.call(comic.cover),
                          ),
                      ],
                      onTap: (item) => context.push(
                        _detailLocation(item.sourceKey, item.id),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.lg),
                  ),
                ],
                for (final section in content.sections)
                  if (!identical(section, featured)) ...[
                    SliverToBoxAdapter(child: _sectionHeader(section)),
                    SliverToBoxAdapter(
                      child: ComicGrid(
                        items: [
                          for (final comic in section.comics)
                            ComicGridItem(
                              id: comic.id,
                              title: comic.title,
                              coverUrl: comic.cover,
                              subtitle: comic.subTitle,
                              sourceKey: section.sourceKey,
                            ),
                        ],
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        coverHeadersBuilder: _coverHeaders,
                        onItemTap: (item) => context.push(
                          _detailLocation(item.sourceKey, item.id),
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.lg),
                    ),
                  ],
                if (content.sections.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      title: content.errors.isEmpty ? '暂无首页内容' : '内容加载失败',
                      subtitle: content.errors.isEmpty
                          ? '下拉刷新，稍后再看看'
                          : '请检查网络后重试',
                      actionLabel: '重试',
                      onAction: _loadHome,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(HomeContentSection section) {
    return SectionHeader(
      title: '${section.sourceName} · ${section.title}',
      actionLabel: section.moreQuery == null ? null : '更多',
      onAction: section.moreQuery == null
          ? null
          : () => context.push(_contentLocation(section)),
    );
  }

  String _contentLocation(HomeContentSection section) {
    final query = section.moreQuery!;
    return Uri(
      pathSegments: ['', 'content', section.sourceKey],
      queryParameters: {
        'kind': 'home',
        'category': query.categoryKey,
        if (query.param != null) 'param': query.param!,
        if (query.sort != null) 'sort': query.sort!,
      },
    ).toString();
  }

  String _detailLocation(String? sourceKey, String comicId) => Uri(
        pathSegments: ['', 'detail', sourceKey ?? 'jm', comicId],
      ).toString();
}

class _SourceErrors extends StatelessWidget {
  const _SourceErrors({
    required this.errors,
    required this.retryingSources,
    required this.onRetry,
  });

  final List<HomeSourceError> errors;
  final Set<String> retryingSources;
  final ValueChanged<String> onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        children: [
          for (final error in errors)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.xs),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      '${error.sourceName}：${error.message}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMedium,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: retryingSources.contains(error.sourceKey)
                        ? null
                        : () => onRetry(error.sourceKey),
                    child: Text(
                      retryingSources.contains(error.sourceKey) ? '重试中' : '重试',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
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
              child: const Icon(
                Icons.search,
                color: AppColors.textHigh,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
