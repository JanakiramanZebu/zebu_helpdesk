import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'zebu_web_color_styles.dart';

/// Typography for the Zebu Helpdesk web target.
///
/// The **shape** of this API follows the Mynt Plus Web convention — static
/// methods taking a [BuildContext], with a `color` / `lightColor` +
/// `darkColor` / `fontWeight` override triple — so both codebases read the
/// same way. The **sizes** are this app's own: a helpdesk grid is denser
/// than a trading watchlist, so table text sits at 12.5–13 rather than 14,
/// and nothing defaults to bold.
///
/// Grown as screens are converted. If a screen needs a style that isn't
/// here, add it here rather than inlining a `TextStyle` at the call site —
/// that is how the old token file accumulated seventeen near-duplicates.

/// ===============================================================
/// FONT SYSTEM – single source of truth
/// ===============================================================
class ZebuFonts {
  // HEADERS
  static const double hero = 24;
  static const double pageTitle = 20;
  static const double sectionTitle = 16;

  // BODY
  static const double body = 14;
  static const double small = 13;

  // TABLE
  static const double tableHeader = 12.5;
  static const double tableCell = 13;

  // SMALL
  static const double caption = 10;
  static const double eyebrow = 11;

  // WEIGHTS
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  // ---------------- TYPEFACE ----------------
  // The two methods below are the *only* places the typeface is named.
  // Everything else — every style here, the Material theme, and the web
  // tree's text theme — routes through them, so swapping the family is a
  // two-line edit rather than a hunt through eleven call sites.
  //
  // To change the face:
  //   * another Google font — swap `GoogleFonts.inter` / `interTextTheme`
  //     for that family's pair;
  //   * a bundled font — drop the files in `assets/fonts/`, declare them in
  //     `pubspec.yaml`, and return `TextStyle(fontFamily: 'Name', …)` /
  //     `base.apply(fontFamily: 'Name')` instead.

  /// One text style in the app typeface.
  static TextStyle face({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      ).copyWith(fontFamilyFallback: _kEmojiFallbacks);

  /// A whole [TextTheme] in the app typeface, for `ThemeData.textTheme`.
  static TextTheme textTheme(TextTheme base) =>
      GoogleFonts.interTextTheme(base);
}

/// System color-emoji fallbacks, so glyphs Inter doesn't ship (emoji in
/// ticket threads, notes, the editor) render from the OS font instead of
/// showing as tofu. Order covers macOS, Windows, Linux/Web.
const _kEmojiFallbacks = <String>[
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Segoe UI Symbol',
  'Noto Color Emoji',
];

/// ===============================================================
/// RESPONSIVE FONT SCALING
/// ===============================================================
/// Ported from Mynt Plus Web so both apps render the same size at the same
/// viewport. Narrower screens shrink type to fit more rows on a laptop.
extension ResponsiveFontContext on BuildContext {
  double get fontScaleFactor {
    final width = MediaQuery.sizeOf(this).width;
    if (width < 1000) return 0.8;
    if (width < 1300) return 0.9;
    return 1.0;
  }
}

/// ===============================================================
/// THEME HELPERS
/// ===============================================================
/// Public because [ZebuColors] stores light and dark as flat sibling
/// constants with no resolution of its own — every surface, border, and
/// icon tint needs this same pairing outside of text.
bool isDarkMode(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color resolveThemeColor(
  BuildContext context, {
  required Color dark,
  required Color light,
}) =>
    isDarkMode(context) ? dark : light;

/// ===============================================================
/// CORE TEXT STYLE ENGINE (DO NOT DUPLICATE)
/// ===============================================================
///
/// Colour resolves in three steps: an explicit [color] wins; otherwise a
/// caller-supplied [lightColor]/[darkColor] pair; otherwise the style's own
/// default tone. That last step is what lets `ZebuTextStyles.tableHeader(c)`
/// be muted and `ZebuTextStyles.tableCell(c)` be primary with no argument.
TextStyle _text(
  BuildContext context, {
  required double size,
  required FontWeight weight,
  required Color defaultLight,
  required Color defaultDark,
  Color? color,
  Color? darkColor,
  Color? lightColor,
  double? height,
  double? letterSpacing,
}) {
  final resolved = color ??
      resolveThemeColor(
        context,
        light: lightColor ?? defaultLight,
        dark: darkColor ?? defaultDark,
      );

  return ZebuFonts.face(
    fontSize: size * context.fontScaleFactor,
    fontWeight: weight,
    color: resolved,
    height: height,
    letterSpacing: letterSpacing,
  );
}

/// ===============================================================
/// PUBLIC TEXT STYLES (SEMANTIC + STABLE)
/// ===============================================================
class ZebuTextStyles {
  // ---------------- HEADERS ----------------

  /// Dashboard greeting — the single largest text in the app.
  static TextStyle hero(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) =>
      _text(
        c,
        size: ZebuFonts.hero,
        weight: fontWeight ?? ZebuFonts.semiBold,
        defaultLight: ZebuColors.textPrimary,
        defaultDark: ZebuColors.textPrimaryDark,
        color: color,
        darkColor: darkColor,
        lightColor: lightColor,
        letterSpacing: -0.4,
        height: 1.2,
      );

  /// `PageHeader` title — "Tickets", "Saved queues".
  static TextStyle pageTitle(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) =>
      _text(
        c,
        size: ZebuFonts.pageTitle,
        weight: fontWeight ?? ZebuFonts.semiBold,
        defaultLight: ZebuColors.textPrimary,
        defaultDark: ZebuColors.textPrimaryDark,
        color: color,
        darkColor: darkColor,
        lightColor: lightColor,
        letterSpacing: -0.2,
      );

  /// Heading inside a card, panel, or dialog.
  static TextStyle sectionTitle(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) =>
      _text(
        c,
        size: ZebuFonts.sectionTitle,
        weight: fontWeight ?? ZebuFonts.semiBold,
        defaultLight: ZebuColors.textPrimary,
        defaultDark: ZebuColors.textPrimaryDark,
        color: color,
        darkColor: darkColor,
        lightColor: lightColor,
      );

  /// Small-caps group label above a run of rows ("VIEWS", "WORKSPACE").
  /// Wider tracking gives it an eyebrow feel without going to display size.
  static TextStyle eyebrow(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) =>
      _text(
        c,
        size: ZebuFonts.eyebrow,
        weight: fontWeight ?? ZebuFonts.semiBold,
        defaultLight: ZebuColors.textSecondary,
        defaultDark: ZebuColors.textSecondaryDark,
        color: color,
        darkColor: darkColor,
        lightColor: lightColor,
        letterSpacing: 0.8,
      );

  // ---------------- BODY ----------------

  /// Default running text.
  static TextStyle body(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) =>
      _text(
        c,
        size: ZebuFonts.body,
        weight: fontWeight ?? ZebuFonts.regular,
        defaultLight: ZebuColors.textPrimary,
        defaultDark: ZebuColors.textPrimaryDark,
        color: color,
        darkColor: darkColor,
        lightColor: lightColor,
      );

  /// Body at medium weight — names, values, anything that leads a row.
  static TextStyle bodyStrong(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) =>
      _text(
        c,
        size: ZebuFonts.body,
        weight: fontWeight ?? ZebuFonts.medium,
        defaultLight: ZebuColors.textPrimary,
        defaultDark: ZebuColors.textPrimaryDark,
        color: color,
        darkColor: darkColor,
        lightColor: lightColor,
      );

  /// Secondary text — subtitles, hints, metadata. Muted by default.
  static TextStyle small(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) =>
      _text(
        c,
        size: ZebuFonts.small,
        weight: fontWeight ?? ZebuFonts.regular,
        defaultLight: ZebuColors.textSecondary,
        defaultDark: ZebuColors.textSecondaryDark,
        color: color,
        darkColor: darkColor,
        lightColor: lightColor,
      );

  /// Muted label — field captions, group headings inside a card, the left
  /// column of a key/value pair. Same size and weight as [smallStrong] but
  /// toned back, so a label never competes with the value beside it.
  static TextStyle label(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) =>
      _text(
        c,
        size: ZebuFonts.small,
        weight: fontWeight ?? ZebuFonts.semiBold,
        defaultLight: ZebuColors.textSecondary,
        defaultDark: ZebuColors.textSecondaryDark,
        color: color,
        darkColor: darkColor,
        lightColor: lightColor,
        letterSpacing: 0.2,
      );

  /// Small text carrying weight — labels, list-row titles.
  static TextStyle smallStrong(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) =>
      _text(
        c,
        size: ZebuFonts.small,
        weight: fontWeight ?? ZebuFonts.semiBold,
        defaultLight: ZebuColors.textPrimary,
        defaultDark: ZebuColors.textPrimaryDark,
        color: color,
        darkColor: darkColor,
        lightColor: lightColor,
      );

  // ---------------- TABLE ----------------

  /// Column header. Muted and medium — the grid's structure should come
  /// from the header strip's fill, not from heavy type.
  static TextStyle tableHeader(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) =>
      _text(
        c,
        size: ZebuFonts.tableHeader,
        weight: fontWeight ?? ZebuFonts.medium,
        defaultLight: ZebuColors.textSecondary,
        defaultDark: ZebuColors.textSecondaryDark,
        color: color,
        darkColor: darkColor,
        lightColor: lightColor,
      );

  /// Body cell.
  static TextStyle tableCell(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) =>
      _text(
        c,
        size: ZebuFonts.tableCell,
        weight: fontWeight ?? ZebuFonts.medium,
        defaultLight: ZebuColors.textPrimary,
        defaultDark: ZebuColors.textPrimaryDark,
        color: color,
        darkColor: darkColor,
        lightColor: lightColor,
      );

  // ---------------- SMALL ----------------

  /// Tiny metadata under a value, count pills, timestamps.
  static TextStyle caption(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) =>
      _text(
        c,
        size: ZebuFonts.caption,
        weight: fontWeight ?? ZebuFonts.medium,
        defaultLight: ZebuColors.textSecondary,
        defaultDark: ZebuColors.textSecondaryDark,
        color: color,
        darkColor: darkColor,
        lightColor: lightColor,
        height: 1.2,
      );
}

/// Tabular figures — fixed-width digits so numbers in a column line up and
/// multi-digit counts don't jitter as they change. Apply to any style
/// rendering a number in a grid.
extension TabularNums on TextStyle {
  TextStyle withTabularNums() =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
