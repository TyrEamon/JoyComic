/// Collection analytics aggregation and optional metadata enrichment.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../comic_source/comic_source.dart';
import '../../database/favorites_helper.dart';
import '../../database/read_record_helper.dart';

class RankedStat {
  const RankedStat(this.name, this.count);

  final String name;
  final int count;
}

class CollectionStatsSnapshot {
  const CollectionStatsSnapshot({
    required this.totalFavorites,
    required this.read,
    required this.unread,
    required this.metadataComplete,
    required this.artists,
    required this.tags,
  });

  const CollectionStatsSnapshot.empty()
    : totalFavorites = 0,
      read = 0,
      unread = 0,
      metadataComplete = 0,
      artists = const <RankedStat>[],
      tags = const <RankedStat>[];

  final int totalFavorites;
  final int read;
  final int unread;
  final int metadataComplete;
  final List<RankedStat> artists;
  final List<RankedStat> tags;

  int get artistCount => artists.length;
  int get tagCount => tags.length;
  int get tagOccurrences => tags.fold(0, (sum, item) => sum + item.count);
  double get readRatio => totalFavorites == 0 ? 0 : read / totalFavorites;
  double get metadataRatio => totalFavorites == 0
      ? 1
      : metadataComplete / totalFavorites;

  factory CollectionStatsSnapshot.fromRecords({
    required Iterable<FavoriteRecord> favorites,
    required Iterable<ReadRecord> history,
  }) {
    final favoriteList = favorites.toList(growable: false);
    final readKeys = <(String, String)>{
      for (final record in history) (record.sourceKey, record.comicId),
    };
    final artistCounts = <String, int>{};
    final tagCounts = <String, int>{};
    var read = 0;
    var metadataComplete = 0;

    for (final favorite in favoriteList) {
      if (readKeys.contains((favorite.sourceKey, favorite.comicId))) read++;
      if (favorite.metadataComplete) metadataComplete++;
      for (final artist in _uniqueClean(favorite.effectiveAuthors)) {
        artistCounts.update(artist, (count) => count + 1, ifAbsent: () => 1);
      }
      for (final tag in _uniqueClean(favorite.tags)) {
        tagCounts.update(tag, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    return CollectionStatsSnapshot(
      totalFavorites: favoriteList.length,
      read: read,
      unread: favoriteList.length - read,
      metadataComplete: metadataComplete,
      artists: _rank(artistCounts),
      tags: _rank(tagCounts),
    );
  }
}

List<String> _uniqueClean(Iterable<String> values) => <String>{
  for (final value in values)
    if (value.trim().isNotEmpty && value.trim() != '未知') value.trim(),
}.toList(growable: false);

List<RankedStat> _rank(Map<String, int> counts) {
  final result = <RankedStat>[
    for (final entry in counts.entries) RankedStat(entry.key, entry.value),
  ];
  result.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.name.compareTo(b.name);
  });
  return List<RankedStat>.unmodifiable(result);
}

List<RankedStat> collapseDistribution(
  List<RankedStat> values, {
  int limit = 7,
}) {
  if (values.length <= limit) return values;
  final visible = values.take(limit).toList();
  final otherCount = values
      .skip(limit)
      .fold(0, (sum, value) => sum + value.count);
  return List<RankedStat>.unmodifiable(<RankedStat>[
    ...visible,
    RankedStat('其他', otherCount),
  ]);
}

typedef StatsSourceLookup = ComicSource? Function(String sourceKey);

class CollectionStatsController extends ChangeNotifier {
  CollectionStatsController({
    FavoritesHelper? favoritesHelper,
    ReadRecordHelper? readRecordHelper,
    StatsSourceLookup sourceLookup = ComicSource.find,
  }) : _favoritesHelper = favoritesHelper ?? FavoritesHelper(),
       _readRecordHelper = readRecordHelper ?? ReadRecordHelper(),
       _sourceLookup = sourceLookup;

  final FavoritesHelper _favoritesHelper;
  final ReadRecordHelper _readRecordHelper;
  final StatsSourceLookup _sourceLookup;

  CollectionStatsSnapshot snapshot = const CollectionStatsSnapshot.empty();
  bool loading = true;
  bool enriching = false;
  int enrichmentDone = 0;
  int enrichmentTotal = 0;
  int enrichmentFailed = 0;
  bool _disposed = false;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    _rebuild();
    loading = false;
    notifyListeners();
  }

  bool get canEnrich =>
      !enriching && snapshot.metadataComplete < snapshot.totalFavorites;

  Future<void> enrichMissingMetadata() async {
    if (!canEnrich) return;
    final pending = _favoritesHelper.list().where((record) {
      if (record.metadataComplete) return false;
      final source = _sourceLookup(record.sourceKey);
      return source != null &&
          source.loadComicInfo != null &&
          (!source.requiresLoginForBrowsing || source.isLogin);
    }).toList(growable: false);
    if (pending.isEmpty) return;

    enriching = true;
    enrichmentDone = 0;
    enrichmentFailed = 0;
    enrichmentTotal = pending.length;
    notifyListeners();

    var nextIndex = 0;
    Future<void> worker() async {
      while (!_disposed) {
        final index = nextIndex++;
        if (index >= pending.length) return;
        final record = pending[index];
        try {
          final source = _sourceLookup(record.sourceKey);
          final result = await source!.loadComicInfo!(record.comicId);
          if (result.error) {
            enrichmentFailed++;
          } else {
            _saveMetadata(record, result.data);
          }
        } catch (_) {
          enrichmentFailed++;
        }
        enrichmentDone++;
        if (!_disposed &&
            (enrichmentDone % 5 == 0 || enrichmentDone == enrichmentTotal)) {
          _rebuild();
          notifyListeners();
        }
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < math.min(3, pending.length); i++) worker(),
    ]);
    if (_disposed) return;
    enriching = false;
    _rebuild();
    notifyListeners();
  }

  void _saveMetadata(FavoriteRecord record, ComicInfoData info) {
    _favoritesHelper.upsert(
      FavoriteRecord(
        source: record.source,
        comic: record.comic,
        title: info.title.isEmpty ? record.title : info.title,
        cover: info.cover.isEmpty ? record.cover : info.cover,
        author: info.authors.isEmpty ? record.author : info.authors.join('、'),
        authors: info.authors.isEmpty ? record.effectiveAuthors : info.authors,
        tags: info.labels,
        metadataComplete: true,
        favoritedAt: record.favoritedAt,
      ),
    );
  }

  void _rebuild() {
    snapshot = CollectionStatsSnapshot.fromRecords(
      favorites: _favoritesHelper.list(),
      history: _readRecordHelper.list(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
