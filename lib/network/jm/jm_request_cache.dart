/// Bounded in-memory TTL/LRU cache for public JM GET responses.
library;

import '../res.dart';

/// Process-local cache for public, idempotent GET [Res] snapshots.
///
/// - Capacity: 64 entries (LRU eviction on insert).
/// - TTL: each [put] carries its own duration; expired entries are dropped on
///   [get].
/// - Never stores error [Res] values.
class JmRequestCache {
  JmRequestCache({DateTime Function()? clock, this.maxEntries = 64})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final int maxEntries;

  // Dart map literals preserve insertion order; cache hits remove/reinsert for
  // LRU. Values are (expiresAt, snapshot).
  final Map<String, ({DateTime expiresAt, Res<dynamic> value})> _entries =
      <String, ({DateTime expiresAt, Res<dynamic> value})>{};

  Res<dynamic>? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (!entry.expiresAt.isAfter(_clock())) {
      return null;
    }
    _entries[key] = entry;
    return entry.value;
  }

  /// Stores [value] when it is a non-error [Res]. Errors are ignored.
  void put(String key, Res<dynamic> value, Duration ttl) {
    if (value.error) return;
    if (ttl <= Duration.zero) return;
    _entries.remove(key);
    final snapshot = Res<dynamic>(
      _freezeJson(value.dataOrNull),
      subData: _freezeJson(value.subData),
    );
    _entries[key] = (expiresAt: _clock().add(ttl), value: snapshot);
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void remove(String key) => _entries.remove(key);

  void clear() => _entries.clear();

  static dynamic _freezeJson(dynamic value) {
    if (value is Map) {
      return Map<dynamic, dynamic>.unmodifiable({
        for (final entry in value.entries) entry.key: _freezeJson(entry.value),
      });
    }
    if (value is Iterable) {
      return List<dynamic>.unmodifiable(value.map(_freezeJson));
    }
    return value;
  }
}
