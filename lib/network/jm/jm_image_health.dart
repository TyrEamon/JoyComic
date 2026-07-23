/// Process-local JM image-host health and request coalescing.
library;

enum ImageFailure { timeout, network, invalidResponse, transform }

class ImageHostHealth {
  DateTime? lastSuccessAt;
  DateTime? coolUntil;
  int consecutiveFailures = 0;
  ImageFailure? lastFailure;
}

final class JmImageHealth {
  JmImageHealth({
    DateTime Function()? clock,
    this.baseCooldown = const Duration(seconds: 10),
  }) : _clock = clock ?? DateTime.now;

  static const _maxCooldown = Duration(seconds: 60);

  final DateTime Function() _clock;
  final Duration baseCooldown;
  final Map<String, ImageHostHealth> _hosts = <String, ImageHostHealth>{};
  final Map<String, Future<dynamic>> _inflight = <String, Future<dynamic>>{};

  ImageHostHealth _host(String host) =>
      _hosts.putIfAbsent(_normalize(host), ImageHostHealth.new);

  String _normalize(String host) => host
      .replaceAll(RegExp(r'^https?://'), '')
      .split('/')
      .first
      .trim()
      .toLowerCase();

  void recordSuccess(String host) {
    final state = _host(host);
    state.lastSuccessAt = _clock();
    state.coolUntil = null;
    state.consecutiveFailures = 0;
    state.lastFailure = null;
  }

  void recordFailure(String host, ImageFailure failure) {
    final state = _host(host);
    state.consecutiveFailures += 1;
    state.lastFailure = failure;
    final multiplier = 1 << (state.consecutiveFailures - 1).clamp(0, 16);
    var cooldown = baseCooldown * multiplier;
    if (cooldown > _maxCooldown) cooldown = _maxCooldown;
    state.coolUntil = _clock().add(cooldown);
  }

  bool isCoolingDown(String host) {
    final state = _hosts[_normalize(host)];
    return state?.coolUntil?.isAfter(_clock()) ?? false;
  }

  List<String> order(Iterable<String> hosts) {
    final indexed = [
      for (var index = 0; index < hosts.length; index++)
        (host: hosts.elementAt(index), index: index),
    ];
    final now = _clock();
    int tier(String host) {
      final state = _hosts[_normalize(host)];
      if (state == null) return 1;
      if (state.coolUntil?.isAfter(now) ?? false) return 2;
      return state.lastSuccessAt == null ? 1 : 0;
    }

    indexed.sort((a, b) {
      final aTier = tier(a.host);
      final bTier = tier(b.host);
      if (aTier != bTier) return aTier.compareTo(bTier);
      if (aTier == 0) {
        final aAt = _hosts[_normalize(a.host)]!.lastSuccessAt!;
        final bAt = _hosts[_normalize(b.host)]!.lastSuccessAt!;
        final byTime = bAt.compareTo(aAt);
        if (byTime != 0) return byTime;
      }
      return a.index.compareTo(b.index);
    });
    return [for (final item in indexed) item.host];
  }

  List<String> orderUrls(Iterable<String> urls) {
    final values = urls.toList(growable: false);
    final ordered = order([
      for (final url in values) Uri.tryParse(url)?.host ?? url,
    ]);
    final byHost = <String, List<String>>{};
    for (final url in values) {
      final host = (Uri.tryParse(url)?.host ?? url).toLowerCase();
      byHost.putIfAbsent(host, () => <String>[]).add(url);
    }
    final result = <String>[];
    for (final host in ordered) {
      final key = host.toLowerCase();
      final bucket = byHost[key];
      if (bucket == null) continue;
      result.addAll(bucket);
      byHost.remove(key);
    }
    for (final bucket in byHost.values) {
      result.addAll(bucket);
    }
    return result;
  }

  Future<T> singleFlight<T>(String key, Future<T> Function() operation) {
    final current = _inflight[key];
    if (current != null) return current.then((value) => value as T);
    final future = () async {
      try {
        return await operation();
      } finally {
        _inflight.remove(key);
      }
    }();
    _inflight[key] = future;
    return future;
  }
}

final jmImageHealth = JmImageHealth();
