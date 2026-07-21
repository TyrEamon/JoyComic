/// 竖直连续模式（带全链路流水线诊断条）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../foundation/log.dart';
import '../../../../foundation/reader_config.dart';
import '../../image_pipeline/page_image_provider.dart';
import '../../providers/reader_provider.dart' hide ReaderImage;
import '../../utils/image_preload_controller.dart';
import '../../utils/reader_pipeline.dart';

class VerticalList extends StatefulWidget {
  const VerticalList({super.key});

  @override
  State<VerticalList> createState() => _VerticalListState();
}

class _VerticalListState extends State<VerticalList> {
  final ScrollController _scrollController = ScrollController();
  ImagePreloadController? _preloadController;
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
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _preloadController?.dispose();
    super.dispose();
  }

  Future<void> _copyDump() async {
    final text = ReaderPipeline.dumpRecent();
    await Clipboard.setData(ClipboardData(text: text));
    Log.i('ReaderPipeline dump copied', 'len=${text.length}');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('流水线日志已复制到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = context.selector((p) => p.pageCount);
    final images = context.selector((p) => p.images);
    final traceId = context.reader.traceId;
    final size = MediaQuery.sizeOf(context);

    if (!_loggedOpen) {
      _loggedOpen = true;
      ReaderPipeline.listBuild(pageCount: pageCount, mq: size);
      Log.i(
        'Reader vertical open',
        'trace=$traceId pages=$pageCount '
        'mq=${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}',
      );
    }

    return ColoredBox(
      color: const Color(0xFF0D47A1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 实时流水线诊断条
          Material(
            color: const Color(0xFFB71C1C),
            child: SafeArea(
              bottom: false,
              child: ValueListenableBuilder<int>(
                valueListenable: ReaderPipeline.tick,
                builder: (context, _, __) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '流水线诊断  共$pageCount页  '
                          '${size.width.toStringAsFixed(0)}×${size.height.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '卡点: ${ReaderPipeline.stuckHint()}',
                          style: const TextStyle(
                            color: Color(0xFFFFF59D),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '第0页: ${ReaderPipeline.summaryForPage0()}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            TextButton(
                              onPressed: _copyDump,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.black45,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                              ),
                              child: const Text('复制流水线日志'),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'trace=${traceId ?? '-'}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
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
                      if (_tileLogged.add(index)) {
                        ReaderPipeline.tileBuild(
                          index,
                          cacheKey: item.cacheKey,
                        );
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
                              child: ValueListenableBuilder<int>(
                                valueListenable: ReaderPipeline.tick,
                                builder: (context, _, __) {
                                  final stage =
                                      ReaderPipeline.pageStages[index];
                                  return Text(
                                    '第${index + 1}/$pageCount  '
                                    '${stage?.code ?? "?"} ${stage?.label ?? "等待"}',
                                    style: const TextStyle(
                                      color: Colors.yellow,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                },
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
                                  if (progress == null) {
                                    // 最终帧
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      if (!context.mounted) return;
                                      final box =
                                          context.findRenderObject()
                                              as RenderBox?;
                                      final sz = box?.size;
                                      ReaderPipeline.widgetFrame(
                                        index,
                                        layoutW: sz?.width ?? 0,
                                        layoutH: sz?.height ?? 0,
                                      );
                                    });
                                    return child;
                                  }
                                  ReaderPipeline.widgetLoading(
                                    index,
                                    loaded: progress.cumulativeBytesLoaded,
                                    total: progress.expectedTotalBytes,
                                  );
                                  return const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                    ),
                                  );
                                },
                                errorBuilder: (context, error, stack) {
                                  ReaderPipeline.widgetError(
                                    index,
                                    error: error,
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
