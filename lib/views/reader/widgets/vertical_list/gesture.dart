/// 竖直连续列表的缩放手势包装器。
///
/// 包装 [ScrollablePositionedList] 并提供：
///   - 双指缩放（双指触摸时锁定列表滚动，启用 [InteractiveViewer] 缩放）
///   - 双击放大 / 双击恢复（[Matrix4Tween] 动画）
///   - 区域点击翻页（上 1/3→上一页、中 1/3→工具栏、下 1/3→下一页）
///   - 菜单锁定状态下的半屏翻页（锁定后上/下半屏分别翻上/下页）
library;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../providers/reader_provider.dart';
import '../../providers/list_state_provider.dart';
import '../../utils/reader_utils.dart';
import '../../../../foundation/reader_config.dart';

/// 手势包装器。
///
/// [child] 为 [ScrollablePositionedList]；[jumpOffset] 为竖直翻页回调
///（由 [ReaderProvider.pageTurnForVertical] 注入）；[openOrCloseToolbar] 为
/// 工具栏切换回调。
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
  final Set<int> _activePointerIds = {};

  bool _isScrollable = true;

  // ============================ 多指追踪 ============================

  void _handlePointerChange(PointerEvent event, bool isAdding) {
    final wasScaleEnabledByTouch = _activePointerIds.length >= 2;
    if (isAdding) {
      _activePointerIds.add(event.pointer);
    } else {
      _activePointerIds.remove(event.pointer);
    }
    final isScaleEnabledByTouch = _activePointerIds.length >= 2;
    final shouldRebuild =
        !isDesktop &&
        !context.stateReader.isCtrlPressed &&
        wasScaleEnabledByTouch != isScaleEnabledByTouch;
    if (shouldRebuild && mounted) {
      setState(() {});
    }

    final shouldBeScrollable = _activePointerIds.length < 2;
    if (_isScrollable != shouldBeScrollable) {
      _isScrollable = shouldBeScrollable;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.stateReader.physics = _isScrollable
            ? const BouncingScrollPhysics()
            : const NeverScrollableScrollPhysics();
      });
    }
  }

  // ============================ 双击缩放 ============================

  final _transformationController = TransformationController();
  Offset _doubleTapPosition = Offset.zero;
  late AnimationController _animationController;
  late Animation<Matrix4> _animation;

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();

    if (currentScale > 1.05) {
      // 已放大 → 恢复原始尺寸
      _animation =
          Matrix4Tween(
            begin: _transformationController.value,
            end: Matrix4.identity(),
          ).animate(
            CurveTween(curve: Curves.easeOut).animate(_animationController),
          );
    } else {
      // 以双击点为中心放大 3×
      final endMatrix = Matrix4.identity()
        ..translateByVector3(
          Vector3(
            -_doubleTapPosition.dx * 2.0,
            -_doubleTapPosition.dy * 2.0,
            0.0,
          ),
        )
        ..scaleByVector3(Vector3(3.0, 3.0, 1.0));
      _animation =
          Matrix4Tween(
            begin: _transformationController.value,
            end: endMatrix,
          ).animate(
            CurveTween(curve: Curves.easeOut).animate(_animationController),
          );
    }
    _animationController.forward(from: 0);
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  // ============================ 单击翻页 ============================

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

  // ============================ 生命周期 ============================

  @override
  void initState() {
    super.initState();
    _animationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          _transformationController.value = _animation.value;
        });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // ============================ 构建 ============================

  @override
  Widget build(BuildContext context) {
    final isCtrlPressed = context.stateSelector((p) => p.isCtrlPressed);
    final scaleEnabled = isDesktop
        ? isCtrlPressed
        : (isCtrlPressed || _activePointerIds.length >= 2);

    return Listener(
      onPointerDown: (event) => _handlePointerChange(event, true),
      onPointerUp: (event) => _handlePointerChange(event, false),
      onPointerCancel: (event) => _handlePointerChange(event, false),
      child: GestureDetector(
        onTap: () {
          context.stateReader.lockMenu ? _handleLockTap() : _handleTap();
        },
        onTapDown: (details) => _tapDownDetails = details,
        onDoubleTapDown: _handleDoubleTapDown,
        onDoubleTap: _handleDoubleTap,
        child: InteractiveViewer(
          transformationController: _transformationController,
          scaleEnabled: scaleEnabled,
          minScale: 1.0,
          maxScale: 3.5,
          child: widget.child,
        ),
      ),
    );
  }
}
