/// 竖直连续沉浸阅读。
///
/// ## 真机铁律（多次黑屏验证）
/// 1. 必须：非零高度槽 + [Column] + [Expanded] + 系统 [Image]
/// 2. 禁止：解码后 [setState] 改槽高（会重建 tile → 黑屏）
/// 3. 禁止：整表 [InteractiveViewer]
/// 4. 禁止：去掉 Expanded 只留裸 Image
///
/// 沉浸：黑底、全宽 [BoxFit.fitWidth]、槽高 = 屏宽×固定比例（构建时算一次，不动态改）。
library;

import 'package:flutter/material.dart';

import '../../../../foundation/reader_config.dart';
import '../../image_pipeline/page_image_provider.dart';
import '../../providers/list_state_provider.dart';
import '../../providers/reader_provider.dart' hide ReaderImage;
import '../../utils/image_preload_controller.dart';
import '../../utils/reader_pipeline.dart';
import 'gesture.dart';

/// 竖直连续模式。
class VerticalList extends StatefulWidget {
  const VerticalList({super.key});

  @override
  State<VerticalList> createState() => _VerticalListState();
}

class _VerticalListState extends State<VerticalList> {
  final ScrollController _scrollController = ScrollController();
  ImagePreloadController? _preloadController;
  int _lastPage = 0;
  bool _loggedOpen = false;
  final Set<int> _tileLogged = <int>{};

  /// 高/宽。常见 JM 页约 960×1355 ≈ 1.41；用固定比例避免解码后改高度。
  static const double _kSlotAspect = 1.41;

  /// 绝对下限（逻辑像素）。
  static const double _kMinSlot = 400;

  @override
  void initState() {
    super.initState();
    final reader = context.reader;
    _preloadController = ImagePreloadController(
      context: context,
      items: reader.images,
      type: reader.readerType,
      maxPreloadCount: ReaderConf.instance.preloadImageCount,
      traceId: reader.traceId,
    );
    reader.initPreloadController(_preloadController!);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _preloadController?.dispose();
    super.dispose();
  }

  /// 全页统一槽高：只依赖屏宽，**永不**因单页解码 setState。
  double _slotHeight(double width) {
    final h = width * _kSlotAspect;
    if (!h.isFinite || h < _kMinSlot) {
      // 与能出图诊断版同量级
      return 520;
    }
    return h;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final count = context.reader.images.length;
    if (count == 0) return;
    final w = MediaQuery.sizeOf(context).width;
    final slot = _slotHeight(w > 1 ? w : 390);
    final index = (_scrollController.offset / slot).floor().clamp(0, count - 1);
    if (index != _lastPage) {
      _lastPage = index;
      _preloadController?.onAnchorChanged([index]);
      context.reader.onPageNoChanged(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final physics = context.stateSelector((p) => p.physics);
    final pageCount = context.selector((p) => p.pageCount);
    final images = context.selector((p) => p.images);
    final traceId = context.reader.traceId;
    final mq = MediaQuery.sizeOf(context);
    final width = mq.width > 1 ? mq.width : 390.0;
    final slotH = _slotHeight(width);

    if (!_loggedOpen) {
      _loggedOpen = true;
      ReaderPipeline.listBuild(pageCount: pageCount, mq: mq);
      ReaderPipeline.mark(
        ReaderStage.listBuild,
        detail: 'slotH=${slotH.toStringAsFixed(1)} aspect=$_kSlotAspect',
      );
    }

    return GestureWrapper(
      openOrCloseToolbar: context.reader.openOrCloseToolbar,
      jumpOffset: (delta) {
        if (!_scrollController.hasClients) return;
        final target = (_scrollController.offset + delta).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      },
      child: ColoredBox(
        color: Colors.black,
        child: ListView.builder(
          controller: _scrollController,
          physics: physics,
          // ignore: deprecated_member_use
          cacheExtent: mq.height * 3,
          padding: EdgeInsets.zero,
          itemCount: pageCount + 1,
          itemBuilder: (context, index) {
            if (index == pageCount) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  '本章完',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white54,
                  ),
                ),
              );
            }

            final item = images[index];
            if (_tileLogged.add(index)) {
              ReaderPipeline.tileBuild(index, cacheKey: item.cacheKey);
            }

            final provider = createPageImageProvider(
              url: item.url,
              cacheKey: item.cacheKey,
              fallbackUrls: item.fallbackUrls,
              headers: item.headers,
              bytesTransformer: item.bytesTransformer,
              traceId: traceId,
              imageIndex: index,
            );

            // ========== 能出图铁律结构（e82905f / a747864）==========
            // SizedBox(非零高) → ColoredBox → Column → Expanded → Image
            // 勿删 Expanded；勿在解码后改 height 触发整表 setState。
            return SizedBox(
              width: double.infinity,
              height: slotH,
              child: ColoredBox(
                color: Colors.black,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Image(
                        image: provider,
                        // 横向铺满；槽高按固定比例，上下黑边远小于 contain+矮槽
                        fit: BoxFit.fitWidth,
                        width: double.infinity,
                        alignment: Alignment.topCenter,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!context.mounted) return;
                              ReaderPipeline.widgetFrame(
                                index,
                                layoutW: width,
                                layoutH: slotH,
                              );
                            });
                            return child;
                          }
                          return const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                color: Colors.white54,
                                strokeWidth: 3,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stack) {
                          ReaderPipeline.widgetError(index, error: error);
                          return Center(
                            child: Text(
                              '加载失败 第${index + 1}页',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
