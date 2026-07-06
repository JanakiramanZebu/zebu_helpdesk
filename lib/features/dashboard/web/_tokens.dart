import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// System color-emoji font fallbacks. Applied to every token text style so
/// emoji glyphs render from the OS font when the primary sans face (Geist)
/// doesn't ship them — avoids tofu boxes in threads, notes, and the editor.
const _kEmojiFallbacks = <String>[
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Segoe UI Symbol',
  'Noto Color Emoji',
];

/// Zebu Premium design tokens for web. Direct Flutter port of the CSS
/// variables and patterns defined in `skill.md` (see project root). All
/// colors resolve light/dark off the ambient [Brightness], so any web
/// screen that reads tokens via [WebTokens.of] will track theme mode for
/// free. Mobile screens never import this — it lives under `web/`.
class WebTokens {
  WebTokens._(this.brightness);
  final Brightness brightness;
  bool get isLight => brightness == Brightness.light;

  static WebTokens of(BuildContext context) =>
      WebTokens._(Theme.of(context).brightness);

  // --- Accent (Mynt brand blue) -------------------------------------------
  static const accent = Color(0xFF0037B7);
  static const accentHover = Color(0xFF002E9B);
  Color get accentMuted => isLight
      ? const Color(0xFFE3EDFA)
      : const Color(0xFF1D242F);
  Color get accentSoft => isLight
      ? const Color(0xFFEFF4FC)
      : const Color(0xFF15202F);

  // --- Backgrounds ---------------------------------------------------------
  // Light page bg: `#F7F7F4` — a hair warm off-white so the content area
  // reads as paper against the crisp-white cards + sidebar rather than as a
  // flat cool gray plate. Same brightness as the previous `#F8F9FA` (~97 %)
  // so contrast with cards is preserved. Dark bg unchanged.
  Color get bgPrimary =>
      isLight ? const Color(0xFFFDFDFF) : const Color(0xFF0E0E10);
  Color get bgSecondary =>
      isLight ? const Color(0xFFFFFFFF) : const Color(0xFF15151A);
  Color get bgTertiary =>
      isLight ? const Color(0xFFF1F3F8) : const Color(0xFF1A1A20);
  Color get bgElevated =>
      isLight ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A20);
  Color get bgHover =>
      isLight ? const Color(0xFFEEF1F6) : const Color(0xFF22222B);

  // --- Borders -------------------------------------------------------------
  // Hairline border matches DESIGN_SYSTEM.md `--color-border: #DDE2E7`
  // (previously #E5E9F0, a hair lighter). The design also identifies
  // `#C7CDD4` as a stronger "outline" — kept on `borderStrong` below.
  Color get borderSubtle =>
      isLight ? const Color(0x84DDE2E7) : const Color(0xFF26262E);
  Color get borderDefault =>
      isLight ? const Color(0xFFDDE2E7) : const Color(0xFF333341);
  Color get borderStrong =>
      isLight ? const Color(0xFFC7CDD4) : const Color(0xFF4A4A55);

  // --- Text ----------------------------------------------------------------
  // skill.md restricts body text to two colors: primary and secondary.
  // The old `--text-muted` token is removed — use [textSecondary] instead.
  Color get textPrimary =>
      isLight ? const Color(0xFF141414) : const Color(0xFFFAFAFA);
  Color get textSecondary =>
      isLight ? const Color(0xFF565C68) : const Color(0xFFB0B5BD);
  static const textInverse = Colors.white;

  // --- Semantic ------------------------------------------------------------
  static const success = Color(0xFF00B14F);
  Color get successLight =>
      isLight ? const Color(0xFFE6F8EE) : const Color(0xFF132B1C);
  static const danger = Color(0xFFFF1717);
  Color get dangerLight =>
      isLight ? const Color(0xFFFDE7E7) : const Color(0xFF311616);
  static const warning = Color(0xFFFFB038);
  Color get warningLight =>
      isLight ? const Color(0xFFFFF4E0) : const Color(0xFF2C2316);
  static const info = Color(0xFF0052CC);
  Color get infoLight =>
      isLight ? const Color(0xFFE3EDFA) : const Color(0xFF1D242F);

  // --- Spacing (px, mirrors --space-* tokens) ------------------------------
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s10 = 40.0;

  // --- Radius --------------------------------------------------------------
  // Scale aligned to DESIGN_SYSTEM.md:
  //   sm=8  buttons, inputs, chips, status pills
  //   md=10 search field, tab indicator
  //   lg=12 cards, icon badges
  //   xl=14 snackbars
  //   2xl=16 stat tiles, nav pills
  //   3xl=18 dialogs
  // rXs (6) is smaller than any design token and reserved for tiny inline
  // chips where 8 would look chunky.
  static const rXs = 6.0;
  static const rSm = 8.0;
  static const rMd = 10.0;
  static const rLg = 12.0;
  static const rXl = 14.0;
  static const r2xl = 16.0;
  static const r3xl = 18.0;
  static const rFull = 999.0;

  // --- Shadows -------------------------------------------------------------
  /// Whisper-quiet card lift — barely visible, just enough to detach the
  /// surface from the page bg. Used at rest on premium cards + KPI tiles so
  /// the dashboard reads as a layered composition instead of a flat wall of
  /// hairline outlines. Hovered / active states step up to [shadowSm].
  static const shadowXs = <BoxShadow>[
    BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 1)),
  ];
  static const shadowSm = <BoxShadow>[
    BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const shadowMd = <BoxShadow>[
    BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const shadowLg = <BoxShadow>[
    BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// Soft accent glow used on selected/active cards.
  static const accentGlow = <BoxShadow>[
    BoxShadow(
      color: Color(0x14002677), // rgba(0, 55, 183, ~8%)
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
  ];

  /// Two-layer soft drop shadow for floating menus / popovers. Kept softer
  /// than a Material `elevation: 8` so it reads as a premium overlay rather
  /// than a plate.
  static const popoverShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x14000000), // rgba(0,0,0,.08)
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x0A000000), // rgba(0,0,0,.04)
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  // --- Typography ----------------------------------------------------------
  // All sans-serif text uses Inter — the family called out globally in
  // DESIGN_SYSTEM.md. (Previously Geist; the design system doc treats Inter
  // as the single source of truth for both mobile and web.) Numeric values
  // that need column alignment should call `withTabularNums` on the returned
  // style.
  //
  // `fontFamilyFallback` lists the system color-emoji families so glyphs the
  // Inter face doesn't ship (emoji, misc symbols) render from the OS font
  // instead of showing as tofu. Order covers macOS, Windows, and Linux/Web.
  TextStyle _sans(
    double size,
    FontWeight weight, {
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color ?? textPrimary,
      height: height,
      letterSpacing: letterSpacing,
    ).copyWith(fontFamilyFallback: _kEmojiFallbacks);
  }

  // Per skill.md hard constraints: min size = 13px, weight ∈ {400, 500, 600},
  // text color ∈ {textPrimary, textSecondary, accent, semantic}. Numeric
  // values still get tabular-nums + tight tracking to stay visually prominent
  // without going heavier than 600.
  TextStyle get hero =>
      _sans(24, FontWeight.w600, letterSpacing: -0.4, height: 1.2);
  TextStyle get pageTitle => _sans(20, FontWeight.w600, letterSpacing: -0.2);
  TextStyle get sectionTitle => _sans(
    13,
    FontWeight.w600,
    color: textSecondary,
    letterSpacing: 0.2, // ~0.015em at 13px — soft tracking, not "wide caps"
  );
  // Small-caps header used to introduce a group inside popovers / cards,
  // ClickUp-style. Slightly wider tracking gives the label an "eyebrow"
  // feel without going into all-caps display sizes.
  TextStyle get sectionCaps => _sans(
    11,
    FontWeight.w600,
    color: textSecondary,
    letterSpacing: 0.8,
  );
  TextStyle get cardName => _sans(13, FontWeight.w600);
  TextStyle get cardNameLg => _sans(14, FontWeight.w600);
  TextStyle get tinyLabel => _sans(
    13,
    FontWeight.w600,
    color: textSecondary,
    letterSpacing: 0.2, // matches sectionTitle
  );
  // Table column header — Title Case labels at medium weight so headers
  // read distinct from body rows without going semibold. Sits on the white
  // `bgElevated` header strip in every _TableHeader across the web target.
  TextStyle get tableHeader => _sans(
    12.5,
    FontWeight.w500,
    color: textSecondary,
    letterSpacing: 0,
  );
  TextStyle get bodySm => _sans(13, FontWeight.w400, color: textSecondary);
  TextStyle get bodyBase => _sans(14, FontWeight.w400);
  TextStyle get label => _sans(13, FontWeight.w600, color: textSecondary);

  TextStyle valueProminent(Color color) => _sans(
    15,
    FontWeight.w600,
    color: color,
    letterSpacing: -0.3,
  ).withTabularNums();
  TextStyle valueMedium(Color color) => _sans(
    18,
    FontWeight.w600,
    color: color,
    letterSpacing: -0.3,
  ).withTabularNums();
  TextStyle valueLarge(Color color) => _sans(
    24,
    FontWeight.w600,
    color: color,
    letterSpacing: -0.5,
  ).withTabularNums();

  // --- Card decorations ----------------------------------------------------
  BoxDecoration card({bool hover = false, bool selected = false}) {
    if (selected) {
      return BoxDecoration(
        color: accentMuted,
        borderRadius: BorderRadius.circular(rMd),
        border: Border.all(color: accent, width: 1),
        boxShadow: accentGlow,
      );
    }
    return BoxDecoration(
      color: bgElevated,
      borderRadius: BorderRadius.circular(rMd),
      border: Border.all(
        color: hover ? borderDefault : borderSubtle,
        width: 1,
      ),
      boxShadow: hover ? shadowSm : null,
    );
  }

  /// Elevated white surface used for floating menus / popovers. Uses the
  /// two-layer [popoverShadow] instead of a flat card border-only look, so
  /// the overlay reads as lifted off the page.
  BoxDecoration cardElevated() {
    return BoxDecoration(
      color: bgElevated,
      borderRadius: BorderRadius.circular(rLg),
      border: Border.all(color: borderSubtle, width: 1),
      boxShadow: popoverShadow,
    );
  }

  /// Info-card variant from skill.md — `bg-tertiary` fill with a uniform
  /// subtle border. The 3 px accent left strip is rendered separately by
  /// the consuming widget (a non-uniform [Border] would silently drop the
  /// [borderRadius] in Flutter's painter).
  BoxDecoration cardAccent({bool hover = false}) {
    return BoxDecoration(
      color: bgTertiary,
      borderRadius: BorderRadius.circular(rMd),
      border: Border.all(
        color: hover ? borderDefault : borderSubtle,
        width: 1,
      ),
      boxShadow: hover ? shadowSm : null,
    );
  }
}

extension TabularNums on TextStyle {
  TextStyle withTabularNums() =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
