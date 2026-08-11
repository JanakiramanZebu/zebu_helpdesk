import 'package:flutter/material.dart';

/// Wraps a screen body so that on wide viewports the content is centered with
/// a sensible maximum width instead of stretching edge-to-edge.
///
/// On phone-width screens (viewport ≤ [maxWidth]) this is a pure pass-through
/// — no extra widgets in the tree, no behavioural change.
/// On wider screens it centers the [child] inside a [SizedBox] of exactly
/// [maxWidth], so the child fills the constrained area.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({super.key, required this.child, this.maxWidth = 1400});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= maxWidth) return child;
        return Center(
          child: SizedBox(width: maxWidth, child: child),
        );
      },
    );
  }
}
