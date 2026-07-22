/// 竖直连续列表手势：区域点击翻页 / 工具栏。
///
/// 不使用 [InteractiveViewer] 包裹整表——iOS 上会再次黑屏。
/// 缩放改走后续单页方案。
library;

import 'package:flutter/material.dart';

import '../../../../foundation/reader_config.dart';
import '../../providers/list_state_provider.dart';
import '../../utils/reader_utils.dart';

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

    if (context.stateReader.lockMenu) {
      if (dy < height / 2) {
        widget.jumpOffset(height * slipFactor * -1);
      } else {
        widget.jumpOffset(height * slipFactor);
      }
      return;
    }

    if (dy < topHeight) {
      widget.jumpOffset(height * slipFactor * -1);
    } else if (dy < (topHeight + centerHeight)) {
      widget.openOrCloseToolbar();
    } else {
      widget.jumpOffset(height * slipFactor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _tapDownDetails = d,
      onTap: _handleTap,
      child: widget.child,
    );
  }
}
