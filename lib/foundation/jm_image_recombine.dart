/// 禁漫图片分段重组算法。
///
/// 禁漫服务端会将图片按纵向条带切割并乱序下发给客户端，客户端需依据
/// 章节信息推算出分段数与原始顺序，把条带重新拼回原图，才能正确显示。
///
/// 本模块负责：根据章节 epsId 推算条带数量 → 解码图片 → 按逆序重组条带 →
/// 重新编码为 JPEG。整个计算放在独立 Isolate 中执行，避免阻塞 UI。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

/// 推算图片需要被分割的条带数量。
///
/// 分段规则按章节 epsId 落在不同区间而不同：
///   - 旧作（epsId < scrambleId）：不分割
///   - 中间区间：固定 10 条带
///   - 较新区间与最新区间：用 md5(epsId + 图片名) 的末位字符取模计算 2~N 条带
///
/// [epsId] 章节 id；[scrambleId] 当前适用的 scramble 阈值（业务侧默认值）；
/// [pictureName] 图片文件名（不含扩展名）。
int getSegmentationNum(String epsId, String scrambleId, String pictureName) {
  final scrambleIdValue = int.parse(scrambleId);
  final epsIdValue = int.parse(epsId);
  var num = 0;

  if (epsIdValue < scrambleIdValue) {
    num = 0;
  } else if (epsIdValue < 268850) {
    num = 10;
  } else if (epsIdValue > 421926) {
    final hashInput = epsIdValue.toString() + pictureName;
    final hash = md5.convert(utf8.encode(hashInput)).toString();
    final charCode = hash.codeUnitAt(hash.length - 1);
    num = (charCode % 8) * 2 + 2;
  } else {
    final hashInput = epsIdValue.toString() + pictureName;
    final hash = md5.convert(utf8.encode(hashInput)).toString();
    final charCode = hash.codeUnitAt(hash.length - 1);
    num = (charCode % 10) * 2 + 2;
  }

  return num;
}

/// 将已下载的图片字节按分段规则重组为原始顺序的 JPEG 字节。
///
/// 流程：解码原图 → 按高度均分为 num 个条带（末条带吸收余数）→
/// 在新画布上以条带**逆序**重新拼接 → 编码 JPEG。
Uint8List segmentPicture(
  Uint8List imgData,
  String epsId,
  String scrambleId,
  String bookId,
) {
  final num = getSegmentationNum(epsId, scrambleId, bookId);

  if (num <= 1) {
    return imgData;
  }

  final image.Image srcImg;
  try {
    srcImg = image.decodeImage(imgData)!;
  } catch (e) {
    throw Exception(
      "Failed to decode image: Data length is ${imgData.length} bytes",
    );
  }

  final blockSize = srcImg.height ~/ num;
  final remainder = srcImg.height % num;

  final blocks = <Map<String, int>>[];
  for (var i = 0; i < num; i++) {
    final start = i * blockSize;
    final end = start + blockSize + (i != num - 1 ? 0 : remainder);
    blocks.add({'start': start, 'end': end});
  }

  final dstImg = image.Image(width: srcImg.width, height: srcImg.height);

  var y = 0;
  for (var i = blocks.length - 1; i >= 0; i--) {
    final block = blocks[i];
    final currBlockHeight = block['end']! - block['start']!;
    final srcRange = srcImg.getRange(
      0,
      block['start']!,
      srcImg.width,
      currBlockHeight,
    );
    final dstRange = dstImg.getRange(0, y, srcImg.width, currBlockHeight);
    while (srcRange.moveNext() && dstRange.moveNext()) {
      dstRange.current.r = srcRange.current.r;
      dstRange.current.g = srcRange.current.g;
      dstRange.current.b = srcRange.current.b;
      dstRange.current.a = srcRange.current.a;
    }
    y += currBlockHeight;
  }

  return image.encodeJpg(dstImg);
}

// ============================ Isolate 后台执行 ============================

class _RecombinationTask {
  final Uint8List imgData;
  final String epsId;
  final String scrambleId;
  final String bookId;
  final String? savePath;
  final Completer<Uint8List>? completer;

  _RecombinationTask(
    this.imgData,
    this.epsId,
    this.scrambleId,
    this.bookId,
    this.completer, [
    this.savePath,
  ]);

  _RecombinationTask detachCompleter() =>
      _RecombinationTask(imgData, epsId, scrambleId, bookId, null, savePath);
}

/// 在独立 Isolate 中执行禁漫图片重组，避免解码阻塞 UI 主线程。
///
/// 维护一个单例 Isolate 与任务队列：每次 [recombine] 投递一个任务，
/// Isolate 处理完返回重组后的字节。失败会重建 Isolate 并重试该任务。
class JmRecombine {
  static Isolate? _isolate;
  static ReceivePort? _receivePort;
  static ReceivePort? _errorPort;
  static SendPort? _sendPort;
  static final List<_RecombinationTask> _tasks = [];
  static _RecombinationTask? _current;

  static Future<Uint8List> recombine(
    Uint8List imgData,
    String epsId,
    String scrambleId,
    String bookId, {
    String? savePath,
  }) async {
    final completer = Completer<Uint8List>();
    final task = _RecombinationTask(
      imgData,
      epsId,
      scrambleId,
      bookId,
      completer,
      savePath,
    );
    _tasks.add(task);
    if (_isolate == null && _receivePort == null) {
      _receivePort = ReceivePort();
      await _start();
    }
    _pushTask();
    return completer.future;
  }

  static void _pushTask() {
    if (_sendPort != null && _current == null && _tasks.isNotEmpty) {
      _current = _tasks.removeAt(0);
      _sendPort!.send(_current!.detachCompleter());
    }
  }

  static Future<void> _start() async {
    _errorPort = ReceivePort();
    _isolate = await Isolate.spawn(
      _run,
      _receivePort!.sendPort,
      onError: _errorPort!.sendPort,
      debugName: 'JmRecombine',
    );
    _listen();
  }

  static void _listen() {
    _receivePort!.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
        _pushTask();
      } else if (message is Uint8List) {
        _current!.completer!.complete(message);
        _current = null;
        _pushTask();
      } else if (message is Exception) {
        _current!.completer!.completeError(message);
        _current = null;
        _pushTask();
      }
    });

    _errorPort!.listen((message) {
      _recover();
    });
  }

  static Future<void> _recover() async {
    _receivePort?.close();
    _errorPort?.close();
    _isolate = null;
    _sendPort = null;
    if (_current != null) {
      _tasks.add(_current!);
      _current = null;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    if (_isolate == null && _receivePort == null) {
      _receivePort = ReceivePort();
      await _start();
    } else {
      _pushTask();
    }
  }

  static void _run(SendPort port) {
    final receivePort = ReceivePort();
    receivePort.listen((message) async {
      if (message is _RecombinationTask) {
        try {
          final bytes = segmentPicture(
            message.imgData,
            message.epsId,
            message.scrambleId,
            message.bookId,
          );
          port.send(bytes);
        } catch (e) {
          port.send(Exception(e.toString()));
        }
      }
    });
    port.send(receivePort.sendPort);
  }
}

/// 对外入口：在后台 Isolate 中重组禁漫图片并（可选）写盘。
Future<Uint8List> recombineJmImage(
  Uint8List imgData,
  String epsId,
  String scrambleId,
  String bookId, {
  String? savePath,
}) {
  return JmRecombine.recombine(
    imgData,
    epsId,
    scrambleId,
    bookId,
    savePath: savePath,
  );
}
