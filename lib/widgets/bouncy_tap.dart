import 'package:flutter/material.dart';
import '../anim/shauchmap_springs.dart';

class BouncyTap extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scale;

  const BouncyTap({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.96,
  });

  @override
  State<BouncyTap> createState() => _BouncyTapState();
}

class _BouncyTapState extends State<BouncyTap>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      lowerBound: 0.0,
      upperBound: 2.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (!mounted) return;
    _controller.animateTo(
      widget.scale,
      duration: const Duration(milliseconds: 50),
      curve: Curves.easeOut,
    );
  }

  void _onTapUp(TapUpDetails details) {
    if (!mounted) return;
    _controller.springTo(1.0, spring: LooSprings.bouncy);
    widget.onTap();
  }

  void _onTapCancel() {
    if (!mounted) return;
    _controller.springTo(1.0, spring: LooSprings.bouncy);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: ScaleTransition(scale: _controller, child: widget.child),
    );
  }
}
