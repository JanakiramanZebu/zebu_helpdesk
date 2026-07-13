import 'package:flutter/material.dart';

import '../../dashboard/web/_tokens.dart';

/// Shell-only palette for the sidebar rail and the top bar. Deliberately kept
/// out of the general [WebTokens] because these tones only ever appear inside
/// `HomeShellWeb` — no other screen consumes them.
///
/// Values track light/dark mode: light theme renders a **white sidebar** with
/// a hairline right border and brand-tinted selected pills (ClickUp-lite);
/// dark theme keeps the near-black rail from the previous iteration.
class ShellTokens {
  ShellTokens._(this.brightness);
  final Brightness brightness;
  bool get isLight => brightness == Brightness.light;

  static ShellTokens of(BuildContext context) =>
      ShellTokens._(Theme.of(context).brightness);

  // --- Dimensions ----------------------------------------------------------
  /// Full-width sidebar (icon + label).
  static const sidebarExpanded = 236.0;

  /// Icon-only rail width, matching the collapsed target hit-area.
  static const sidebarCollapsed = 68.0;

  /// Height of the persistent top bar.
  static const topbarHeight = 60.0;

  /// Viewport width under which the sidebar auto-collapses.
  static const collapseBreakpoint = 1100.0;

  // --- Sidebar surfaces ----------------------------------------------------
  /// Rail body colour. Light theme uses a **whisper-warm off-white**
  /// (`#FBFAF7`). Dark theme uses GitHub Dark's `canvas-inset` / `sidebar-bg`
  /// (`#010409`) — the deepest tone in the palette, so the rail reads as
  /// grounding for the layered surfaces to its right.
  Color get sidebarBg =>
      isLight ? const Color(0xFFFBFAF7) : const Color(0xFF010409);

  /// Right-edge hairline separating the sidebar from the content area. Warm
  /// hairline on light; GitHub `border-muted` (`#21262D`) on dark.
  Color get sidebarBorder =>
      isLight ? const Color(0xFFE8E4DA) : const Color(0xFF21262D);

  /// Inner divider (between the nav column and the profile footer).
  Color get sidebarDivider =>
      isLight ? const Color(0xFFE8E4DA) : const Color(0xFF21262D);

  // --- Sidebar text / icon tones ------------------------------------------
  /// Idle nav item text — muted secondary tone.
  Color get sidebarTextIdle =>
      isLight ? const Color(0xFF6B6D7A) : const Color(0xFF8B949E);

  /// Selected nav item text. Light → brand blue; dark → GitHub `text-primary`
  /// (`#F0F6FC`) so the selected pill reads with maximum contrast against
  /// the near-black rail.
  Color get sidebarTextActive =>
      isLight ? WebTokens.accentLight : const Color(0xFFF0F6FC);

  Color get sidebarIconIdle =>
      isLight ? const Color(0xFF6B6D7A) : const Color(0xFF8B949E);
  Color get sidebarIconActive =>
      isLight ? WebTokens.accentLight : const Color(0xFFF0F6FC);

  // --- Sidebar interaction states -----------------------------------------
  /// Nav row hover fill. Light theme uses a **brand-tinted** wash
  /// (`#E5EBF5`). Dark theme uses GitHub `sidebar-hover` (`#161B22`) —
  /// the `canvas-overlay` tone stepped one level above the sidebar bg.
  Color get sidebarHover =>
      isLight ? const Color(0xFFE5EBF5) : const Color(0xFF161B22);

  /// Selected nav row fill. Light theme uses the brand-muted tint; dark
  /// theme uses GitHub `sidebar-active` (`#21262D`) — surface-3.
  Color get sidebarSelected =>
      isLight ? const Color(0xFFE3EDFA) : const Color(0xFF21262D);

  // --- Sidebar accents -----------------------------------------------------
  /// Thin coloured bar on the left of the selected nav row.
  Color get sidebarAccentBar =>
      isLight ? WebTokens.accentLight : WebTokens.accentDark;

  /// Pink notification pill on the Inbox row (ClickUp reference).
  Color get sidebarBadgePink => const Color(0xFFFF3985);

  // --- Profile footer ------------------------------------------------------
  /// Avatar tint under the initial. Light → brand at 12 % alpha; dark →
  /// GitHub `surface-3` (`#21262D`).
  Color get profileAvatarBg => isLight
      ? WebTokens.accentLight.withValues(alpha: 0.12)
      : const Color(0xFF21262D);

  /// Initial letter foreground.
  Color get profileAvatarFg =>
      isLight ? WebTokens.accentLight : Colors.white;

  /// Profile name text — always the primary text tone in either mode.
  Color get profileNameFg =>
      isLight ? const Color(0xFF1F2028) : const Color(0xFFF0F6FC);

  /// Profile email text — muted secondary in either mode.
  Color get profileEmailFg =>
      isLight ? const Color(0xFF6B6D7A) : const Color(0xFF8B949E);

  // --- New Ticket CTA ------------------------------------------------------
  /// Flat-fill primary CTA above the nav destinations. Kept simple — no
  /// gradient, no glow, no motion. Hover is a single solid colour swap in
  /// the same family. Both modes now render a coloured pill (Mynt brand
  /// blue in light, GitHub accent blue in dark) so the CTA reads as the
  /// primary action against either rail.
  Color get ctaBg =>
      isLight ? WebTokens.accentLight : WebTokens.accentDark;
  Color get ctaBgHover =>
      isLight ? WebTokens.accentHoverLight : WebTokens.accentHoverDark;

  /// Border chrome. Light has no border (the solid brand fill is enough
  /// separation from the whisper-warm sidebar). Dark wears a 1 px white
  /// rim at ~10 % alpha so the top edge catches the tiniest bit of light
  /// against the deeper `canvas-inset` rail — no other chrome.
  Color? get ctaBorder =>
      isLight ? null : Colors.white.withValues(alpha: 0.10);
  Color? get ctaBorderHover =>
      isLight ? null : Colors.white.withValues(alpha: 0.16);

  /// Foreground (text). White in both modes — sits on the coloured pill.
  Color get ctaFg => Colors.white;

  /// Plus-glyph tint. White in both modes now that the surface itself
  /// carries the colour signal.
  Color get ctaIconFg => Colors.white;


  // --- Top bar surfaces ----------------------------------------------------
  /// Top bar mirrors the sidebar's deepest surface in dark mode — GitHub
  /// `navbar-bg` (`#010409`) — so the app chrome reads as one continuous
  /// grounding plate around the workspace.
  Color get topbarBg =>
      isLight ? const Color(0xFFFFFFFF) : const Color(0xFF010409);
  Color get topbarBorder =>
      isLight ? const Color(0xFFE8E4DA) : const Color(0xFF21262D);
}
