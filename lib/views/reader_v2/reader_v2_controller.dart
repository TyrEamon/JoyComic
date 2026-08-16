import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../foundation/log.dart';
import '../reader/providers/reader_provider.dart' hide ReaderImage;
import 'core/reader_v2_scheduler.dart';
import 'core/reader_v2_session.dart';
import 'data/reader_v2_page.dart';
import 'image/reader_v2_image_provider.dart';

final class ReaderV2Controller extends ChangeNotifier {
  ReaderV2Controller({
    required ReaderProvider reader,
    int preloadCount = 4,
    ReaderV2BytesLoader? bytesLoader,
  }) : _reader = reader,
       preloadCount = preloadCount.clamp(2, 8),
       _bytesLoader = bytesLoader ?? ReaderV2PageLoader().load {
    _session = ReaderV2Session(traceId: 'v2-pending');
    _scheduler = ReaderV2Scheduler(session: _session, maxConcurrent: 3);
    _reader.addListener(_syncFromReader);
    _syncFromReader();
  }

  final ReaderProvider _reader;
  final int preloadCount;
  final ReaderV2BytesLoader _bytesLoader;
  late ReaderV2Session _session;
  late ReaderV2Scheduler _scheduler;
  List<ReaderV2Page> _pages = const <ReaderV2Page>[];
  final Map<String, Size> _imageSizes = <String, Size>{};
  String? _sourceTrace;
  bool _disposed = false;

  ReaderV2Session get session => _session;
  ReaderV2Scheduler get scheduler => _scheduler;
  ReaderV2BytesLoader get bytesLoader => _bytesLoader;
  UnmodifiableListView<ReaderV2Page> get pages =>
      UnmodifiableListView<ReaderV2Page>(_pages);
  int get currentPage {
    final reportedPage = _reader.pageNo;
    final rawPage = _reader.readMode.isDoublePage
        ? reportedPage * 2
        : reportedPage;
    return rawPage.clamp(0, _pages.isEmpty ? 0 : _pages.length - 1);
  }

  bool shouldLoad(int index) =>
      index >= 0 &&
      index < _pages.length &&
      (index - currentPage).abs() <= preloadCount;

  ReaderV2Priority priorityFor(int index) => index == currentPage
      ? ReaderV2Priority.visible
      : ReaderV2Priority.preload;

  void preloadNextBytes(int anchor) {
    if (_disposed) return;
    final index = anchor + 1;
    if (index < 0 || index >= _pages.length) return;
    final page = _pages[index];
    final session = _session;
    final scheduler = _scheduler;
    unawaited(_preloadBytes(page, session, scheduler));
  }

  Future<void> _preloadBytes(
    ReaderV2Page page,
    ReaderV2Session session,
    ReaderV2Scheduler scheduler,
  ) async {
    try {
      await scheduler.schedule(
        key: page.cacheKey,
        page: page.index,
        priority: ReaderV2Priority.preload,
        task: () => _bytesLoader(page, session),
      );
    } on ReaderV2Cancelled {
      // Chapter and route changes cancel their old preloads by design.
    } catch (error) {
      session.record('preload-error', page: page.index, detail: '$error');
    }
  }

  void setCurrentPage(int index) {
    if (_pages.isEmpty) return;
    _reader.onPageNoChanged(index.clamp(0, _pages.length - 1));
  }

  void recordImageSize(ReaderV2Page page, Size size) {
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0 ||
        _imageSizes[page.cacheKey] == size) {
      return;
    }
    _imageSizes[page.cacheKey] = size;
    notifyListeners();
  }

  double pageHeight(int index, double width) {
    if (index < 0 || index >= _pages.length || width <= 0) {
      return width * 1355 / 960;
    }
    final size = _imageSizes[_pages[index].cacheKey];
    if (size == null) return width * 1355 / 960;
    return width * size.height / size.width;
  }

  void _syncFromReader() {
    if (_disposed) return;
    final trace = _reader.traceId;
    final images = _reader.images;
    if (trace == null || trace.isEmpty || images.isEmpty) return;
    final samePages =
        _sourceTrace == trace &&
        _pages.length == images.length &&
        List<bool>.generate(
          images.length,
          (index) => _pages[index].cacheKey == images[index].cacheKey,
        ).every((same) => same);
    if (samePages) {
      notifyListeners();
      return;
    }

    final nextPages = <ReaderV2Page>[
      for (var index = 0; index < images.length; index++)
        ReaderV2Page(
          index: index,
          url: images[index].url,
          cacheKey: images[index].cacheKey,
          headers: images[index].headers,
          fallbackUrls: images[index].fallbackUrls,
          bytesTransformer: images[index].bytesTransformer,
        ),
    ];
    _scheduler.dispose();
    _session = ReaderV2Session(traceId: 'v2-$trace', eventSink: _writeEvent);
    _scheduler = ReaderV2Scheduler(session: _session, maxConcurrent: 3);
    _pages = List<ReaderV2Page>.unmodifiable(nextPages);
    _sourceTrace = trace;
    _imageSizes.clear();
    notifyListeners();
  }

  static void _writeEvent(ReaderV2Event event) {
    final page = event.page == null ? '-' : event.page.toString();
    Log.i(
      'ReaderV2 ${event.stage}',
      'trace=${event.traceId} page=$page ${event.detail}'.trim(),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _reader.removeListener(_syncFromReader);
    _scheduler.dispose();
    super.dispose();
  }
}
