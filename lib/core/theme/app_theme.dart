import 'package:flutter/material.dart';
import '../../res/zebu_text_styles.dart';

/// Zebu Helpdesk visual theme, aligned to the **Mynt Plus** design system:
/// the Mynt brand blue (`#0037B7`), Inter typeface, profit-green / loss-red
/// semantic colors, light grey app background, and 8/12 component radii.
class AppTheme {
  AppTheme._();

  // --- Brand (Mynt Plus `AppColors.primary` family) -------------------------
  static const Color brand = Color(0xFF0037B7); // Mynt brand blue (light)
  static const Color brandDark = Color(0xFF002E9B); // primaryVariant (light)
  // Dark mode brand tone — GitHub Dark accent (`#2F81F7`). Reads with strong
  // contrast against the near-black `canvas-default` surface.
  static const Color brandLight = Color(0xFF2F81F7);
  static const Color brandDarkHover = Color(0xFF1F6FEB); // GH accent-hover

  // --- Semantic status colors (Mynt profit/loss/pending) --------------------
  static const Color open = Color(0xFF00B14F); // Mynt profit green
  static const Color closed = Color(0xFF737373); // Mynt secondary text grey
  static const Color overdue = Color(0xFFFF1717); // Mynt loss red
  static const Color warning = Color(0xFFFFB038); // Mynt pending amber

  // --- Surface / line tokens ------------------------------------------------
  static const Color _bgLight = Color(0xFFF8F9FA); // backgroundSecondary
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _textLight = Color(0xFF141414); // textPrimary
  static const Color _textMutedLight = Color(0xFF737373); // textSecondary
  static const Color _outlineLight = Color(0xFFDDE2E7); // divider
  static const Color _primaryContainerLight = Color(0xFFE3EDFA);

  // GitHub Dark surface stack — see MEMORY palette for the source variables.
  //   canvas-default (#0D1117) → scaffold bg
  //   canvas-overlay (#161B22) → cards, sheets, popovers
  //   text-primary   (#F0F6FC), text-secondary (#C9D1D9), text-muted (#8B949E)
  //   border-default (#30363D), border-muted   (#21262D)
  static const Color _bgDark = Color(0xFF0D1117);
  static const Color _surfaceDark = Color(0xFF161B22);
  static const Color _textDark = Color(0xFFF0F6FC);
  static const Color _textMutedDark = Color(0xFF8B949E);
  static const Color _outlineDark = Color(0xFF30363D);
  static const Color _outlineVariantDark = Color(0xFF21262D);
  static const Color _primaryContainerDark = Color(0xFF0C2D6B); // accent-subtle
  static const Color _onPrimaryContainerDark = Color(0xFF79C0FF); // link-hover

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    final scheme =
        ColorScheme.fromSeed(seedColor: brand, brightness: brightness).copyWith(
          primary: isLight ? brand : brandLight,
          onPrimary: Colors.white,
          primaryContainer: isLight
              ? _primaryContainerLight
              : _primaryContainerDark,
          onPrimaryContainer: isLight
              ? brandDark
              : _onPrimaryContainerDark,
          secondary: isLight
              ? const Color(0xFF0052CC)
              : brandLight, // GH accent doubles for secondary in dark
          error: isLight ? overdue : const Color(0xFFF85149), // GH danger
          surface: isLight ? _surfaceLight : _surfaceDark,
          onSurface: isLight ? _textLight : _textDark,
          onSurfaceVariant: isLight ? _textMutedLight : _textMutedDark,
          outline: isLight ? const Color(0xFFC7CDD4) : _outlineDark,
          outlineVariant: isLight ? _outlineLight : _outlineVariantDark,
        );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: isLight ? _bgLight : _bgDark,
    );

    return base.copyWith(
      textTheme: ZebuFonts.textTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: ZebuFonts.face(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.8)),
        ),
        color: scheme.surface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Light: Mynt searchBg (`#F9F9F9`). Dark: GitHub Dark `input-bg`
        // (`#0D1117`) — same tone as the scaffold so inputs sit *in* the
        // canvas rather than as a raised chip.
        fillColor: isLight
            ? const Color(0xFFF9F9F9)
            : _bgDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          // Light: Mynt brand. Dark: GitHub `focus-ring` / `input-border-focus`
          // (`#1F6FEB`).
          borderSide: BorderSide(
            color: isLight ? brand : brandDarkHover,
            width: 1.6,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Dark filled CTAs adopt GitHub's accent blue so they stay
          // on-palette with the surrounding dark surfaces.
          backgroundColor: isLight ? brand : brandLight,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: ZebuFonts.face(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isLight ? brand : brandLight,
          minimumSize: const Size.fromHeight(50),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: ZebuFonts.face(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isLight ? brand : brandLight,
          textStyle: ZebuFonts.face(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isLight ? brand : brandLight,
        foregroundColor: Colors.white,
      ),
      // Mynt Plus-style tabs: padded pill segments (no underline), grey
      // unselected labels, brand-colored selected label. Dark pill uses
      // GitHub `surface-3` (`#21262D`) so the indicator reads on the
      // near-black surface.
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: isLight ? const Color(0xFFF1F3F8) : const Color(0xFF21262D),
          borderRadius: BorderRadius.circular(10),
        ),
        labelColor: isLight ? brand : brandLight,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: ZebuFonts.face(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: ZebuFonts.face(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 1,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(
          ZebuFonts.face(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      // Instant route push/pop across every platform. Flutter's Material 3
      // default on desktop targets is a zoom + fade, which felt heavy for a
      // click-to-navigate helpdesk — this makes navigation feel like a
      // proper SPA (matching the slide-over detail panel's instant swap).
      // Only affects `Navigator.push`/`pop` animations — dialogs, snackbars,
      // and modal sheets keep their own transitions.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.linux: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.macOS: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.windows: _NoAnimationPageTransitionsBuilder(),
          TargetPlatform.fuchsia: _NoAnimationPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Resolve a hex string like `#e53935` to a [Color] (fallbacks to grey).
  static Color hexColor(
    String? hex, [
    Color fallback = const Color(0xFF666666),
  ]) {
    if (hex == null) return fallback;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }
}

/// Instant page transition — returns the incoming page unchanged, so route
/// pushes and pops swap with no motion or fade. Wired into [AppTheme] as
/// the app-wide [PageTransitionsTheme] builder so every route pushed via
/// `MaterialPage` (which is what `GoRoute(builder: …)` produces) inherits
/// it without touching the router.
///
/// Only affects `Navigator` page transitions — [showDialog],
/// [showModalBottomSheet], and other overlays keep their own transitions.
class _NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
