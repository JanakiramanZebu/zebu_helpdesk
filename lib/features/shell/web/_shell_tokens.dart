import 'package:flutter/material.dart';

import '../../../res/zebu_theme.dart';

/// Shell-only palette and metrics for the icon rail, the section sub-panel,
/// and the inset workspace card. Deliberately kept out of the general
/// [ZebuTheme] because these tones only ever appear inside `HomeShellWeb` —
/// no other screen consumes them.
///
/// The shell is a three-column composition sitting on a single [canvas]:
///
/// ```
///   ┌────┬───────────────┬──────────────────────────┐
///   │rail│  sub-panel    │      workspace card      │
///   │ 72 │     280       │        remaining         │
///   └────┴───────────────┴──────────────────────────┘
/// ```
///
/// The rail floats *over* the other two when hover-expanded, so its surface
/// must be opaque in both states — see [railSurface] / [railSurfaceExpanded].
class ShellTokens {
  ShellTokens._(this.brightness);
  final Brightness brightness;
  bool get isLight => brightness == Brightness.light;

  static final ShellTokens _light = ShellTokens._(Brightness.light);
  static final ShellTokens _dark = ShellTokens._(Brightness.dark);

  static ShellTokens of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? _light : _dark;

  // --- Dimensions ----------------------------------------------------------
  /// Resting icon-only rail width. One 44 px tile plus a 14 px gutter each
  /// side — the tile is the full hit target, so the whole rail is clickable.
  static const railWidth = 72.0;

  /// Width the rail animates to while the pointer rests on it. Wide enough
  /// for the longest destination label ("Dashboard") plus the Inbox count
  /// pill without truncating, which is what lets us skip Zoho-style
  /// mid-word ellipsis entirely.
  static const railExpandedWidth = 240.0;

  /// Uniform rail row height — nav items, the create button, and the footer
  /// utilities all share it so the column reads as one rhythm.
  static const railItemHeight = 44.0;

  /// Horizontal gutter each side of a rail tile. `railWidth - 2 * this`
  /// is the tile width, so these two constants must stay in step.
  static const railGutter = 14.0;

  /// Tile edge — square when collapsed, the left cap of the pill when open.
  static double get railTileSize => railWidth - railGutter * 2;

  /// Section sub-panel width (Workspace destinations, Create actions).
  static const panelWidth = 280.0;

  /// Corner radius of the inset content workspace card.
  static const workspaceRadius = 16.0;

  /// Gutter between the chrome (rail / panel / window edges) and the cards —
  /// the canvas shows through here.
  static const workspaceGutter = 10.0;

  /// Below this viewport width the sub-panel would leave too little room for
  /// a list plus an open detail panel, so it auto-collapses.
  static const panelCollapseBreakpoint = 1180.0;

  // --- Canvas & cards ------------------------------------------------------
  /// Chrome canvas behind every card. Light is a soft cool tint (not pure
  /// white) so the white cards read as distinct plates; dark keeps GitHub's
  /// deepest `canvas-inset` (`#010409`) so cards read as lifted.
  Color get canvas =>
      isLight ? const Color(0xFFF4F8FD) : const Color(0xFF010409);

  /// Hairline around the rounded cards — this line is what sells the inset,
  /// especially in dark mode where canvas and card are close.
  Color get cardBorder =>
      isLight ? const Color(0xFFDDE2E7) : const Color(0xFF21262D);

  // --- Rail surfaces -------------------------------------------------------
  /// Rail surface at rest. Matches [canvas] so the collapsed rail reads as
  /// part of the page rather than a plate — the Pinterest/Intercom look.
  Color get railSurface => canvas;

  /// Rail surface while hover-expanded. The rail overlays the sub-panel and
  /// content in this state, so it steps up to an opaque elevated surface and
  /// takes [railShadow] to read as floating above them.
  Color get railSurfaceExpanded =>
      isLight ? const Color(0xFFFFFFFF) : const Color(0xFF161B22);

  /// Cast only while expanded — a soft right-side falloff so the floating
  /// rail separates from whatever it covers.
  static const railShadow = <BoxShadow>[
    BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(4, 0)),
    BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(1, 0)),
  ];

  // --- Rail item states ----------------------------------------------------
  /// Idle glyph tint — muted so the rail recedes until pointed at.
  Color get railIconIdle =>
      isLight ? const Color(0xFF6B7280) : const Color(0xFF8B949E);

  /// Hovered glyph tint — full-strength neutral, no colour yet.
  Color get railIconHover =>
      isLight ? const Color(0xFF141414) : const Color(0xFFF0F6FC);

  /// Selected glyph tint — the single point of brand colour in the rail.
  Color get railIconActive =>
      isLight ? ZebuTheme.accentLight : ZebuTheme.accentDark;

  /// Hover tile fill. Deliberately a *neutral* grey with no blue cast — it
  /// has to stay clearly distinct from [railTileActive], which sits only a
  /// few units away in the blue channel. Hover means "you could go here";
  /// only the selected tone is allowed to look brand-coloured.
  Color get railTileHover =>
      isLight ? const Color(0xFFECEEF1) : const Color(0xFF21262D);

  /// Selected tile fill — brand-muted, pairs with [railIconActive].
  Color get railTileActive =>
      isLight ? const Color(0xFFE3EDFA) : const Color(0x332F81F7);

  /// Resting tile fill.
  ///
  /// **Not** [Colors.transparent] — that is transparent *black*, and
  /// [AnimatedContainer] lerps RGBA channels linearly, so fading from it to
  /// a light tone drags the tile through a half-alpha grey on the way. Using
  /// the hover tone at zero alpha holds the hue constant so only the alpha
  /// animates, and the fill washes in cleanly.
  Color get railTileIdle => railTileHover.withValues(alpha: 0);

  /// Idle label tint in the expanded rail.
  Color get railLabelIdle =>
      isLight ? const Color(0xFF565C68) : const Color(0xFF8B949E);

  /// Selected label tint in the expanded rail.
  Color get railLabelActive =>
      isLight ? ZebuTheme.accentLight : const Color(0xFFF0F6FC);

  /// Divider between nav groups inside the rail.
  Color get railDivider =>
      isLight ? const Color(0xFFDDE2E7) : const Color(0xFF21262D);

  /// Unread pill on the Inbox row, and its collapsed-state corner dot.
  static const badgePink = Color(0xFFFF3985);

  // The rail deliberately has no CTA palette. Create is a peer of the
  // destinations, drawn with the same idle/hover/selected tones above — a
  // solid fill at tile size reads as "selected", which would put two loud
  // marks in the rail with the louder one not being the state.

  // --- Tooltip -------------------------------------------------------------
  /// Dark pill behind the collapsed-rail tooltip. Near-black in both themes
  /// so the tooltip reads as an overlay, not a themed surface.
  Color get tooltipBg =>
      isLight ? const Color(0xFF1F2328) : const Color(0xFF30363D);
  Color get tooltipFg => Colors.white;

  // --- Profile footer ------------------------------------------------------
  /// Profile name text in the expanded rail footer.
  Color get profileNameFg =>
      isLight ? const Color(0xFF141414) : const Color(0xFFF0F6FC);

  /// Profile email text in the expanded rail footer.
  Color get profileEmailFg =>
      isLight ? const Color(0xFF737373) : const Color(0xFF8B949E);
}
