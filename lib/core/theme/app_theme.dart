import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Zebu Helpdesk visual theme, aligned to the **Mynt Plus** design system:
/// the Mynt brand blue (`#0037B7`), Inter typeface, profit-green / loss-red
/// semantic colors, light grey app background, and 8/12 component radii.
class AppTheme {
  AppTheme._();

  // --- Brand (Mynt Plus `AppColors.primary` family) -------------------------
  static const Color brand = Color(0xFF0037B7); // Mynt brand blue
  static const Color brandDark = Color(0xFF002E9B); // primaryVariant
  static const Color brandLight = Color(0xFF4A6CF7); // primaryLight

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

  static const Color _bgDark = Color(0xFF181818);
  static const Color _surfaceDark = Color(0xFF1A1A1A);
  static const Color _textMutedDark = Color(0xFF8A8A8A);
  static const Color _outlineDark = Color(0xFF333333);

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
              : const Color(0xFF1D242F),
          onPrimaryContainer: isLight ? brandDark : _primaryContainerLight,
          secondary: const Color(0xFF0052CC),
          error: isLight ? overdue : const Color(0xFFFF6B6B),
          surface: isLight ? _surfaceLight : _surfaceDark,
          onSurface: isLight ? _textLight : Colors.white,
          onSurfaceVariant: isLight ? _textMutedLight : _textMutedDark,
          outline: isLight ? const Color(0xFFC7CDD4) : const Color(0xFF4A4A4A),
          outlineVariant: isLight ? _outlineLight : _outlineDark,
        );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: isLight ? _bgLight : _bgDark,
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      // Use the modern, lighter Material 3 "fade forwards" page transition on
      // every platform — smoother and less janky than the default zoom on
      // lower-end Android.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: GoogleFonts.inter(
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
        fillColor: isLight
            ? const Color(0xFFF9F9F9) // Mynt searchBg
            : const Color(0xFF1E1E1E), // Mynt searchBgDark
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
          borderSide: const BorderSide(color: brand, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.inter(
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
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: isLight ? brand : brandLight,
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brand,
        foregroundColor: Colors.white,
      ),
      // Mynt Plus-style tabs: padded pill segments (no underline), grey
      // unselected labels, brand-colored selected label.
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: isLight ? const Color(0xFFF1F3F8) : const Color(0xFF24242B),
          borderRadius: BorderRadius.circular(10),
        ),
        labelColor: isLight ? brand : brandLight,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: GoogleFonts.inter(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(
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
          GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      // Jira/Asana/ClickUp-style modal sheets: large 24px top radius, flat
      // surface fill and a dimmed scrim. The built-in drag handle is left off
      // here because it reserves a fixed 48px touch-target box (only its
      // colour/size are themeable, not that height) — AppSheet draws its own
      // compact grabber instead. Sheets that opt in explicitly still get one.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surface,
        modalBarrierColor: Colors.black.withValues(alpha: isLight ? 0.32 : 0.55),
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.35),
        dragHandleSize: const Size(36, 4),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      // Floating, rounded, surface-toned SnackBars in Inter — the on-brand base
      // for any bar not built via the AppSnack helper.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? const Color(0xFF232A34) : _surfaceDark,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
        actionTextColor: brandLight,
        elevation: 6,
        insetPadding: const EdgeInsets.fromLTRB(12, 5, 12, 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      // On-brand date picker: rounded surface card, brand-blue header + selected
      // day, Inter typography, brand-tinted "today" ring and action buttons.
      datePickerTheme: DatePickerThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        headerBackgroundColor: isLight ? brand : brandLight,
        headerForegroundColor: Colors.white,
        headerHeadlineStyle: GoogleFonts.inter(
          fontSize: 30,
          fontWeight: FontWeight.w700,
        ),
        headerHelpStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        weekdayStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: scheme.onSurfaceVariant,
        ),
        dayStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : scheme.onSurface,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? brand : null,
        ),
        todayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : brand,
        ),
        todayBorder: const BorderSide(color: brand, width: 1.4),
        yearStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500),
        yearForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : scheme.onSurface,
        ),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? brand : null,
        ),
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: isLight ? brand : brandLight,
        ),
      ),
      // Matching on-brand time picker.
      timePickerTheme: TimePickerThemeData(
        backgroundColor: scheme.surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        dialBackgroundColor: isLight
            ? const Color(0xFFF1F3F8)
            : const Color(0xFF24242B),
        dialHandColor: brand,
        hourMinuteColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isLight ? _primaryContainerLight : const Color(0xFF1D242F))
              : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isLight ? brand : brandLight)
              : scheme.onSurface,
        ),
        hourMinuteTextStyle: GoogleFonts.inter(
          fontSize: 44,
          fontWeight: FontWeight.w600,
        ),
        dayPeriodColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isLight ? _primaryContainerLight : const Color(0xFF1D242F))
              : Colors.transparent,
        ),
        dayPeriodTextColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? (isLight ? brand : brandLight)
              : scheme.onSurfaceVariant,
        ),
        dayPeriodBorderSide: BorderSide(color: scheme.outlineVariant),
        helpTextStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
        confirmButtonStyle: TextButton.styleFrom(
          foregroundColor: isLight ? brand : brandLight,
        ),
        cancelButtonStyle: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Accent color for a priority name (high/emergency = red, low = grey,
  /// else amber). Used for the left accent bar on list cards. Falls back to a
  /// neutral outline tone when no priority is set.
  static Color priorityAccent(String? priority, ColorScheme scheme) {
    if (priority == null || priority.isEmpty) return scheme.outlineVariant;
    final p = priority.toLowerCase();
    if (p.contains('emergency') || p.contains('high')) return overdue;
    if (p.contains('low')) return closed;
    return warning;
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
