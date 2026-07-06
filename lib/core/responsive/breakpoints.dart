import 'package:flutter/widgets.dart';

/// Width-based breakpoints used across the app to switch between phone,
/// tablet, and desktop layouts.
///
/// Cutoffs follow Material 3 window-size classes:
///   compact  → phone           (< 600)
///   medium   → small tablet    (600 – 904)
///   expanded → large tablet    (905 – 1239)
///   large    → desktop / wide  (≥ 1240)
///
/// Screens should branch on these via `LayoutBuilder` (preferred — measures
/// the actual content area) or `context.breakpoint` (uses the window size).
enum Breakpoint {
  compact,
  medium,
  expanded,
  large;

  /// True for any breakpoint at or above the side-nav threshold (905).
  /// Below this, screens use the phone layout (bottom nav, single column).
  bool get isWide => index >= Breakpoint.expanded.index;

  static Breakpoint of(double width) {
    if (width < 600) return Breakpoint.compact;
    if (width < 905) return Breakpoint.medium;
    if (width < 1240) return Breakpoint.expanded;
    return Breakpoint.large;
  }
}

extension BreakpointContext on BuildContext {
  Breakpoint get breakpoint => Breakpoint.of(MediaQuery.sizeOf(this).width);
}
