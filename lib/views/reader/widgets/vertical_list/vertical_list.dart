/// 竖直连续模式。
///
/// 出图关键结构（真机已验证）：
/// 固定非零高度槽 + [createPageImageProvider] + 系统 [Image]（fit contain）。
/// 不用 InteractiveViewer、不用自研 Image.memory 状态机。
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

  /// 非零页槽高度。诊断版 520 能出图；过小/0 会导致真机黑屏。
  static const double _kPageSlotHeight = 520;

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

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final count = context.reader.images.length;
    if (count == 0) return;
    final index = (_scrollController.offset / _kPageSlotHeight)
        .floor()
        .clamp(0, count - 1);
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

    if (!_loggedOpen) {
      _loggedOpen = true;
      ReaderPipeline.listBuild(pageCount: pageCount, mq: mq);
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

            // 能出图的槽位结构：固定高度 + Image 填满（黑底无彩条）。
            return SizedBox(
              width: double.infinity,
              height: _kPageSlotHeight,
              child: ColoredBox(
                color: Colors.black,
                child: Image(
                  image: provider,
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!context.mounted) return;
                        ReaderPipeline.widgetFrame(
                          index,
                          layoutW: mq.width,
                          layoutH: _kPageSlotHeight,
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
            );
          },
        ),
      ),
    );
  }
}
