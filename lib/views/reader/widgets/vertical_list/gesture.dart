/// 竖直连续列表手势：区域点击 + 双指缩放 + 双击缩放。
///
/// 多指时锁定列表滚动，避免与 [InteractiveViewer] 抢手势。
/// 缩放仅在本层矩阵完成；列表本身仍是标准 [Image]，不走自研绘制。
library;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

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

class _GestureWrapperState extends State<GestureWrapper>
    with SingleTickerProviderStateMixin {
  final Set<int> _activePointers = <int>{};
  final TransformationController _transform = TransformationController();
  late final AnimationController _animController;
  Animation<Matrix4>? _animation;
  Offset _doubleTapPos = Offset.zero;
  late TapDownDetails _tapDownDetails;
  bool _scrollEnabled = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addListener(() {
      final a = _animation;
      if (a != null) _transform.value = a.value;
    });
    _transform.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _animController.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _setScrollEnabled(bool enabled) {
    if (_scrollEnabled == enabled) return;
    _scrollEnabled = enabled;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.stateReader.physics = enabled
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics();
    });
  }

  void _onPointer(PointerEvent event, {required bool down}) {
    if (down) {
      _activePointers.add(event.pointer);
    } else {
      _activePointers.remove(event.pointer);
    }
    _setScrollEnabled(_activePointers.length < 2);
  }

  void _handleTap() {
    final conf = ReaderConf.instance;
    if (!conf.enableGesture) {
      widget.openOrCloseToolbar();
      return;
    }

    // 缩放中：单击恢复 1x
    if (_transform.value.getMaxScaleOnAxis() > 1.05) {
      _animateTo(Matrix4.identity());
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

  void _handleDoubleTap() {
    final scale = _transform.value.getMaxScaleOnAxis();
    if (scale > 1.05) {
      _animateTo(Matrix4.identity());
      return;
    }
    final end = Matrix4.identity()
      ..translateByVector3(
        Vector3(-_doubleTapPos.dx * 2.0, -_doubleTapPos.dy * 2.0, 0),
      )
      ..scaleByVector3(Vector3(3.0, 3.0, 1.0));
    _animateTo(end);
  }

  void _animateTo(Matrix4 end) {
    _animation = Matrix4Tween(begin: _transform.value, end: end).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _onPointer(e, down: true),
      onPointerUp: (e) => _onPointer(e, down: false),
      onPointerCancel: (e) => _onPointer(e, down: false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _tapDownDetails = d,
        onTap: _handleTap,
        onDoubleTapDown: (d) => _doubleTapPos = d.localPosition,
        onDoubleTap: _handleDoubleTap,
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1.0,
          maxScale: 3.5,
          // 1x 时不抢拖动手势，交给 ListView 滚动
          panEnabled: _transform.value.getMaxScaleOnAxis() > 1.05,
          scaleEnabled: true,
          child: widget.child,
        ),
      ),
    );
  }
}
