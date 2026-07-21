/// 竖直连续列表的手势包装器。
///
/// 提供：
///   - 区域点击翻页（上 1/3→上一页、中 1/3→工具栏、下 1/3→下一页）
///   - 菜单锁定状态下的半屏翻页
///
/// 注意：默认**不**再包 [InteractiveViewer]。在 iOS Impeller 上，
/// 永久把整页连续列表塞进 InteractiveViewer 会导致已解码帧黑屏
/// （日志有 codec/first frame 但像素不可见）。缩放改走后续单页方案。
library;

import 'package:flutter/material.dart';

import '../../providers/list_state_provider.dart';
import '../../utils/reader_utils.dart';
import '../../../../foundation/reader_config.dart';

/// 手势包装器。
class GestureWrapper extends StatefulWidget {
  const GestureWrapper({
    super.key,
    required this.child,
    required this.jumpOffset,
    required this.openOrCloseToolbar,
  });

  final Widget child;
  final void Function(double) jumpOffset;
  final VoidCallback openOrCloseToolbar;

  @override
  State<GestureWrapper> createState() => _GestureWrapperState();
}

class _GestureWrapperState extends State<GestureWrapper> {
  late TapDownDetails _tapDownDetails;

  void _handleTap() {
    final conf = ReaderConf.instance;

    if (!conf.enableGesture) {
      widget.openOrCloseToolbar();
      return;
    }

    final height = context.height;
    final centerFraction = conf.verticalCenterFraction;
    final topFraction = (1 - centerFraction) / 2;
    final slipFactor = conf.slipFactor;
    final topHeight = height * topFraction;
    final centerHeight = height * centerFraction;
    final dy = _tapDownDetails.localPosition.dy;

    if (dy < topHeight) {
      widget.jumpOffset(height * slipFactor * -1);
    } else if (dy < (topHeight + centerHeight)) {
      widget.openOrCloseToolbar();
    } else {
      widget.jumpOffset(height * slipFactor);
    }
  }

  void _handleLockTap() {
    final conf = ReaderConf.instance;
    if (!conf.enableGesture) return;

    final height = context.height;
    final halfHeight = height / 2;
    final dy = _tapDownDetails.localPosition.dy;
    final slipFactor = conf.slipFactor;

    if (dy < halfHeight) {
      widget.jumpOffset(height * slipFactor * -1);
    } else {
      widget.jumpOffset(height * slipFactor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        context.stateReader.lockMenu ? _handleLockTap() : _handleTap();
      },
      onTapDown: (details) => _tapDownDetails = details,
      child: widget.child,
    );
  }
}
