/// 竖直连续模式 —— 诊断版。
///
/// 每页强制：红标题条 + 蓝底 + 固定高度 + 标准 [Image]。
/// 若用户仍「纯黑、无红条」，说明列表根本没进树，不是图片解码问题。
library;

import 'package:flutter/material.dart';

import '../../../../foundation/log.dart';
import '../../../../foundation/reader_config.dart';
import '../../image_pipeline/page_image_provider.dart';
import '../../providers/reader_provider.dart' hide ReaderImage;
import '../../utils/image_preload_controller.dart';

class VerticalList extends StatefulWidget {
  const VerticalList({super.key});

  @override
  State<VerticalList> createState() => _VerticalListState();
}

class _VerticalListState extends State<VerticalList> {
  final ScrollController _scrollController = ScrollController();
  ImagePreloadController? _preloadController;
  bool _loggedOpen = false;

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
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _preloadController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = context.selector((p) => p.pageCount);
    final images = context.selector((p) => p.images);
    final traceId = context.reader.traceId;
    final size = MediaQuery.sizeOf(context);

    if (!_loggedOpen) {
      _loggedOpen = true;
      Log.i(
        'Reader vertical open',
        'trace=$traceId pages=$pageCount '
        'mq=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)} '
        'images=${images.length}',
      );
    }

    // 全屏蓝底：若用户看到蓝底，说明列表区域在画。
    return ColoredBox(
      color: const Color(0xFF0D47A1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 永久可见顶栏（不依赖工具栏状态）
          Material(
            color: const Color(0xFFB71C1C),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  '阅读器诊断  共$pageCount页  ${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: pageCount <= 0
                ? const Center(
                    child: Text(
                      'pageCount=0 无图片',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    itemCount: pageCount,
                    itemBuilder: (context, index) {
                      final item = images[index];
                      final provider = createPageImageProvider(
                        url: item.url,
                        cacheKey: item.cacheKey,
                        fallbackUrls: item.fallbackUrls,
                        headers: item.headers,
                        bytesTransformer: item.bytesTransformer,
                        traceId: traceId,
                        imageIndex: index,
                      );

                      // 固定高度 520，绝不依赖解码尺寸。
                      return Container(
                        width: double.infinity,
                        height: 520,
                        color: index.isEven
                            ? const Color(0xFF1565C0)
                            : const Color(0xFF2E7D32),
                        margin: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              color: Colors.black87,
                              padding: const EdgeInsets.all(6),
                              child: Text(
                                '第${index + 1}/$pageCount页',
                                style: const TextStyle(
                                  color: Colors.yellow,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Image(
                                image: provider,
                                fit: BoxFit.contain,
                                alignment: Alignment.topCenter,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.low,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stack) {
                                  Log.w(
                                    'Reader Image error',
                                    error:
                                        'trace=$traceId idx=$index err=$error',
                                  );
                                  return Center(
                                    child: Text(
                                      '图失败 #$index\n$error',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
