/// 阅读器最高优先级诊断悬浮球。
///
/// 通过 [rootOverlay] 插入根 Overlay，保证盖在阅读器 Scaffold / 黑屏内容之上。
/// 可拖动；点开可看流水线卡点、最近事件、复制日志、返回。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../foundation/log.dart';
import '../utils/reader_pipeline.dart';

/// 挂在 [Reader] 上：自身不占布局，把悬浮球塞进根 Overlay。
class ReaderDebugOverlayHost extends StatefulWidget {
  const ReaderDebugOverlayHost({
    super.key,
    this.traceId,
    this.onBack,
  });

  final String? traceId;
  final VoidCallback? onBack;

  @override
  State<ReaderDebugOverlayHost> createState() => _ReaderDebugOverlayHostState();
}

class _ReaderDebugOverlayHostState extends State<ReaderDebugOverlayHost> {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _mount());
  }

  @override
  void didUpdateWidget(covariant ReaderDebugOverlayHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.traceId != widget.traceId) {
      _entry?.markNeedsBuild();
    }
  }

  void _mount() {
    if (!mounted || _entry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      Log.w('ReaderDebugOverlay', error: 'root Overlay not found');
      return;
    }
    _entry = OverlayEntry(
      builder: (overlayContext) {
        return _ReaderDebugBallLayer(
          traceId: widget.traceId,
          onBack: widget.onBack ??
              () {
                try {
                  if (overlayContext.mounted) {
                    GoRouter.of(overlayContext).pop();
                  }
                } catch (_) {}
              },
          onRequestRebuild: () => _entry?.markNeedsBuild(),
        );
      },
    );
    overlay.insert(_entry!);
    Log.i('ReaderDebugOverlay', 'inserted on root Overlay');
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _ReaderDebugBallLayer extends StatefulWidget {
  const _ReaderDebugBallLayer({
    required this.traceId,
    required this.onBack,
    required this.onRequestRebuild,
  });

  final String? traceId;
  final VoidCallback onBack;
  final VoidCallback onRequestRebuild;

  @override
  State<_ReaderDebugBallLayer> createState() => _ReaderDebugBallLayerState();
}

class _ReaderDebugBallLayerState extends State<_ReaderDebugBallLayer> {
  Offset _offset = const Offset(0, 0);
  bool _expanded = false;
  bool _placed = false;

  @override
  void initState() {
    super.initState();
    ReaderPipeline.tick.addListener(_onTick);
  }

  @override
  void dispose() {
    ReaderPipeline.tick.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _copyDump() async {
    final text = ReaderPipeline.dumpRecent();
    await Clipboard.setData(ClipboardData(text: text));
    Log.i('ReaderDebugOverlay', 'pipeline dump copied len=${text.length}');
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('流水线日志已复制'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openLogs() async {
    try {
      if (context.mounted) {
        await GoRouter.of(context).push('/logs');
      }
    } catch (e) {
      Log.w('ReaderDebugOverlay open logs', error: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    if (!_placed) {
      _placed = true;
      // 右下角初始位置（避开 Home 指示条）
      _offset = Offset(mq.width - 72, mq.height - pad.bottom - 160);
    }

    final stuck = ReaderPipeline.stuckHint();
    final page0 = ReaderPipeline.summaryForPage0();
    final events = ReaderPipeline.events.take(12).toList();

    return Stack(
      children: [
        // 展开时半透明遮罩，仍可点悬浮球区域
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _expanded = false),
              child: const ColoredBox(color: Color(0x99000000)),
            ),
          ),

        // 展开面板（固定在顶部，最高 z）
        if (_expanded)
          Positioned(
            left: 12,
            right: 12,
            top: pad.top + 8,
            child: Material(
              elevation: 32,
              borderRadius: BorderRadius.circular(12),
              color: const Color(0xFF1A237E),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: mq.height * 0.55),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '阅读器流水线（最高层悬浮）',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '卡点: $stuck',
                        style: const TextStyle(
                          color: Color(0xFFFFF59D),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '第0页: $page0',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        'trace=${widget.traceId ?? ReaderPipeline.activeTrace ?? '-'}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonal(
                            onPressed: _copyDump,
                            child: const Text('复制流水线'),
                          ),
                          FilledButton.tonal(
                            onPressed: _openLogs,
                            child: const Text('打开日志页'),
                          ),
                          FilledButton(
                            onPressed: widget.onBack,
                            child: const Text('返回'),
                          ),
                          OutlinedButton(
                            onPressed: () => setState(() => _expanded = false),
                            child: const Text('收起'),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white24),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: events.length,
                          itemBuilder: (context, i) {
                            final e = events[i];
                            return Text(
                              e.line,
                              style: TextStyle(
                                color: e.isError
                                    ? const Color(0xFFFF8A80)
                                    : Colors.white70,
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // 可拖动悬浮球
        Positioned(
          left: _offset.dx.clamp(0, mq.width - 64),
          top: _offset.dy.clamp(pad.top, mq.height - 64),
          child: GestureDetector(
            onPanUpdate: (d) {
              setState(() {
                _offset += d.delta;
              });
            },
            onTap: () => setState(() => _expanded = !_expanded),
            child: Material(
              elevation: 40,
              shape: const CircleBorder(),
              color: Colors.transparent,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF6D00),
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xCC000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.bug_report, color: Colors.white, size: 22),
                    Text(
                      ReaderPipeline.pageStages[0]?.code ?? 'DBG',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
