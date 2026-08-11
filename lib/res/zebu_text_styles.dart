import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'zebu_theme.dart';

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
///
/// Sizes are **fixed**. Mynt Plus Web multiplies every size by a viewport
/// scale factor (0.8× under 1000 px, 0.9× under 1300 px); that was ported
/// and then removed, because it dropped table cells to 10.4 px and captions
/// to 8.8 px on a small laptop — below what is comfortable to read in a grid
/// an agent stares at all day. A size here is the size that renders.

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
  static const double small = 12;

  // TABLE
  // Both at body size, matching the Mynt Plus Web position table: the header
  // is set apart by weight and tone, not by being smaller than its column.
  static const double tableHeader = 14;
  static const double tableCell = 14;

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
  }) => GoogleFonts.inter(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
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
}) => isDarkMode(context) ? dark : light;

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
}) {
  final resolved =
      color ??
      resolveThemeColor(
        context,
        light: lightColor ?? defaultLight,
        dark: darkColor ?? defaultDark,
      );

  return ZebuFonts.face(fontSize: size, fontWeight: weight, color: resolved);
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
  }) => _text(
    c,
    size: ZebuFonts.hero,
    weight: fontWeight ?? ZebuFonts.semiBold,
    defaultLight: ZebuTheme.textPrimaryLight,
    defaultDark: ZebuTheme.textPrimaryDark,
    color: color,
    darkColor: darkColor,
    lightColor: lightColor,
  );

  /// `PageHeader` title — "Tickets", "Saved queues".
  static TextStyle pageTitle(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) => _text(
    c,
    size: ZebuFonts.pageTitle,
    weight: fontWeight ?? ZebuFonts.semiBold,
    defaultLight: ZebuTheme.textPrimaryLight,
    defaultDark: ZebuTheme.textPrimaryDark,
    color: color,
    darkColor: darkColor,
    lightColor: lightColor,
  );

  /// Heading inside a card, panel, or dialog.
  static TextStyle sectionTitle(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) => _text(
    c,
    size: ZebuFonts.sectionTitle,
    weight: fontWeight ?? ZebuFonts.semiBold,
    defaultLight: ZebuTheme.textPrimaryLight,
    defaultDark: ZebuTheme.textPrimaryDark,
    color: color,
    darkColor: darkColor,
    lightColor: lightColor,
  );

  /// Small-caps group label above a run of rows ("VIEWS", "WORKSPACE").
  static TextStyle eyebrow(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) => _text(
    c,
    size: ZebuFonts.small,
    weight: fontWeight ?? ZebuFonts.semiBold,
    defaultLight: ZebuTheme.textSecondaryLight,
    defaultDark: ZebuTheme.textSecondaryDark,
    color: color,
    darkColor: darkColor,
    lightColor: lightColor,
  );

  // ---------------- BODY ----------------

  /// Default running text.
  static TextStyle body(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) => _text(
    c,
    size: ZebuFonts.body,
    weight: fontWeight ?? ZebuFonts.regular,
    defaultLight: ZebuTheme.textPrimaryLight,
    defaultDark: ZebuTheme.textPrimaryDark,
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
  }) => _text(
    c,
    size: ZebuFonts.body,
    weight: fontWeight ?? ZebuFonts.medium,
    defaultLight: ZebuTheme.textPrimaryLight,
    defaultDark: ZebuTheme.textPrimaryDark,
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
  }) => _text(
    c,
    size: ZebuFonts.small,
    weight: fontWeight ?? ZebuFonts.regular,
    defaultLight: ZebuTheme.textSecondaryLight,
    defaultDark: ZebuTheme.textSecondaryDark,
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
  }) => _text(
    c,
    size: ZebuFonts.small,
    weight: fontWeight ?? ZebuFonts.semiBold,
    defaultLight: ZebuTheme.textSecondaryLight,
    defaultDark: ZebuTheme.textSecondaryDark,
    color: color,
    darkColor: darkColor,
    lightColor: lightColor,
  );

  /// Small text carrying weight — labels, list-row titles.
  static TextStyle smallStrong(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) => _text(
    c,
    size: ZebuFonts.small,
    weight: fontWeight ?? ZebuFonts.semiBold,
    defaultLight: ZebuTheme.textPrimaryLight,
    defaultDark: ZebuTheme.textPrimaryDark,
    color: color,
    darkColor: darkColor,
    lightColor: lightColor,
  );

  // ---------------- TABLE ----------------

  /// Column header — muted, semibold, at body size.
  static TextStyle tableHeader(
    BuildContext c, {
    Color? color,
    Color? darkColor,
    Color? lightColor,
    FontWeight? fontWeight,
  }) => _text(
    c,
    size: ZebuFonts.tableHeader,
    weight: fontWeight ?? ZebuFonts.semiBold,
    defaultLight: ZebuTheme.textSecondaryLight,
    defaultDark: ZebuTheme.textSecondaryDark,
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
  }) => _text(
    c,
    size: ZebuFonts.tableCell,
    weight: fontWeight ?? ZebuFonts.medium,
    defaultLight: ZebuTheme.textPrimaryLight,
    defaultDark: ZebuTheme.textPrimaryDark,
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
  }) => _text(
    c,
    size: ZebuFonts.caption,
    weight: fontWeight ?? ZebuFonts.medium,
    defaultLight: ZebuTheme.textSecondaryLight,
    defaultDark: ZebuTheme.textSecondaryDark,
    color: color,
    darkColor: darkColor,
    lightColor: lightColor,
  ).withTabularNums();
}

/// Tabular figures — fixed-width digits so numbers in a column line up and
/// multi-digit counts don't jitter as they change. Apply to any style
/// rendering a number in a grid.
extension TabularNums on TextStyle {
  TextStyle withTabularNums() =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
