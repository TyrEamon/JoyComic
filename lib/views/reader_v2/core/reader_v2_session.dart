import 'dart:collection';

final class ReaderV2Cancelled implements Exception {
  const ReaderV2Cancelled(this.traceId, this.reason);

  final String traceId;
  final String reason;

  @override
  String toString() => 'ReaderV2Cancelled(trace=$traceId, reason=$reason)';
}

final class ReaderV2Event {
  const ReaderV2Event({
    required this.traceId,
    required this.stage,
    required this.at,
    this.page,
    this.detail = '',
  });

  final String traceId;
  final String stage;
  final DateTime at;
  final int? page;
  final String detail;
}

typedef ReaderV2CancelListener = void Function(ReaderV2Cancelled error);

final class ReaderV2Session {
  ReaderV2Session({String? traceId}) : traceId = traceId ?? _newTraceId() {
    record('start');
  }

  final String traceId;
  final List<ReaderV2Event> _events = <ReaderV2Event>[];
  final Set<ReaderV2CancelListener> _cancelListeners =
      <ReaderV2CancelListener>{};
  ReaderV2Cancelled? _cancellation;

  bool get isCancelled => _cancellation != null;
  ReaderV2Cancelled? get cancellation => _cancellation;
  UnmodifiableListView<ReaderV2Event> get events =>
      UnmodifiableListView<ReaderV2Event>(_events);

  void record(String stage, {int? page, String detail = ''}) {
    _events.add(
      ReaderV2Event(
        traceId: traceId,
        stage: stage,
        at: DateTime.now(),
        page: page,
        detail: detail,
      ),
    );
  }

  void addCancelListener(ReaderV2CancelListener listener) {
    final cancellation = _cancellation;
    if (cancellation != null) {
      listener(cancellation);
      return;
    }
    _cancelListeners.add(listener);
  }

  void removeCancelListener(ReaderV2CancelListener listener) {
    _cancelListeners.remove(listener);
  }

  void cancel(String reason) {
    if (_cancellation != null) return;
    final error = ReaderV2Cancelled(traceId, reason);
    _cancellation = error;
    record('cancel', detail: reason);
    for (final listener in List<ReaderV2CancelListener>.of(_cancelListeners)) {
      listener(error);
    }
    _cancelListeners.clear();
  }

  void throwIfCancelled() {
    final cancellation = _cancellation;
    if (cancellation != null) throw cancellation;
  }

  static String _newTraceId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
