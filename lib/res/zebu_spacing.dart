import 'package:flutter/material.dart';

/// Layout primitives for the web target — spacing, corner radii, elevation.
///
/// Kept on this app's own scale rather than Mynt Plus Web's `AppSpacing`
/// (4 / 8 / 16 / 24 / 32 / 48). Ours is finer — it includes 12, 20, and 40 —
/// and those three steps carry 434 of the ~950 spacing call sites here.
/// Adopting the coarser scale would have silently re-spaced a third of the
/// app, so the numbers stay and only the home changes.

/// 4 px base unit. `sN` is N × 4 px, so the name states the multiple.
class ZebuSpacing {
  ZebuSpacing._();

  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
}

/// Corner radii.
///
///   sm  8   buttons, inputs, chips, status pills
///   md  10  search field, tab indicator
///   lg  12  cards, icon badges
///   xl  14  snackbars
///   2xl 16  stat tiles, nav pills
///   3xl 18  dialogs
///
/// `rXs` (6) is smaller than any design-system step and is reserved for tiny
/// inline chips where 8 looks chunky.
class ZebuRadius {
  ZebuRadius._();

  static const double rXs = 6;
  static const double rSm = 8;
  static const double rMd = 10;
  static const double rLg = 12;
  static const double rXl = 14;
  static const double r2xl = 16;
  static const double r3xl = 18;
  static const double rFull = 999;
}

/// Drop shadows.
///
/// Deliberately separate from [ZebuShadows] in the colours file, which holds
/// Mynt Plus Web's heavier panel/modal/dropdown set. These are this app's
/// quieter surface elevations — a helpdesk grid sitting under a whisper of
/// lift rather than a floating trading panel.
class ZebuElevation {
  ZebuElevation._();

  /// Whisper-quiet card lift — barely visible, just enough to detach a
  /// surface from the page. Used at rest on cards and KPI tiles.
  static const List<BoxShadow> shadowXs = [
    BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> shadowMd = [
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> shadowLg = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// Two-layer soft shadow for floating menus and popovers. Softer than a
  /// Material `elevation: 8` so it reads as a premium overlay, not a plate.
  static const List<BoxShadow> popoverShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
  ];
}
