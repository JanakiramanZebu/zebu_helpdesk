import 'package:flutter/material.dart';

import '../../dashboard/web/_tokens.dart';

/// Shell-only palette for the sidebar rail and the top bar. Deliberately kept
/// out of the general [WebTokens] because these tones only ever appear inside
/// `HomeShellWeb` — no other screen consumes them.
///
/// Values track light/dark mode: light theme renders a **brand-tinted
/// gradient rail** and a defined, tinted top bar with accent-chip nav items;
/// dark theme keeps the near-black rail with the same subtle depth cues.
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

  /// Corner radius of the inset content workspace card.
  static const workspaceRadius = 16.0;

  /// Gutter between the chrome (sidebar/topbar/window edges) and the
  /// workspace card — the canvas shows through here.
  static const workspaceGutter = 10.0;

  // --- Inset workspace -----------------------------------------------------
  /// Chrome canvas behind the sidebar, topbar, and workspace gutter. Light
  /// is a soft cool tint (not pure white) so the tinted chrome reads as a
  /// distinct plate that the white cards + workspace pop against; dark keeps
  /// GitHub's deepest `canvas-inset` (`#010409`) so the card reads as lifted.
  Color get canvas =>
      isLight ? const Color(0xFFF4F8FD) : const Color(0xFF010409);

  /// Hairline around the rounded workspace card — this line is what sells
  /// the inset, especially in dark mode where canvas and card are close.
  Color get workspaceBorder =>
      isLight ? const Color(0xFFDDE2E7) : const Color(0xFF21262D);

  // --- Sidebar surfaces ----------------------------------------------------
  /// Rich nav-rail wash — a soft brand-tinted vertical gradient so the sidebar
  /// reads as its own premium surface instead of flat white chrome. The
  /// bottom stop matches [canvas] so the rail melts into the gutter, while the
  /// top carries a gentle Mynt-blue tint. Dark mode lifts the top a step above
  /// the near-black inset for the same depth cue.
  Gradient get sidebarGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: isLight
        ? const [Color(0xFFE9EFFA), Color(0xFFF4F8FD)]
        : const [Color(0xFF0F141C), Color(0xFF010409)],
  );

  /// Idle nav-row fill — transparent so the rail gradient shows through; hover
  /// and selected states paint their own fills over it.
  Color get sidebarBg => Colors.transparent;

  /// Top-bar surface — a subtle tint a hair brighter than the rail so the app
  /// bar reads as its own band of chrome, closed off by [topbarBorder].
  Color get topbarBg =>
      isLight ? const Color(0xFFEDF2FB) : const Color(0xFF0D1117);

  /// Hairline under the top bar, defining it against the workspace below.
  Color get topbarBorder =>
      isLight ? const Color(0xFFDFE6F1) : const Color(0xFF21262D);

  /// Right-edge hairline separating the sidebar from the content area. Mobile
  /// cool `outlineVariant` (`#DDE2E7`) on light; GitHub `border-muted`
  /// (`#21262D`) on dark.
  Color get sidebarBorder =>
      isLight ? const Color(0xFFDDE2E7) : const Color(0xFF21262D);

  /// Inner divider (between the nav column and the profile footer).
  Color get sidebarDivider =>
      isLight ? const Color(0xFFDDE2E7) : const Color(0xFF21262D);

  // --- Sidebar text / icon tones ------------------------------------------
  /// Idle nav item text — mobile muted secondary tone (`#737373`).
  Color get sidebarTextIdle =>
      isLight ? const Color(0xFF737373) : const Color(0xFF8B949E);

  /// Selected nav item text. Light → brand blue; dark → GitHub `text-primary`
  /// (`#F0F6FC`) so the selected pill reads with maximum contrast against
  /// the near-black rail.
  Color get sidebarTextActive =>
      isLight ? WebTokens.accentLight : const Color(0xFFF0F6FC);

  Color get sidebarIconIdle =>
      isLight ? const Color(0xFF737373) : const Color(0xFF8B949E);
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
  Color get profileAvatarFg => isLight ? WebTokens.accentLight : Colors.white;

  /// Profile name text — mobile `textPrimary` (`#141414`) in light, GH
  /// `text-primary` in dark.
  Color get profileNameFg =>
      isLight ? const Color(0xFF141414) : const Color(0xFFF0F6FC);

  /// Profile email text — mobile muted secondary (`#737373`) in light.
  Color get profileEmailFg =>
      isLight ? const Color(0xFF737373) : const Color(0xFF8B949E);

  // --- New Ticket CTA ------------------------------------------------------
  /// Flat-fill primary CTA above the nav destinations. Kept simple — no
  /// gradient, no glow, no motion. Hover is a single solid colour swap in
  /// the same family. Both modes now render a coloured pill (Mynt brand
  /// blue in light, GitHub accent blue in dark) so the CTA reads as the
  /// primary action against either rail.
  Color get ctaBg => isLight ? WebTokens.accentLight : WebTokens.accentDark;
  Color get ctaBgHover =>
      isLight ? WebTokens.accentHoverLight : WebTokens.accentHoverDark;

  /// Border chrome. Light has no border (the solid brand fill is enough
  /// separation from the whisper-warm sidebar). Dark wears a 1 px white
  /// rim at ~10 % alpha so the top edge catches the tiniest bit of light
  /// against the deeper `canvas-inset` rail — no other chrome.
  Color? get ctaBorder => isLight ? null : Colors.white.withValues(alpha: 0.10);
  Color? get ctaBorderHover =>
      isLight ? null : Colors.white.withValues(alpha: 0.16);

  /// Foreground (text). White in both modes — sits on the coloured pill.
  Color get ctaFg => Colors.white;

  /// Plus-glyph tint. White in both modes now that the surface itself
  /// carries the colour signal.
  Color get ctaIconFg => Colors.white;
}
