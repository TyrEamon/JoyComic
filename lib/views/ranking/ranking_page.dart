/// Aggregated source-aware rankings.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:joycomic/theme/app_theme_context.dart';

import '../../comic_source/comic_source.dart';
import '../../network/base_comic.dart';
import '../../theme/app_spacing.dart';
import '../common/source_content_models.dart';
import '../common/widgets/comic_grid.dart';
import '../common/widgets/source_login_prompt.dart';

class RankingPage extends StatefulWidget {
  const RankingPage({super.key, this.initialTab = 0, this.sources});

  final int initialTab;
  final List<ComicSource>? sources;

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage>
    with SingleTickerProviderStateMixin {
  static const _tabKeys = <String>['latest', 'hot', 'rating'];

  late final TabController _tab = TabController(
    length: _tabKeys.length,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, _tabKeys.length - 1),
  );
  final _data = <int, _TabData>{};
  final _loading = <int, bool>{};
  final _sourceGenerations = <String, int>{};
  final _sourceLoading = <String, bool>{};

  List<ComicSource> get _sources => widget.sources ?? ComicSource.sources;

  @override
  void initState() {
    super.initState();
    _loadTab(_tab.index);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) _loadTab(_tab.index);
    });
  }

  Future<void> _loadTab(int tabIndex, {bool force = false}) async {
    if (!force && _data[tabIndex] != null) return;
    if (_loading[tabIndex] == true) return;
    if (mounted) setState(() => _loading[tabIndex] = true);
    final tabKey = _tabKeys[tabIndex];
    final results = await Future.wait(<Future<_SourceLoad>>[
      for (final source in _sources) _loadSource(source, tabKey),
    ]);
    if (!mounted) return;

    final items = <ComicGridItem>[];
    final failures = <_SourceFailure>[];
    final loginRequirements = <HomeLoginRequirement>[];
    for (final result in results) {
      if (result.loginRequired) {
        loginRequirements.add(
          HomeLoginRequirement(
            sourceKey: result.source.key,
            sourceName: result.source.name,
          ),
        );
      } else if (result.error != null) {
        failures.add(
          _SourceFailure(source: result.source, message: result.error!),
        );
      } else {
        items.addAll(
          result.comics.map(
            (comic) => ComicGridItem(
              id: comic.id,
              title: comic.title,
              coverUrl: comic.cover,
              subtitle: comic.subTitle,
              sourceKey: result.source.key,
            ),
          ),
        );
      }
    }
    setState(() {
      _data[tabIndex] = _TabData(
        items: items,
        failures: failures,
        loginRequirements: loginRequirements,
      );
      _loading[tabIndex] = false;
    });
  }

  Future<void> _retrySource(int tabIndex, ComicSource source) async {
    final requestKey = '$tabIndex:${source.key}';
    final generation = (_sourceGenerations[requestKey] ?? 0) + 1;
    _sourceGenerations[requestKey] = generation;
    if (mounted) setState(() => _sourceLoading[requestKey] = true);
    final result = await _loadSource(source, _tabKeys[tabIndex]);
    if (!mounted || _sourceGenerations[requestKey] != generation) return;
    final current = _data[tabIndex] ?? const _TabData();
    final items = current.items
        .where((item) => item.sourceKey != source.key)
        .toList();
    final failures = current.failures
        .where((failure) => failure.source.key != source.key)
        .toList();
    final loginRequirements = current.loginRequirements
        .where((requirement) => requirement.sourceKey != source.key)
        .toList();
    if (result.loginRequired) {
      loginRequirements.add(
        HomeLoginRequirement(sourceKey: source.key, sourceName: source.name),
      );
    } else if (result.error != null) {
      failures.add(_SourceFailure(source: source, message: result.error!));
    } else {
      items.addAll(
        result.comics.map(
          (comic) => ComicGridItem(
            id: comic.id,
            title: comic.title,
            coverUrl: comic.cover,
            subtitle: comic.subTitle,
            sourceKey: source.key,
          ),
        ),
      );
    }
    setState(() {
      _sourceLoading[requestKey] = false;
      _data[tabIndex] = _TabData(
        items: items,
        failures: failures,
        loginRequirements: loginRequirements,
      );
    });
  }

  Future<_SourceLoad> _loadSource(ComicSource source, String tabKey) async {
    final ranking = source.categoryComicsData?.rankingData;
    if (ranking == null) return _SourceLoad(source: source);
    if (source.key == 'picacg' &&
        (source.data['token']?.toString().isEmpty ?? true)) {
      return _SourceLoad(source: source, loginRequired: true);
    }
    final option = ranking.options[tabKey];
    if (option == null) {
      return _SourceLoad(source: source, error: '不支持当前排行');
    }
    try {
      final result = await ranking.load(option, 1);
      if (result.error) {
        final message = result.errorMessageWithoutNull;
        if (source.key == 'picacg' &&
            ((source.data['token']?.toString().isEmpty ?? true) ||
                message.contains('登录失效') ||
                message.contains('未登录'))) {
          return _SourceLoad(source: source, loginRequired: true);
        }
        return _SourceLoad(source: source, error: message);
      }
      return _SourceLoad(source: source, comics: result.data);
    } catch (error) {
      return _SourceLoad(source: source, error: error.toString());
    }
  }

  ComicSource _sourceByKey(String key) =>
      _sources.firstWhere((source) => source.key == key);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pageBackground,
      appBar: AppBar(
        title: const Text('排行榜'),
        backgroundColor: context.pageBackground,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: context.colorScheme.primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: context.primaryTextColor,
          unselectedLabelColor: context.tertiaryTextColor,
          tabs: const <Tab>[
            Tab(text: '最新'),
            Tab(text: '热门'),
            Tab(text: '评分'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: List<Widget>.generate(_tabKeys.length, _buildTab),
      ),
    );
  }

  Widget _buildTab(int index) {
    if (_loading[index] == true && _data[index] == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = _data[index] ?? const _TabData();
    return Column(
      children: <Widget>[
        for (final requirement in data.loginRequirements)
          SourceLoginPrompt(
            requirement: requirement,
            contentLabel: '排行榜内容',
            onLoggedIn: () =>
                _retrySource(index, _sourceByKey(requirement.sourceKey)),
          ),
        for (final failure in data.failures)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: ListTile(
              title: Text('${failure.source.name}加载失败'),
              subtitle: Text(failure.message),
              trailing: TextButton(
                key: Key('ranking-retry-${failure.source.key}'),
                onPressed:
                    _sourceLoading['$index:${failure.source.key}'] == true
                    ? null
                    : () => _retrySource(index, failure.source),
                child: const Text('重试'),
              ),
            ),
          ),
        Expanded(
          child: data.items.isEmpty
              ? const Center(child: Text('暂无排行内容'))
              : ComicGrid(
                  items: data.items,
                  onItemTap: (item) => context.push(
                    '/detail/${item.sourceKey ?? 'jm'}/${item.id}',
                  ),
                ),
        ),
      ],
    );
  }
}

class _TabData {
  const _TabData({
    this.items = const <ComicGridItem>[],
    this.failures = const <_SourceFailure>[],
    this.loginRequirements = const <HomeLoginRequirement>[],
  });

  final List<ComicGridItem> items;
  final List<_SourceFailure> failures;
  final List<HomeLoginRequirement> loginRequirements;
}

class _SourceFailure {
  const _SourceFailure({required this.source, required this.message});
  final ComicSource source;
  final String message;
}

class _SourceLoad {
  const _SourceLoad({
    required this.source,
    this.comics = const <BaseComic>[],
    this.error,
    this.loginRequired = false,
  });

  final ComicSource source;
  final List<BaseComic> comics;
  final String? error;
  final bool loginRequired;
}
