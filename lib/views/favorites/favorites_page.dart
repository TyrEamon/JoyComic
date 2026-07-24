/// 收藏库：合并本地缓存与已登录漫画源的远端收藏。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:joycomic/theme/app_theme_context.dart';
import 'package:go_router/go_router.dart';

import '../../comic_source/comic_source.dart';
import '../../database/favorites_helper.dart';
import '../../foundation/log.dart';
import '../../foundation/source_session_notifier.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../common/utils/source_login_guard.dart';
import '../common/widgets/comic_card.dart';
import '../common/widgets/empty_state.dart';

List<ComicSource> _defaultSourcesProvider() => ComicSource.sources;

/// 收藏页统一条目。一个条目可同时存在于 SQLite 与远端。
class FavoriteLibraryItem {
  const FavoriteLibraryItem({
    required this.sourceKey,
    required this.comicId,
    required this.title,
    required this.coverUrl,
    required this.author,
    this.favoritedAt = 0,
    this.isLocal = false,
    this.isRemote = false,
  });

  final String sourceKey;
  final String comicId;
  final String title;
  final String coverUrl;
  final String author;
  final int favoritedAt;
  final bool isLocal;
  final bool isRemote;

  FavoriteLibraryItem merge(FavoriteLibraryItem newer) {
    return FavoriteLibraryItem(
      sourceKey: sourceKey,
      comicId: comicId,
      title: newer.title.isNotEmpty ? newer.title : title,
      coverUrl: newer.coverUrl.isNotEmpty ? newer.coverUrl : coverUrl,
      author: newer.author.isNotEmpty ? newer.author : author,
      favoritedAt: math.max(favoritedAt, newer.favoritedAt),
      isLocal: isLocal || newer.isLocal,
      isRemote: isRemote || newer.isRemote,
    );
  }
}

/// 按 `(sourceKey, comicId)` 合并，远端非空元数据优先，本地时间用于稳定排序。
List<FavoriteLibraryItem> mergeFavoriteLibraryItems({
  required Iterable<FavoriteLibraryItem> local,
  required Iterable<FavoriteLibraryItem> remote,
}) {
  final merged = <(String, String), FavoriteLibraryItem>{};
  for (final item in <FavoriteLibraryItem>[...local, ...remote]) {
    final key = (item.sourceKey, item.comicId);
    merged[key] = merged[key]?.merge(item) ?? item;
  }
  final result = merged.values.toList();
  result.sort((a, b) {
    final byTime = b.favoritedAt.compareTo(a.favoritedAt);
    if (byTime != 0) return byTime;
    final byTitle = a.title.compareTo(b.title);
    if (byTitle != 0) return byTitle;
    final bySource = a.sourceKey.compareTo(b.sourceKey);
    return bySource != 0 ? bySource : a.comicId.compareTo(b.comicId);
  });
  return result;
}

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({
    super.key,
    this.favoritesHelper,
    this.sourcesProvider = _defaultSourcesProvider,
  });

  final FavoritesHelper? favoritesHelper;
  final List<ComicSource> Function() sourcesProvider;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  late final FavoritesHelper _helper =
      widget.favoritesHelper ?? FavoritesHelper();
  String? _filterSource;
  List<FavoriteLibraryItem> _items = const [];
  Set<String> _failedSources = const {};
  final Set<(String, String)> _busyFavorites = <(String, String)>{};
  bool _loading = true;
  bool _syncingRemote = false;
  int _loadGeneration = 0;
  late int _lastSeenRevision;

  @override
  void initState() {
    super.initState();
    _lastSeenRevision = FavoriteNotifier.instance.revision;
    FavoriteNotifier.instance.addListener(_onFavoriteChanged);
    SourceSessionNotifier.instance.addListener(_onSourceSessionChanged);
    _loadFavorites();
  }

  @override
  void dispose() {
    FavoriteNotifier.instance.removeListener(_onFavoriteChanged);
    SourceSessionNotifier.instance.removeListener(_onSourceSessionChanged);
    super.dispose();
  }

  void _onSourceSessionChanged() {
    final sourceKey = SourceSessionNotifier.instance.lastChangedSourceKey;
    final isRelevant = widget.sourcesProvider().any(
      (source) => source.key == sourceKey && source.favoriteData != null,
    );
    if (!isRelevant) return;
    Log.i('Favorites refresh after source session change', sourceKey);
    unawaited(_loadFavorites());
  }

  void _onFavoriteChanged() {
    final revision = FavoriteNotifier.instance.revision;
    if (revision <= _lastSeenRevision) return;
    _lastSeenRevision = revision;
    if (_syncingRemote) return;
    _loadFavorites();
  }

  List<FavoriteLibraryItem> _localItems() {
    return _helper
        .list()
        .map(
          (record) => FavoriteLibraryItem(
            sourceKey: record.source,
            comicId: record.comic,
            title: record.title,
            coverUrl: record.cover,
            author: record.author,
            favoritedAt: record.favoritedAt,
            isLocal: true,
          ),
        )
        .toList();
  }

  static const int _remotePageSafetyLimit = 100;

  int? _maxPageFrom(Object? value) {
    final parsed = switch (value) {
      int number => number,
      num number => number.toInt(),
      String text => int.tryParse(text),
      _ => null,
    };
    return parsed != null && parsed > 0 ? parsed : null;
  }

  Future<List<FavoriteLibraryItem>> _loadRemoteSource(
    ComicSource source,
    Set<String> failed,
  ) async {
    final items = <FavoriteLibraryItem>[];
    final seenComicIds = <String>{};
    int? maxPage;
    var page = 1;

    while (page <= _remotePageSafetyLimit) {
      try {
        final result = await source.favoriteData!.load(page);
        if (result.error) {
          failed.add(source.key);
          break;
        }

        final comics = result.data;
        var newItems = 0;
        for (final comic in comics) {
          if (!seenComicIds.add(comic.id)) continue;
          newItems++;
          items.add(
            FavoriteLibraryItem(
              sourceKey: source.key,
              comicId: comic.id,
              title: comic.title,
              coverUrl: comic.cover,
              author: comic.subTitle,
              isRemote: true,
            ),
          );
        }

        maxPage ??= _maxPageFrom(result.subData);
        if (maxPage != null) {
          if (page >= maxPage) break;
        } else if (comics.isEmpty || newItems == 0) {
          break;
        }
        page++;
      } catch (error, stackTrace) {
        failed.add(source.key);
        Log.e(
          'Favorite source load failed',
          error: error,
          stackTrace: stackTrace,
        );
        break;
      }
    }

    if (page > _remotePageSafetyLimit) {
      Log.w(
        'Favorite pagination stopped',
        error: '${source.key} exceeded $_remotePageSafetyLimit pages',
      );
    }
    return items;
  }

  Future<void> _loadFavorites() async {
    final generation = ++_loadGeneration;
    final local = _localItems();
    if (mounted) {
      setState(() {
        _items = mergeFavoriteLibraryItems(local: local, remote: const []);
        _loading = true;
      });
    }

    final remote = <FavoriteLibraryItem>[];
    final failed = <String>{};
    final sources = widget.sourcesProvider();
    final batches = await Future.wait(
      sources
          .where((source) => source.isLogin && source.favoriteData != null)
          .map((source) => _loadRemoteSource(source, failed)),
    );
    for (final batch in batches) {
      remote.addAll(batch);
    }

    if (!mounted || generation != _loadGeneration) return;

    // 成功取得的远端收藏写入本地缓存，使下次离线启动仍然可见。
    _syncingRemote = true;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var index = 0; index < remote.length; index++) {
        final item = remote[index];
        final existing = _helper.get(item.sourceKey, item.comicId);
        _helper.upsert(
          FavoriteRecord(
            source: item.sourceKey,
            comic: item.comicId,
            title: item.title.isEmpty ? existing?.title ?? '' : item.title,
            cover: item.coverUrl.isEmpty
                ? existing?.cover ?? ''
                : item.coverUrl,
            author: item.author.isEmpty ? existing?.author ?? '' : item.author,
            favoritedAt: existing?.favoritedAt ?? now - index,
          ),
        );
        if (!FavoriteNotifier.instance.isFavorited(
          item.sourceKey,
          item.comicId,
        )) {
          FavoriteNotifier.instance.addLocal(
            item.sourceKey,
            item.comicId,
            item.title,
            item.coverUrl,
            item.author,
          );
        }
      }
    } finally {
      _syncingRemote = false;
      _lastSeenRevision = FavoriteNotifier.instance.revision;
    }

    final refreshedLocal = _localItems();
    setState(() {
      _items = mergeFavoriteLibraryItems(local: refreshedLocal, remote: remote);
      _failedSources = failed;
      _loading = false;
    });
    Log.i('Favorites loaded', '${_items.length} merged items');
  }

  List<FavoriteLibraryItem> get _visibleItems => _filterSource == null
      ? _items
      : _items.where((item) => item.sourceKey == _filterSource).toList();

  List<String> get _sourceKeys {
    final keys = <String>{
      ...widget.sourcesProvider().map((source) => source.key),
      ..._items.map((item) => item.sourceKey),
    }.toList();
    keys.sort();
    return keys;
  }

  String _sourceName(String key) =>
      widget
          .sourcesProvider()
          .where((source) => source.key == key)
          .firstOrNull
          ?.name ??
      key;

  Future<void> _openDetail(FavoriteLibraryItem item) async {
    final source =
        ComicSource.find(item.sourceKey) ??
        widget
            .sourcesProvider()
            .where((source) => source.key == item.sourceKey)
            .firstOrNull;
    if (source != null && source.requiresLoginForBrowsing && !source.isLogin) {
      final allowed = await ensureSourceLoggedIn(context, item.sourceKey);
      if (!allowed) return;
    }
    if (!mounted) return;
    context.push('/detail/${item.sourceKey}/${item.comicId}');
  }

  Future<void> _removeFavorite(FavoriteLibraryItem item) async {
    final key = (item.sourceKey, item.comicId);
    if (_busyFavorites.contains(key)) return;

    final source = widget
        .sourcesProvider()
        .where((candidate) => candidate.key == item.sourceKey)
        .firstOrNull;
    if (item.isRemote && source != null && !source.isLogin) {
      await ensureSourceLoggedIn(
        context,
        item.sourceKey,
        requireAuthentication: true,
      );
      return;
    }

    if (!mounted) return;
    setState(() => _busyFavorites.add(key));
    final shouldRemoveRemotely =
        source?.isLogin == true &&
        source?.favoriteData?.addOrDelFavorite != null;
    try {
      if (shouldRemoveRemotely) {
        await _helper.toggleFavorite(
          sourceKey: item.sourceKey,
          comicId: item.comicId,
          title: item.title,
          coverUrl: item.coverUrl,
          author: item.author,
        );
      } else {
        _helper.delete(item.sourceKey, item.comicId);
        FavoriteNotifier.instance.removeLocal(item.sourceKey, item.comicId);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('取消收藏失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _busyFavorites.remove(key));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _visibleItems;
    final loggedOutSources = widget
        .sourcesProvider()
        .where((source) => source.favoriteData != null && !source.isLogin)
        .toList();
    final loginSource =
        loggedOutSources.firstWhereOrNull(
          (source) => source.key == _filterSource,
        ) ??
        loggedOutSources.firstOrNull;

    return Scaffold(
      backgroundColor: context.pageBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopBar(
              count: visibleItems.length,
              loading: _loading,
              onRefresh: _loadFavorites,
            ),
            if (_sourceKeys.isNotEmpty)
              _SourceFilterBar(
                sourceKeys: _sourceKeys,
                sourceName: _sourceName,
                current: _filterSource,
                onChanged: (source) => setState(() => _filterSource = source),
              ),
            if (loggedOutSources.isNotEmpty)
              _LoginHint(
                sourceNames: loggedOutSources
                    .map((source) => source.name)
                    .join('、'),
                onLogin: loginSource == null
                    ? null
                    : () => context.push('/login?source=${loginSource.key}'),
              ),
            if (_failedSources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  0,
                ),
                child: Text(
                  '${_failedSources.map(_sourceName).join('、')} 同步失败，已显示本地收藏',
                  style: TextStyle(
                    color: context.tertiaryTextColor,
                    fontSize: 12,
                  ),
                ),
              ),
            Expanded(
              child: _loading && visibleItems.isEmpty
                  ? Center(
                      child: CircularProgressIndicator(
                        color: context.colorScheme.primary,
                        strokeWidth: 2.5,
                      ),
                    )
                  : visibleItems.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _loadFavorites,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          EmptyState(
                            icon: Icons.favorite_border_rounded,
                            title: '还没有收藏',
                            subtitle: '在详情页点收藏，作品会出现在这里',
                          ),
                        ],
                      ),
                    )
                  : _FavoritesGrid(
                      items: visibleItems,
                      onRefresh: _loadFavorites,
                      onOpen: _openDetail,
                      onRemove: _removeFavorite,
                      busyItems: _busyFavorites,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.count,
    required this.loading,
    required this.onRefresh,
  });

  final int count;
  final bool loading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            '收藏',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: context.primaryTextColor,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$count',
            style: TextStyle(fontSize: 14, color: context.tertiaryTextColor),
          ),
          const Spacer(),
          IconButton(
            tooltip: '刷新收藏',
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _SourceFilterBar extends StatelessWidget {
  const _SourceFilterBar({
    required this.sourceKeys,
    required this.sourceName,
    required this.current,
    required this.onChanged,
  });

  final List<String> sourceKeys;
  final String Function(String) sourceName;
  final String? current;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: sourceKeys.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          final key = index == 0 ? null : sourceKeys[index - 1];
          return ChoiceChip(
            label: Text(key == null ? '全部' : sourceName(key)),
            selected: current == key,
            onSelected: (_) => onChanged(key),
          );
        },
      ),
    );
  }
}

class _LoginHint extends StatelessWidget {
  const _LoginHint({required this.sourceNames, required this.onLogin});

  final String sourceNames;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              '$sourceNames 登录后可同步云端收藏；本地收藏仍可直接查看',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          TextButton(onPressed: onLogin, child: const Text('去登录')),
        ],
      ),
    );
  }
}

class _FavoritesGrid extends StatelessWidget {
  const _FavoritesGrid({
    required this.items,
    required this.onRefresh,
    required this.onOpen,
    required this.onRemove,
    required this.busyItems,
  });

  final List<FavoriteLibraryItem> items;
  final Future<void> Function() onRefresh;
  final ValueChanged<FavoriteLibraryItem> onOpen;
  final ValueChanged<FavoriteLibraryItem> onRemove;
  final Set<(String, String)> busyItems;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 3;
        final width =
            (constraints.maxWidth - AppSpacing.md * 2 - AppSpacing.sm * 2) /
            columns;
        return RefreshIndicator(
          color: context.colorScheme.primary,
          onRefresh: onRefresh,
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              92,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.52,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final busy = busyItems.contains((item.sourceKey, item.comicId));
              final source = ComicSource.find(item.sourceKey);
              final headers = source?.getThumbnailLoadingConfig?.call(
                item.coverUrl,
              );
              final status = item.isLocal && item.isRemote
                  ? '本地 + 云端'
                  : item.isRemote
                  ? '云端收藏'
                  : '本地收藏 · 离线可见';
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  ComicCard.poster(
                    title: item.title,
                    coverUrl: item.coverUrl,
                    subtitle: item.author.isEmpty
                        ? status
                        : '${item.author} · $status',
                    width: width,
                    headers: headers,
                    sourceKey: item.sourceKey,
                    onTap: busy ? null : () => onOpen(item),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Material(
                      color: context.semanticColors.imageScrimSoft,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: busy ? '取消收藏中' : '取消收藏',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        color: context.colorScheme.primary,
                        onPressed: busy ? null : () => onRemove(item),
                        icon: busy
                            ? SizedBox.square(
                                key: ValueKey<String>(
                                  'favorite-busy:${item.sourceKey}:${item.comicId}',
                                ),
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: context.colorScheme.primary,
                                ),
                              )
                            : const Icon(Icons.favorite_rounded),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
