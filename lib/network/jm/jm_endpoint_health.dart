/// Process-local JM API host health, cooldown, and single-flight helpers.
library;

/// Transport / infrastructure failure classes that cool a host.
///
/// Auth (401) and decoded business errors are **not** represented here and must
/// not cool a host — use [JmEndpointHealth.recordBusinessResponse] instead.
enum FailureClass { timeout, network, empty, serverError }

/// Mutable per-host counters used only for ordering and cooldown.
class HostHealth {
  DateTime? lastSuccessAt;
  DateTime? coolUntil;
  int consecutiveFailures = 0;
  FailureClass? lastFailure;
}

/// Runtime API host health tracker.
///
/// - Successes prioritize a host in [order].
/// - Timeout / network / empty / 5xx failures apply exponential cooldown
///   (base → 2× → … capped at 60s).
/// - 401 and business-level errors never cool a host.
/// - [singleFlight] shares one in-flight [Future] per key and removes it in
///   `finally` so a later call runs a fresh operation.
class JmEndpointHealth {
  JmEndpointHealth({
    DateTime Function()? clock,
    this.baseCooldown = const Duration(seconds: 10),
  }) : _clock = clock ?? DateTime.now;

  static const Duration _maxCooldown = Duration(seconds: 60);

  final DateTime Function() _clock;
  final Duration baseCooldown;
  final Map<String, HostHealth> _hosts = <String, HostHealth>{};
  final Map<String, Future<dynamic>> _inflight = <String, Future<dynamic>>{};

  HostHealth _host(String host) =>
      _hosts.putIfAbsent(_normalize(host), HostHealth.new);

  String _normalize(String host) => host
      .replaceAll(RegExp(r'^https?://'), '')
      .split('/')
      .first
      .trim()
      .toLowerCase();

  void recordSuccess(String host) {
    final h = _host(host);
    h.lastSuccessAt = _clock();
    h.consecutiveFailures = 0;
    h.coolUntil = null;
    h.lastFailure = null;
  }

  void recordFailure(String host, FailureClass failure) {
    final h = _host(host);
    h.consecutiveFailures += 1;
    h.lastFailure = failure;
    final multiplier = 1 << (h.consecutiveFailures - 1).clamp(0, 16);
    var cooldown = baseCooldown * multiplier;
    if (cooldown > _maxCooldown) cooldown = _maxCooldown;
    h.coolUntil = _clock().add(cooldown);
  }

  /// Records an HTTP-level or decoded business outcome that must **not** cool.
  ///
  /// [statusCode] 401 and [isBusinessError] true leave the host out of cooldown.
  /// A non-error 2xx may optionally be treated as success when [isBusinessError]
  /// is false and [statusCode] is in 200–299 (used by integration probes).
  void recordBusinessResponse(
    String host, {
    int? statusCode,
    bool isBusinessError = false,
  }) {
    if (statusCode == 401 || isBusinessError) {
      // Explicitly do not cool; also do not reset success ordering.
      return;
    }
    if (statusCode != null && statusCode >= 500) {
      recordFailure(host, FailureClass.serverError);
      return;
    }
    if (statusCode != null && statusCode >= 200 && statusCode < 300) {
      recordSuccess(host);
    }
  }

  bool isCoolingDown(String host) {
    final h = _hosts[_normalize(host)];
    if (h == null || h.coolUntil == null) return false;
    return h.coolUntil!.isAfter(_clock());
  }

  /// True when [host] has a recorded success and is not currently cooling.
  bool hasKnownSuccess(String host) {
    final h = _hosts[_normalize(host)];
    if (h == null || h.lastSuccessAt == null) return false;
    return !isCoolingDown(host);
  }

  bool hasAnyKnownSuccess(Iterable<String> hosts) => hosts.any(hasKnownSuccess);

  /// Returns [candidates] ordered: not-cooling successes first (most recent
  /// success first), then never-failed, then cooling hosts last (soonest cool
  /// expiry first). Relative order among equal tiers preserves candidate order.
  List<String> order(List<String> candidates) {
    final now = _clock();
    final indexed = <({String host, int index})>[
      for (var i = 0; i < candidates.length; i++)
        (host: candidates[i], index: i),
    ];

    int tier(String host) {
      final h = _hosts[_normalize(host)];
      if (h == null) return 1; // never seen
      final cooling = h.coolUntil != null && h.coolUntil!.isAfter(now);
      if (cooling) return 2;
      if (h.lastSuccessAt != null) return 0;
      return 1;
    }

    indexed.sort((a, b) {
      final ta = tier(a.host);
      final tb = tier(b.host);
      if (ta != tb) return ta.compareTo(tb);
      if (ta == 0) {
        final ha = _hosts[_normalize(a.host)]!;
        final hb = _hosts[_normalize(b.host)]!;
        final cmp = hb.lastSuccessAt!.compareTo(ha.lastSuccessAt!);
        if (cmp != 0) return cmp;
      }
      if (ta == 2) {
        final ha = _hosts[_normalize(a.host)]!;
        final hb = _hosts[_normalize(b.host)]!;
        final cmp = ha.coolUntil!.compareTo(hb.coolUntil!);
        if (cmp != 0) return cmp;
      }
      return a.index.compareTo(b.index);
    });

    return [for (final item in indexed) item.host];
  }

  Future<T> singleFlight<T>(String key, Future<T> Function() operation) {
    final existing = _inflight[key];
    if (existing != null) {
      return existing.then((value) => value as T);
    }

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
