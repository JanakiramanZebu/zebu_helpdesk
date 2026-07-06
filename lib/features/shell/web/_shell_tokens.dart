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
  /// (`#FBFAF7`) — barely a step off pure white but enough to feel
  /// connected to the paper-tinted content bg rather than a stark plate
  /// glued to the side. Dark theme stays near-black.
  Color get sidebarBg =>
      isLight ? const Color(0xFFFBFAF7) : const Color(0xFF0A0A0D);

  /// Right-edge hairline separating the sidebar from the content area. Only
  /// needed on light bg — the dark rail already contrasts against the light
  /// content strongly enough.
  Color get sidebarBorder =>
      isLight ? const Color(0xFFEAECEF) : const Color(0xFF1E1E26);

  /// Inner divider (between the nav column and the profile footer).
  Color get sidebarDivider =>
      isLight ? const Color(0xFFEAECEF) : const Color(0xFF17171E);

  // --- Sidebar text / icon tones ------------------------------------------
  /// Idle nav item text — muted secondary tone. On light bg this is the same
  /// muted grey used across the app's list rows.
  Color get sidebarTextIdle =>
      isLight ? const Color(0xFF6B6D7A) : const Color(0xFFA0A2AB);

  /// Selected nav item text. On light bg → brand blue (reads as selected
  /// without needing a filled solid pill); on dark bg → white for contrast.
  Color get sidebarTextActive =>
      isLight ? WebTokens.accent : const Color(0xFFFFFFFF);

  Color get sidebarIconIdle =>
      isLight ? const Color(0xFF6B6D7A) : const Color(0xFFB7B9C1);
  Color get sidebarIconActive =>
      isLight ? WebTokens.accent : const Color(0xFFFFFFFF);

  // --- Sidebar interaction states -----------------------------------------
  /// Nav row hover fill. Light theme uses a **brand-tinted** accent-soft
  /// grey (`#E5EBF5`) — deeper than the previous neutral `#F1F3F8` so the
  /// hover reads clearly against the warm off-white sidebar bg while still
  /// staying calmer than the [sidebarSelected] pill.
  Color get sidebarHover =>
      isLight ? const Color(0xFFE5EBF5) : const Color(0xFF1E1F26);

  /// Selected nav row fill. Light theme uses the brand-muted tint so the
  /// pill reads as "in the brand family" without being loud.
  Color get sidebarSelected =>
      isLight ? const Color(0xFFE3EDFA) : const Color(0xFF22232B);

  // --- Sidebar accents -----------------------------------------------------
  /// Thin coloured bar on the left of the selected nav row.
  Color get sidebarAccentBar => WebTokens.accent;

  /// Pink notification pill on the Inbox row (ClickUp reference).
  Color get sidebarBadgePink => const Color(0xFFFF3985);

  // --- Profile footer ------------------------------------------------------
  /// Avatar tint under the initial. Light → brand at 12 % alpha; dark → a
  /// warm neutral so the initial still pops.
  Color get profileAvatarBg => isLight
      ? WebTokens.accent.withValues(alpha: 0.12)
      : const Color(0xFF2A2B34);

  /// Initial letter foreground.
  Color get profileAvatarFg =>
      isLight ? WebTokens.accent : Colors.white;

  /// Profile name text — always the primary text tone in either mode.
  Color get profileNameFg =>
      isLight ? const Color(0xFF1F2028) : Colors.white;

  /// Profile email text — muted secondary in either mode.
  Color get profileEmailFg =>
      isLight ? const Color(0xFF6B6D7A) : const Color(0xFFA0A2AB);

  // --- New Ticket CTA ------------------------------------------------------
  /// Filled brand pill sitting above the nav destinations.
  Color get ctaBg => WebTokens.accent;
  Color get ctaHover => WebTokens.accentHover;
  Color get ctaFg => Colors.white;

  // --- Top bar surfaces ----------------------------------------------------
  Color get topbarBg =>
      isLight ? const Color(0xFFFFFFFF) : const Color(0xFF15151A);
  Color get topbarBorder =>
      isLight ? const Color(0xFFEAECEF) : const Color(0xFF26262E);
}
