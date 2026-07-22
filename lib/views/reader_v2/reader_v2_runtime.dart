import 'package:flutter/foundation.dart';

import '../../foundation/log.dart';
import '../../foundation/reader_config.dart';
import '../reader/providers/reader_provider.dart';
import '../reader/utils/reader_image_provider.dart'
    show ReaderImageBytesTransformer;
import 'core/reader_v2_scheduler.dart';
import 'core/reader_v2_session.dart';
import 'data/reader_v2_page.dart';
import 'image/reader_v2_image_provider.dart';

final class ReaderV2Runtime extends ChangeNotifier {
  factory ReaderV2Runtime({ReaderV2PageLoader? pageLoader}) {
    final session = ReaderV2Session();
    return ReaderV2Runtime._(pageLoader ?? ReaderV2PageLoader(), session);
  }

  ReaderV2Runtime._(this._pageLoader, this._session)
    : _scheduler = ReaderV2Scheduler(session: _session);

  final ReaderV2PageLoader _pageLoader;
  ReaderV2Session _session;
  ReaderV2Scheduler _scheduler;
  String? _sourceTrace;
  int _pageCount = 0;

  ReaderV2Session get session => _session;
  ReaderV2Scheduler get scheduler => _scheduler;
  ReaderV2BytesLoader get bytesLoader => _pageLoader.load;

  void sync(ReaderProvider reader) {
    final trace = reader.traceId;
    final count = reader.images.length;
    if (trace == null || trace.isEmpty) return;
    if (_sourceTrace == trace && _pageCount == count) return;
    _scheduler.dispose();
    _session = ReaderV2Session(traceId: 'v2-$trace', eventSink: _writeEvent);
    _scheduler = ReaderV2Scheduler(session: _session, maxConcurrent: 3);
    _sourceTrace = trace;
    _pageCount = count;
  }

  bool shouldLoad(int index, int anchor) {
    final window = ReaderConf.instance.preloadImageCount.clamp(2, 8);
    return (index - anchor).abs() <= window;
  }

  ReaderV2Priority priorityFor(int index, int anchor) =>
      index == anchor ? ReaderV2Priority.visible : ReaderV2Priority.preload;

  ReaderV2Page pageFrom({
    required int index,
    required String url,
    required String cacheKey,
    Map<String, String>? headers,
    List<String> fallbackUrls = const <String>[],
    ReaderImageBytesTransformer? bytesTransformer,
  }) => ReaderV2Page(
    index: index,
    url: url,
    cacheKey: cacheKey,
    headers: headers,
    fallbackUrls: fallbackUrls,
    bytesTransformer: bytesTransformer,
  );

  static void _writeEvent(ReaderV2Event event) {
    final page = event.page == null ? '-' : event.page.toString();
    Log.i(
      'ReaderV2 ${event.stage}',
      'trace=${event.traceId} page=$page ${event.detail}'.trim(),
    );
  }

  @override
  void dispose() {
    _scheduler.dispose();
    super.dispose();
  }
}
