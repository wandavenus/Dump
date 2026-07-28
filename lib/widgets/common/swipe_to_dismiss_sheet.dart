import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

/// Wraps arbitrary bottom-sheet content with a swipe-down-to-dismiss
/// gesture that responds anywhere on the child — not just a drag handle.
///
/// Dragging down translates the whole sheet with a subtle fade. If the
/// drag exceeds [dismissDistance] or [dismissVelocity] on release, the
/// enclosing route is popped; otherwise it snaps back to rest.
class SwipeToDismissSheet extends StatefulWidget {
  final Widget child;
  final double dismissDistance;
  final double dismissVelocity;

  const SwipeToDismissSheet({
    super.key,
    required this.child,
    this.dismissDistance = 80,
    this.dismissVelocity = 700,
  });

  @override
  State<SwipeToDismissSheet> createState() => _SwipeToDismissSheetState();
}

class _SwipeToDismissSheetState extends State<SwipeToDismissSheet> {
  double _dragOffset = 0;

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    setState(() {
      _dragOffset = (_dragOffset + delta).clamp(0, double.infinity);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > widget.dismissDistance ||
        velocity > widget.dismissVelocity) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    setState(() => _dragOffset = 0);
  }

  @override
  Widget build(BuildContext context) {
    final dragFraction = (_dragOffset / 240).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _handleDragUpdate,
      onVerticalDragEnd: _handleDragEnd,
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Opacity(opacity: 1 - (dragFraction * 0.35), child: widget.child),
      ),
    );
  }
}
