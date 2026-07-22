/// 竖直连续模式。
///
/// 列表 + 标准 [Image]（[createPageImageProvider] 负责下载与 JM 重组）。
library;

import 'package:flutter/material.dart';

import '../../../../foundation/reader_config.dart';
import '../../providers/list_state_provider.dart';
import '../../providers/reader_provider.dart' hide ReaderImage;
import '../../utils/image_preload_controller.dart';
import '../../utils/reader_pipeline.dart';
import '../reader_image.dart';
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
    final w = MediaQuery.sizeOf(context).width;
    final avgH = w > 0 ? w * 1.2 : 600.0;
    final index = (_scrollController.offset / avgH).floor().clamp(0, count - 1);
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
    final screenW = MediaQuery.sizeOf(context).width;
    final imageWidth = screenW > 1 ? screenW : 390.0;

    if (!_loggedOpen) {
      _loggedOpen = true;
      ReaderPipeline.listBuild(
        pageCount: pageCount,
        mq: MediaQuery.sizeOf(context),
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
          cacheExtent: MediaQuery.sizeOf(context).height * 3,
          padding: EdgeInsets.zero,
          itemCount: pageCount + 1,
          itemBuilder: (context, index) {
            if (index == pageCount) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '本章完',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
              );
            }

            final item = images[index];
            if (_tileLogged.add(index)) {
              ReaderPipeline.tileBuild(index, cacheKey: item.cacheKey);
            }

            return ReaderImage(
              key: ValueKey(item.cacheKey),
              url: item.url,
              cacheKey: item.cacheKey,
              headers: item.headers,
              fallbackUrls: item.fallbackUrls,
              bytesTransformer: item.bytesTransformer,
              width: imageWidth,
              // 仅作加载占位高度；出图后 Image 按真实宽高比占位。
              height: imageWidth * 1.2,
              fit: BoxFit.fitWidth,
              filterQuality: FilterQuality.medium,
              traceId: traceId,
              imageIndex: index,
            );
          },
        ),
      ),
    );
  }
}
