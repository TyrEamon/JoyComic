/// 阅读器全链路分阶段诊断。
///
/// 阶段顺序：
/// S0 章节开始 → S1 URL 就绪 → S2 success → S3 列表 build → S4 tile build
/// → S5 Provider.load → S6 下载开始 → S7 下载完成 → S9 重组开始 → S10 重组完成
/// → S12 字节就绪 → S13 解码开始 → S14 解码完成 → S16 Widget 加载中
/// → S17 Widget 收到帧
///
/// 全部写入 [Log]（可导出 TXT），并缓存在内存供界面实时显示。
library;

import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../../../foundation/log.dart';

/// 流水线阶段。
enum ReaderStage {
  chapterBegin('S0', '章节开始'),
  chapterApiOk('S1', 'URL列表就绪'),
  chapterReady('S2', '列表将构建'),
  listBuild('S3', '列表build'),
  tileBuild('S4', 'tile build'),
  providerLoad('S5', 'Provider.load'),
  downloadBegin('S6', '下载开始'),
  downloadOk('S7', '下载完成'),
  downloadFail('S8', '下载失败'),
  transformBegin('S9', '重组开始'),
  transformOk('S10', '重组完成'),
  transformFail('S11', '重组失败'),
  bytesReady('S12', '字节就绪'),
  codecBegin('S13', '解码开始'),
  codecOk('S14', '解码完成'),
  codecFail('S15', '解码失败'),
  widgetLoading('S16', 'Widget加载中'),
  widgetFrame('S17', 'Widget收到帧'),
  widgetError('S18', 'Widget错误'),
  layout('S19', '布局');

  const ReaderStage(this.code, this.label);
  final String code;
  final String label;
}

class ReaderPipelineEvent {
  ReaderPipelineEvent({
    required this.stage,
    required this.traceId,
    required this.pageIndex,
    required this.detail,
    required this.at,
    this.isError = false,
  });

  final ReaderStage stage;
  final String traceId;
  final int pageIndex;
  final String detail;
  final DateTime at;
  final bool isError;

  String get line {
    final t = at.toIso8601String().substring(11, 23);
    final err = isError ? 'ERR ' : '';
    final page = pageIndex < 0 ? '-' : '$pageIndex';
    return '[$t] $err${stage.code} p=$page ${stage.label} | $detail';
  }
}

/// 全局阅读器流水线诊断。
class ReaderPipeline {
  ReaderPipeline._();

  static const int _maxEvents = 500;
  static final List<ReaderPipelineEvent> _events = <ReaderPipelineEvent>[];
  static final Map<int, ReaderStage> _pageStage = <int, ReaderStage>{};
  static String? activeTrace;
  static DateTime? _chapterStartedAt;

  /// UI 刷新用：每次 mark 递增。
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);

  static List<ReaderPipelineEvent> get events =>
      List<ReaderPipelineEvent>.unmodifiable(_events.reversed);

  static Map<int, ReaderStage> get pageStages =>
      Map<int, ReaderStage>.unmodifiable(_pageStage);

  static String summaryForPage0() {
    final s = _pageStage[0];
    ReaderPipelineEvent? last0;
    for (var i = _events.length - 1; i >= 0; i--) {
      final e = _events[i];
      if (e.pageIndex == 0 || e.pageIndex < 0) {
        last0 = e;
        break;
      }
    }
    if (s == null && last0 == null) return '尚无流水线事件';
    final stage = s ?? last0!.stage;
    final detail = last0?.detail ?? '';
    final err = last0?.isError == true ? ' ⚠' : '';
    return '${stage.code} ${stage.label}$err $detail';
  }

  /// 页面 0 是否已到达「Widget 收到帧」。
  static bool get page0HasFrame =>
      _pageStage[0] == ReaderStage.widgetFrame ||
      _pageStage[0] == ReaderStage.layout;

  /// 卡在哪：最后一个非 error 阶段之后。
  static String stuckHint() {
    final s0 = _pageStage[0];
    if (s0 == null) {
      if (_events.isEmpty) return '未进入阅读器流水线';
      final last = _events.last;
      return '最新: ${last.stage.code} ${last.stage.label}';
    }
    if (s0 == ReaderStage.widgetFrame) return '第0页已收到帧（若仍黑=GPU/遮罩）';
    if (s0 == ReaderStage.bytesReady || s0 == ReaderStage.codecOk) {
      return '字节/解码已成功，卡在 Widget 上屏';
    }
    if (s0 == ReaderStage.transformOk) return '重组成功，卡在后续解码/上屏';
    if (s0 == ReaderStage.downloadOk) return '下载成功，卡在重组';
    if (s0.index <= ReaderStage.tileBuild.index) {
      return '列表/tile 已 build，卡在 Provider 加载';
    }
    return '当前: ${s0.code} ${s0.label}';
  }

  static String dumpRecent({int max = 100}) {
    final buf = StringBuffer();
    buf.writeln('=== ReaderPipeline dump ===');
    buf.writeln('trace=$activeTrace');
    buf.writeln('page0=${summaryForPage0()}');
    buf.writeln('stuck=${stuckHint()}');
    buf.writeln('pageStages=$_pageStage');
    buf.writeln('--- events newest first ---');
    for (final e in events.take(max)) {
      buf.writeln(e.line);
    }
    return buf.toString();
  }

  static void reset(String traceId) {
    activeTrace = traceId;
    _chapterStartedAt = DateTime.now();
    _events.clear();
    _pageStage.clear();
    mark(ReaderStage.chapterBegin, pageIndex: -1, detail: 'trace=$traceId');
  }

  static int? _elapsedMs() {
    final start = _chapterStartedAt;
    if (start == null) return null;
    return DateTime.now().difference(start).inMilliseconds;
  }

  static void mark(
    ReaderStage stage, {
    int pageIndex = -1,
    String detail = '',
    bool isError = false,
    String? traceId,
  }) {
    if (pageIndex >= 0 && !isError) {
      final prev = _pageStage[pageIndex];
      // 不回退阶段；loading 进度不刷屏
      if (prev != null && stage.index < prev.index) return;
      if (prev == stage && stage == ReaderStage.widgetLoading) return;
    }

    final trace = traceId ?? activeTrace ?? 'none';
    final ms = _elapsedMs();
    final elapsed = ms == null ? '' : ' +${ms}ms';
    final fullDetail = '$detail$elapsed'.trim();
    final event = ReaderPipelineEvent(
      stage: stage,
      traceId: trace,
      pageIndex: pageIndex,
      detail: fullDetail,
      at: DateTime.now(),
      isError: isError,
    );
    _events.add(event);
    while (_events.length > _maxEvents) {
      _events.removeAt(0);
    }
    if (pageIndex >= 0) {
      final prev = _pageStage[pageIndex];
      if (prev == null || stage.index >= prev.index || isError) {
        _pageStage[pageIndex] = stage;
      }
    }

    final msg =
        'PIPE ${stage.code} trace=$trace p=${pageIndex < 0 ? '-' : pageIndex} '
        '${stage.label} | $fullDetail';
    if (isError) {
      Log.w('PIPE ${stage.code}', error: msg);
    } else {
      Log.i('PIPE ${stage.code}', msg);
    }
    tick.value = tick.value + 1;
  }

  // ---- 便捷阶段 API ----

  static void chapterApiOk({required int urlCount}) =>
      mark(ReaderStage.chapterApiOk, detail: 'urls=$urlCount');

  static void chapterReady({required int imageCount}) =>
      mark(ReaderStage.chapterReady, detail: 'images=$imageCount');

  static void listBuild({required int pageCount, required Size mq}) => mark(
        ReaderStage.listBuild,
        detail:
            'pages=$pageCount mq=${mq.width.toStringAsFixed(0)}x${mq.height.toStringAsFixed(0)}',
      );

  static void tileBuild(int pageIndex, {required String cacheKey}) => mark(
        ReaderStage.tileBuild,
        pageIndex: pageIndex,
        detail: 'cache=len=${cacheKey.length}',
      );

  static void downloadBegin(int pageIndex, {required String host}) => mark(
        ReaderStage.downloadBegin,
        pageIndex: pageIndex,
        detail: 'host=$host',
      );

  static void downloadOk(
    int pageIndex, {
    required String host,
    required int len,
    required String magic,
  }) =>
      mark(
        ReaderStage.downloadOk,
        pageIndex: pageIndex,
        detail: 'host=$host len=$len magic=$magic',
      );

  static void downloadFail(int pageIndex, {required Object error}) => mark(
        ReaderStage.downloadFail,
        pageIndex: pageIndex,
        detail: 'err=$error',
        isError: true,
      );

  static void transformBegin(int pageIndex, {required int inLen}) => mark(
        ReaderStage.transformBegin,
        pageIndex: pageIndex,
        detail: 'in=$inLen',
      );

  static void transformOk(
    int pageIndex, {
    required int outLen,
    required String magic,
  }) =>
      mark(
        ReaderStage.transformOk,
        pageIndex: pageIndex,
        detail: 'out=$outLen magic=$magic',
      );

  static void transformFail(int pageIndex, {required Object error}) => mark(
        ReaderStage.transformFail,
        pageIndex: pageIndex,
        detail: 'err=$error',
        isError: true,
      );

  static void bytesReady(
    int pageIndex, {
    required int len,
    required String magic,
  }) =>
      mark(
        ReaderStage.bytesReady,
        pageIndex: pageIndex,
        detail: 'len=$len magic=$magic',
      );

  static void codecBegin(int pageIndex, {required int len}) => mark(
        ReaderStage.codecBegin,
        pageIndex: pageIndex,
        detail: 'len=$len',
      );

  static void codecOk(
    int pageIndex, {
    required int width,
    required int height,
  }) =>
      mark(
        ReaderStage.codecOk,
        pageIndex: pageIndex,
        detail: 'size=${width}x$height',
      );

  static void codecFail(int pageIndex, {required Object error}) => mark(
        ReaderStage.codecFail,
        pageIndex: pageIndex,
        detail: 'err=$error',
        isError: true,
      );

  static void widgetLoading(int pageIndex, {int? loaded, int? total}) => mark(
        ReaderStage.widgetLoading,
        pageIndex: pageIndex,
        detail: 'loaded=$loaded total=$total',
      );

  static void widgetFrame(
    int pageIndex, {
    required double layoutW,
    required double layoutH,
  }) =>
      mark(
        ReaderStage.widgetFrame,
        pageIndex: pageIndex,
        detail:
            'layout=${layoutW.toStringAsFixed(1)}x${layoutH.toStringAsFixed(1)}',
      );

  static void widgetError(int pageIndex, {required Object error}) => mark(
        ReaderStage.widgetError,
        pageIndex: pageIndex,
        detail: 'err=$error',
        isError: true,
      );
}
