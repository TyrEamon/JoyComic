import 'dart:async';

import 'reader_v2_session.dart';

enum ReaderV2Priority {
  visible(0),
  preload(1);

  const ReaderV2Priority(this.rank);
  final int rank;
}

final class ReaderV2Scheduler {
  ReaderV2Scheduler({required this.session, this.maxConcurrent = 3})
    : assert(maxConcurrent > 0) {
    session.addCancelListener(_onSessionCancelled);
  }

  final ReaderV2Session session;
  final int maxConcurrent;
  final List<_ReaderV2Job> _queue = <_ReaderV2Job>[];
  final Map<String, Future<Object?>> _shared = <String, Future<Object?>>{};
  int _activeCount = 0;
  int _sequence = 0;
  bool _disposed = false;
  Completer<void>? _idleCompleter;

  int get activeCount => _activeCount;
  int get queuedCount => _queue.length;
  Future<void> get idle => _activeCount == 0 && _queue.isEmpty
      ? Future<void>.value()
      : (_idleCompleter ??= Completer<void>()).future;

  Future<T> schedule<T>({
    required String key,
    required int page,
    required ReaderV2Priority priority,
    required Future<T> Function() task,
  }) {
    if (_disposed) {
      return Future<T>.error(
        ReaderV2Cancelled(session.traceId, 'scheduler disposed'),
      );
    }
    try {
      session.throwIfCancelled();
    } catch (error, stackTrace) {
      return Future<T>.error(error, stackTrace);
    }

    final existing = _shared[key];
    if (existing != null) {
      session.record('dedupe', page: page, detail: key);
      return existing.then((value) => value as T);
    }

    final completer = Completer<Object?>();
    final job = _ReaderV2Job(
      key: key,
      page: page,
      priority: priority,
      sequence: _sequence++,
      task: () async => task(),
      completer: completer,
    );
    _shared[key] = completer.future;
    _queue.add(job);
    _queue.sort(_compareJobs);
    _idleCompleter ??= Completer<void>();
    session.record(
      'queued',
      page: page,
      detail:
          'priority=${priority.name} active=$_activeCount queued=${_queue.length}',
    );
    _pump();
    return completer.future.then((value) => value as T);
  }

  void _pump() {
    if (_disposed || session.isCancelled) {
      _completeIdleIfNeeded();
      return;
    }
    while (_activeCount < maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _activeCount += 1;
      unawaited(_run(job));
    }
  }

  Future<void> _run(_ReaderV2Job job) async {
    session.record(
      'start',
      page: job.page,
      detail: 'active=$_activeCount queued=${_queue.length}',
    );
    try {
      session.throwIfCancelled();
      final result = await job.task();
      session.throwIfCancelled();
      if (!job.completer.isCompleted) {
        job.completer.complete(result);
        session.record('complete', page: job.page);
      }
    } catch (error, stackTrace) {
      if (!job.completer.isCompleted) {
        job.completer.completeError(error, stackTrace);
      }
      session.record('error', page: job.page, detail: '$error');
    } finally {
      if (identical(_shared[job.key], job.completer.future)) {
        _shared.remove(job.key);
      }
      _activeCount -= 1;
      _pump();
      _completeIdleIfNeeded();
    }
  }

  void _onSessionCancelled(ReaderV2Cancelled error) {
    for (final job in _queue) {
      if (!job.completer.isCompleted) {
        job.completer.completeError(error);
      }
      if (identical(_shared[job.key], job.completer.future)) {
        _shared.remove(job.key);
      }
    }
    _queue.clear();
    _completeIdleIfNeeded();
  }

  void _completeIdleIfNeeded() {
    if (_activeCount != 0 || _queue.isNotEmpty) return;
    final completer = _idleCompleter;
    _idleCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!session.isCancelled) session.cancel('scheduler disposed');
    session.removeCancelListener(_onSessionCancelled);
    _completeIdleIfNeeded();
  }

  static int _compareJobs(_ReaderV2Job a, _ReaderV2Job b) {
    final priority = a.priority.rank.compareTo(b.priority.rank);
    return priority != 0 ? priority : a.sequence.compareTo(b.sequence);
  }
}

final class _ReaderV2Job {
  const _ReaderV2Job({
    required this.key,
    required this.page,
    required this.priority,
    required this.sequence,
    required this.task,
    required this.completer,
  });

  final String key;
  final int page;
  final ReaderV2Priority priority;
  final int sequence;
  final Future<Object?> Function() task;
  final Completer<Object?> completer;
}
