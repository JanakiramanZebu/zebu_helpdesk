import 'package:flutter/material.dart';

/// ===============================================================
/// WEB COLORS (Brand + Business + Semantic Aliases)
/// ===============================================================
///
///
/// Usage: read the static members directly.
/// Example: `ZebuColors.primary`, `ZebuColors.textPrimaryDark`
///
///
class ZebuColors {
  // Private constructor for singleton pattern
  const ZebuColors._();

  // Singleton instance - use this instead of WebColors()
  static const ZebuColors instance = ZebuColors._();

  // ---------------- BRAND ----------------

  static const Color primary = Color(0xFF0037B7);
  static const Color primaryDark = Color(0xFF58A6FF);

  static const Color secondary = Color(0xFF0052CC);
  static const Color secondaryDark = Color(0xFF388BFD);

  static const Color tertiary = Color(0xFFC40024);

  //-------------------------Text---------------------

  static const Color textBlack = Color(0xFF000000);
  static const Color textWhite = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF121212);
  static const Color textPrimaryDark = Color(0xFFC9D1D9);

  static const Color textSecondary = Color(0xFF4A4A4A);
  static const Color textSecondaryDark = Color(0xFF8B949E);

  static const Color textTertiary = Color(0xFF6B6B6B);
  static const Color textTertiaryDark = Color(0xFF6E7681);

  // ---------------- CARD / SURFACE ----------------

  static const Color card = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF161B22);

  static const Color cardBorder = Color(0xFFE1E4E8);
  static const Color cardBorderDark = Color(0xFF30363D);

  static const Color cardHover = Color(0xFFF6F8FA);
  static const Color cardHoverDark = Color(0xFF21262D); 

  static const Color cardPressed = Color(0xFFEAEEF2);
  static const Color cardPressedDark = Color(0xFF30363D);

  // ---------------- BUSINESS / STATUS ----------------

  static const Color profit = Color(0xFF00B14F);
  static const Color profitDark = Color(0xFF3FB950); 
  static const Color loss = Color(0xFFFF1717);
  static const Color lossDark = Color(0xFFF85149);

  static const Color success = Color(0xFF00B14F);
  static const Color successDark = Color(0xFF238636);

  static const Color error = Color(0xFFFF1717);
  // static const Color errorDark = Color(0xFFDA3633);
  static const Color errorDark = Color(0xFFF85149);

  static const Color warning = Color(0xFFFFB038);
  static const Color warningDark = Color(0xFFD29922);
  static const Color pending = Color(0xFFFFB038);

  /// Trade-journal note marker on the P&L Summary heat map. A vivid orange
  /// chosen to stay visible on the profit green, the loss red, and the empty
  /// grey cells alike; rendered with a lighter same-hue glow around it.
  static const Color noteMarker = Color(0xFFFF7900);

  // ---------------- BACKGROUND----------------

  static const Color searchBg = Color(0xFFF9F9F9);
  static const Color searchBgDark = Color(0xFF010409);

  // Input field background (shadcn TextField default)
  static const Color inputBg = Color(0xFFF9F9F9);
  static const Color inputBgDark = Color(0xFF171C22);

  static const Color listItemBg = Color(0xFFF1F3F8);
  static const Color listItemBgDark = Color(0xFF161B22);

  static const Color backgroundColor = Color(0xFFffffff);
  static const Color backgroundColorDark = Color(0xFF0D0F11);

  // Sidebar / secondary background
  static const Color sidebarBg = Color(0xFFF6F8FA);
  static const Color sidebarBgDark = Color(0xFF010409);

  // Overlay background (modals, dropdowns)
  static const Color overlayBg = Color(0xFFFFFFFF);
  static const Color overlayBgDark = Color(0xFF161B22);

  // ---------------- BORDER / DIVIDER ----------------

  static const Color divider = Color(0xFFDDE2E7);
  static const Color dividerDark = Color(0xFF30363D);

  static const Color borderMuted = Color(0xFFE1E4E8);
  static const Color borderMutedDark = Color(0xFF21262D);

  static const Color outlinedBorder = Color(0xFF0037B7);
  static const Color outlinedBorderDark = Color(0xFF58A6FF);

  // ---------------- ICON ----------------

  static const Color icon = Color(0xFF000000);
  static const Color iconDark = Color(0xFF8B949E);

  static const Color iconSecondary = Color(0xFF6B6B6B);
  static const Color iconSecondaryDark = Color(0xFF6E7681);

  static const Color modalBarrierLight = Color(0x66000000); // black @ 40%
  static const Color modalBarrierDark = Color(0x4E010409);

  // ---------------- SCROLLBAR ----------------
  static const Color scrollbarThumbLight =
      Color(0x804A4A4A); // textSecondary @ 50%
  static const Color scrollbarThumbDark =
      Color(0x806E7681); //  fg-subtle @ 50%

  static const Color scrollbarTrack = Color(0xFFF6F8FA);
  static const Color scrollbarTrackDark = Color(0xFF010409);

  // ---------------- INTERACTION / RIPPLE ----------------
  static const Color rippleLight = Color(0x26000000); // black @ 15%
  static const Color rippleDark = Color(0x2658A6FF); //  blue @ 15%

  static const Color highlightLight = Color(0x14000000); // black @ 8%
  static const Color highlightDark = Color(0x1458A6FF); //  blue @ 8%

  // Row/list hover
  static const Color rowHover = Color(0xFFF6F8FA);
  static const Color rowHoverDark = Color(0xFF161B22);

  // Selected/active state
  static const Color selectedBg = Color(0xFFE8F4FD);
  static const Color selectedBgDark = Color(0xFF1F2937);

  static const Color transparent = Color(0x00000000);

  static const Color dialog = Color(0xFFFFFFFF);
  static const Color dialogDark = Color(0xFF161B22);

  // static const Color dashboardCarColor = Color.fromARGB(19, 65, 75, 94);
  static const Color dashboardCarColor = Color(0xFF171A1E);
   // 123 alpha value in ARGB format

}

/// Parses a `#RRGGBB` hex string (the format the journal-notes backend stores
/// for tag colours) into a [Color].
///
/// Tolerant of bad input — an empty or malformed string returns [fallback]
/// instead of throwing, unlike the private `_hexToColor` copies in the chart
/// engine, which crash on `''`. Also accepts `#AARRGGBB`.
Color hexToColor(String? hex, {Color fallback = ZebuColors.textSecondary}) {
  if (hex == null) return fallback;
  final cleaned = hex.replaceAll('#', '').trim();
  if (cleaned.length != 6 && cleaned.length != 8) return fallback;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return fallback;
  // 6-digit input gets an opaque alpha.
  return Color(cleaned.length == 6 ? (0xFF000000 | value) : value);
}

/// ===============================================================
/// WEB BOX SHADOWS (Reusable shadow definitions)
/// ===============================================================
///
/// Usage: ZebuShadows.panel, ZebuShadows.card, etc.
///
class ZebuShadows {
  // Private constructor
  const ZebuShadows._();

  // ---------------- PANEL / SHEET SHADOWS ----------------
  /// Shadow for side panels and sheets sliding from the edge
  static List<BoxShadow> panel = [
    BoxShadow(
      color: const Color(0x26000000), // black @ 15%
      blurRadius: 20,
      offset: const Offset(-5, 0),
      spreadRadius: 2,
    ),
  ];

  /// Shadow for panels sliding from right
  static List<BoxShadow> panelRight = [
    BoxShadow(
      color: const Color(0x26000000), // black @ 15%
      blurRadius: 20,
      offset: const Offset(-5, 0),
      spreadRadius: 2,
    ),
  ];

  static List<BoxShadow> panelLeft = [
    BoxShadow(
      color: const Color(0x26000000),
      blurRadius: 20,
      offset: const Offset(5, 0),
      spreadRadius: 2,
    ),
  ];

  // ---------------- PANEL SHADOWS (Dark) ----------------
  static List<BoxShadow> panelDark = [
    BoxShadow(
      color: const Color(0x66010409),
      blurRadius: 16,
      offset: const Offset(-4, 0),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> panelRightDark = [
    BoxShadow(
      color: const Color(0x66010409),
      blurRadius: 16,
      offset: const Offset(-4, 0),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> panelLeftDark = [
    BoxShadow(
      color: const Color(0x66010409),
      blurRadius: 16,
      offset: const Offset(4, 0),
      spreadRadius: 0,
    ),
  ];

  // ---------------- CARD SHADOWS (Light) ----------------
  static List<BoxShadow> card = [
    BoxShadow(
      color: const Color(0x1A000000), // black @ 10%
      blurRadius: 10,
      offset: const Offset(0, 2),
      spreadRadius: 0,
    ),
  ];

  /// Elevated shadow for cards on hover
  static List<BoxShadow> cardHover = [
    BoxShadow(
      color: const Color(0x26000000), // black @ 15%
      blurRadius: 16,
      offset: const Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  // ---------------- CARD SHADOWS (Dark) ----------------
  static List<BoxShadow> cardDark = [
    BoxShadow(
      color: const Color(0x33010409), // Very subtle
      blurRadius: 3,
      offset: const Offset(0, 1),
      spreadRadius: 0,
    ),
  ];

  static List<BoxShadow> cardHoverDark = [
    BoxShadow(
      color: const Color(0x4D010409),
      blurRadius: 6,
      offset: const Offset(0, 2),
      spreadRadius: 0,
    ),
  ];

  // No shadow - use border instead
  static List<BoxShadow> none = [];

  // ---------------- MODAL SHADOWS (Light) ----------------
  static List<BoxShadow> modal = [
    BoxShadow(
      color: const Color(0x33000000), // black @ 20%
      blurRadius: 24,
      offset: const Offset(0, 8),
      spreadRadius: 0,
    ),
  ];

  // ---------------- MODAL SHADOWS (Dark) ----------------
  static List<BoxShadow> modalDark = [
    BoxShadow(
      color: const Color(0x99010409),
      blurRadius: 24,
      offset: const Offset(0, 8),
      spreadRadius: 4,
    ),
  ];

  // ---------------- DROPDOWN SHADOWS (Light) ----------------
  static List<BoxShadow> dropdown = [
    BoxShadow(
      color: const Color(0x1A000000), // black @ 10%
      blurRadius: 12,
      offset: const Offset(0, 4),
      spreadRadius: 0,
    ),
  ];

  // ---------------- DROPDOWN SHADOWS (Dark) ----------------
  static List<BoxShadow> dropdownDark = [
    BoxShadow(
      color: const Color(0x80010409),
      blurRadius: 12,
      offset: const Offset(0, 8),
      spreadRadius: 1,
    ),
  ];
}
