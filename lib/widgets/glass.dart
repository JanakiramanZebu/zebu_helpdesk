import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable **"aurora glass"** building blocks — the same material language as
/// the sign-in screen, shared by the dashboard and every main tab.
///
/// The recipe: [canvas] paints an aurora gradient lit by cyan/indigo glows, then
/// translucent surfaces float over it. The whole system is **brightness-aware**:
/// a deep navy→black canvas with luminous panels in dark mode, and a soft
/// blue-white canvas with frosted white panels in light mode. Every surface /
/// text / border token resolves against the ambient [Theme]'s brightness, so a
/// widget that reads these will follow the app's theme toggle automatically.
///
/// Two flavours of material:
///  * **Real frosted glass** — [frost] wraps a `BackdropFilter` blur, used for
///    the few *static* chrome bars (nav bar) where the GPU cost is paid once.
///    [frost] is theme-agnostic (a plain blur).
///  * **Glass-lite** — [tint] returns a theme whose `surface`/`Card` colors read
///    as glass panes over the [canvas] *without* a per-card blur (cheap inside
///    long scrolling lists).
class Glass {
  Glass._();

  // --- Fixed brand accents (identical in both modes) ------------------------
  // Used for data-viz bars, chips and the selected nav pill — they read well on
  // both the dark and the light canvas, so they don't vary by brightness.
  static const Color accent = Color(0xFF22D3EE); // cyan
  static const Color indigo = Color(0xFF6366F1);

  // --- Dark palette ---------------------------------------------------------
  static const Color _bgTopDark = Color(0xFF0B1120);
  static const Color _bgMidDark = Color(0xFF0A0E1A);
  static const Color _bgBottomDark = Color(0xFF05070D);
  static const Color _glowCyanDark = Color(0x3322D3EE);
  static const Color _glowIndigoDark = Color(0x336366F1);
  static const Color _glowSkyDark = Color(0x2238BDF8);

  /// Solid dark fill for panels/cards floating over the canvas. Kept opaque
  /// (not translucent) so scrolled content, popup menus and pinned headers
  /// never bleed through — the "glass" depth comes from the aurora canvas
  /// showing in the margins around these panels, plus the [border] hairline.
  static const Color _surfaceDark = Color(0xFF161D30);

  /// Opaque dark fill for overlays that must stay readable (dialogs, popup
  /// menus, bottom sheets) — where a translucent surface would let the content
  /// behind bleed through.
  static const Color _overlayDark = Color(0xFF141A2B);

  static const Color _textPrimaryDark = Color(0xFFF2F6FC);
  static const Color _textMutedDark = Color(0xA8FFFFFF);
  static const Color _linkDark = Color(0xFF38BDF8); // sky

  // --- Light palette --------------------------------------------------------
  static const Color _bgTopLight = Color(0xFFEDF2FB);
  static const Color _bgMidLight = Color(0xFFF4F6FB);
  static const Color _bgBottomLight = Color(0xFFFCFDFF);
  static const Color _glowCyanLight = Color(0x1A22D3EE);
  static const Color _glowIndigoLight = Color(0x1A6366F1);
  static const Color _glowSkyLight = Color(0x2238BDF8);

  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _overlayLight = Color(0xFFFFFFFF);
  static const Color _textPrimaryLight = Color(0xFF141414);
  static const Color _textMutedLight = Color(0xFF5B6472);
  static const Color _linkLight = Color(0xFF0A6CD8); // deeper sky for contrast

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  // --- Brightness-aware tokens ----------------------------------------------

  /// Panel/card fill floating over the [canvas].
  static Color surfaceFill(BuildContext context) =>
      _isDark(context) ? _surfaceDark : _surfaceLight;

  /// Opaque fill for overlays / solid app bars that must stay readable.
  static Color overlayFill(BuildContext context) =>
      _isDark(context) ? _overlayDark : _overlayLight;

  /// Primary inline-text tone for text painted *outside* theme-driven child
  /// widgets (app-bar title, section headers).
  static Color textPrimary(BuildContext context) =>
      _isDark(context) ? _textPrimaryDark : _textPrimaryLight;

  /// Muted inline-text tone (subtitles, secondary labels).
  static Color textMuted(BuildContext context) =>
      _isDark(context) ? _textMutedDark : _textMutedLight;

  /// Sky-blue link / drill-in tone, darkened in light mode for contrast.
  static Color link(BuildContext context) =>
      _isDark(context) ? _linkDark : _linkLight;

  /// A hairline used as the edge of glass surfaces — white in dark mode, a soft
  /// black in light mode.
  static Color border(BuildContext context, [double alpha = 0.10]) =>
      (_isDark(context) ? Colors.white : Colors.black)
          .withValues(alpha: alpha);

  // --- Canvas ---------------------------------------------------------------

  /// Full-bleed aurora canvas for the given [brightness]: a gradient lit by
  /// aurora glows, with [child] stacked on top. Also sets the matching
  /// status-bar icon brightness (light icons over the dark canvas, dark icons
  /// over the light one).
  static Widget canvas({
    required Brightness brightness,
    required Widget child,
  }) {
    final isDark = brightness == Brightness.dark;
    final decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [_bgTopDark, _bgMidDark, _bgBottomDark]
            : const [_bgTopLight, _bgMidLight, _bgBottomLight],
        stops: const [0.0, 0.55, 1.0],
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Stack(
        children: [
          Positioned.fill(child: DecoratedBox(decoration: decoration)),
          Positioned(
            top: -110,
            right: -80,
            child: _glow(320, isDark ? _glowCyanDark : _glowCyanLight),
          ),
          Positioned(
            bottom: -130,
            left: -90,
            child: _glow(340, isDark ? _glowIndigoDark : _glowIndigoLight),
          ),
          Positioned(
            top: 200,
            left: -70,
            child: _glow(220, isDark ? _glowSkyDark : _glowSkyLight),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }

  static Widget _glow(double size, Color color) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
        ),
      ),
    ),
  );

  // Clean, flat list-screen background — a standard task-management surface.
  // Deliberately hue-neutral (no blue) and flat (no gradient / sheen / shadow):
  // a light grey-white in light mode so white cards separate cleanly, and a
  // calm flat dark in dark mode. Earlier blue and frosted-grey treatments were
  // rejected in UI review, so this stays plain and simple.
  static const Color _listBgLight = Color(0xFFF4F5F7);
  static const Color _listBgDark = Color(0xFF0B0F17);

  /// A flat, hue-neutral background for list-screen bodies (Tickets / Tasks /
  /// Inbox). Masks the global aurora canvas in the list area with a clean solid
  /// surface, so the list reads like a normal task-management list. Theme-aware.
  static Widget listBackdrop({
    required BuildContext context,
    required Widget child,
  }) {
    return ColoredBox(
      color: _isDark(context) ? _listBgDark : _listBgLight,
      child: child,
    );
  }

  /// Wrap [child] in a clipped `BackdropFilter` blur — real frosted glass.
  static Widget frost({required Widget child, double sigma = 18}) => ClipRect(
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    ),
  );

  /// Glass theme derived from [base], picking the light or dark treatment from
  /// `base.brightness`: translucent-reading `surface`/`Card` fills over the
  /// [canvas], a sky/indigo accent and matching text, so every theme-driven
  /// widget reads as a glass pane. App bars are solid (the canvas never bleeds
  /// through the chrome), and overlays that must stay readable (dialogs / menus
  /// / sheets) get an opaque fill. Apply with
  /// `Theme(data: Glass.tint(Theme.of(context)), child: ...)`.
  static ThemeData tint(ThemeData base) {
    final isDark = base.brightness == Brightness.dark;
    final surface = isDark ? _surfaceDark : _surfaceLight;
    final overlay = isDark ? _overlayDark : _overlayLight;
    final hairline = (isDark ? Colors.white : Colors.black)
        .withValues(alpha: isDark ? 0.10 : 0.08);

    final scheme = base.colorScheme.copyWith(
      surface: surface,
      outlineVariant: hairline,
      // Sky links read as the interactive accent in both modes.
      primary: isDark ? _linkDark : _linkLight,
    );

    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: scheme,
      cardTheme: base.cardTheme.copyWith(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: hairline),
        ),
      ),
      // Solid app bars (not transparent) so the aurora glows never bleed
      // through the title / search / filter chrome.
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: overlay,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: indigo,
        foregroundColor: Colors.white,
      ),
      // Keep overlays opaque so their content never bleeds through the glass.
      dialogTheme: base.dialogTheme.copyWith(backgroundColor: overlay),
      popupMenuTheme: base.popupMenuTheme.copyWith(color: overlay),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: overlay,
        modalBackgroundColor: overlay,
      ),
    );
  }
}
