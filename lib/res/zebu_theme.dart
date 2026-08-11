import 'package:flutter/material.dart';

import 'zebu_spacing.dart';
import 'zebu_web_color_styles.dart';

/// Brightness-resolving façade over [ZebuColors].
///
/// [ZebuColors] is a flat palette — `card` and `cardDark` sit side by side as
/// constants with no notion of which one applies. This class is the layer
/// that picks, so a screen writes `t.bgElevated` and gets the right tone for
/// the ambient theme.
///
/// Getter names are inherited from the `WebTokens` class this replaces, on
/// purpose: it kept roughly a thousand call sites from needing an edit during
/// the migration. Where [ZebuColors] has no equivalent — the tinted semantic
/// backgrounds, `borderStrong`, `accentSoft` — the previous value is kept
/// inline and marked below.
class ZebuTheme {
  ZebuTheme._(this.brightness);
  final Brightness brightness;
  bool get isLight => brightness == Brightness.light;

  // Only two possible instances, and every value is immutable, so cache one
  // per brightness. `of(context)` is then an O(1) lookup returning a shared
  // object rather than allocating per build.
  static final ZebuTheme _light = ZebuTheme._(Brightness.light);
  static final ZebuTheme _dark = ZebuTheme._(Brightness.dark);

  static ZebuTheme of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? _light : _dark;

  // --- Accent ---------------------------------------------------------------
  static const accentLight = ZebuColors.primary;
  static const accentDark = ZebuColors.primaryDark;

  // No hover pair in the palette — these are the app's own deepened steps.
  static const accentHoverLight = Color(0xFF002E9B);
  static const accentHoverDark = Color(0xFF1F6FEB);

  Color get accent => isLight ? accentLight : accentDark;
  Color get accentHover => isLight ? accentHoverLight : accentHoverDark;

  /// Selected-row / active-chip wash.
  Color get accentMuted =>
      isLight ? ZebuColors.selectedBg : ZebuColors.selectedBgDark;

  /// A whisper of accent — lighter than [accentMuted], for unread rows and
  /// hover fills that should not read as selected. No palette equivalent.
  Color get accentSoft =>
      isLight ? const Color(0xFFEFF4FC) : const Color(0x1F2F81F7);

  /// Secondary identity tint — the "mine" view dot, matching mobile.
  static const indigo = Color(0xFF6366F1);

  /// Internal-only content: notes in the composer and the thread.
  ///
  /// A note never leaves the team, while a reply is emailed to the customer,
  /// so the two must not look alike. Purple because it is the one hue not
  /// already spoken for — amber means High priority, indigo means Answered,
  /// green Resolved, red Escalated — and "private / internal" reads as
  /// purple across most tools.
  static const noteLight = Color(0xFF7C3AED);
  static const noteDark = Color(0xFFA78BFA);
  Color get note => isLight ? noteLight : noteDark;

  LinearGradient get brandGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isLight
        ? const [Color(0xFF4A6CF7), ZebuColors.primary]
        : const [Color(0xFF2F81F7), ZebuColors.primary],
  );

  LinearGradient get brandGradientHover => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isLight
        ? const [Color(0xFF3F5FE8), accentHoverLight]
        : const [Color(0xFF1F6FEB), accentHoverLight],
  );

  // --- Backgrounds ----------------------------------------------------------
  /// The screen surface every routed page paints — the area inside the
  /// workspace card.
  ///
  /// White in light mode. That means [bgElevated] cards sitting on it are
  /// also white, so they separate by hairline and `shadowXs` rather than by
  /// fill. Dark mode still layers by fill (`#0D0F11` page vs `#161B22` card).
  Color get bgPrimary =>
      isLight ? ZebuColors.backgroundColor : ZebuColors.backgroundColorDark;
  Color get bgSecondary => isLight ? ZebuColors.card : ZebuColors.cardDark;
  Color get bgElevated => isLight ? ZebuColors.card : ZebuColors.cardDark;
  Color get bgTertiary =>
      isLight ? ZebuColors.listItemBg : ZebuColors.listItemBgDark;
  Color get bgHover =>
      isLight ? ZebuColors.cardHover : ZebuColors.cardHoverDark;

  // --- Borders --------------------------------------------------------------
  Color get borderSubtle =>
      isLight ? ZebuColors.borderMuted : ZebuColors.borderMutedDark;
  Color get borderDefault =>
      isLight ? ZebuColors.divider : ZebuColors.dividerDark;

  /// Strong hairline for controls that must stand off their surface. No
  /// palette equivalent.
  Color get borderStrong =>
      isLight ? const Color(0xFFC7CDD4) : const Color(0xFF3D444D);

  // --- Text -----------------------------------------------------------------
  //
  // These four are deliberately *not* taken from [ZebuColors]. The palette's
  // tones (`#121212` / `#4A4A4A`, and dimmer darks) made secondary text —
  // which is most of a table row: requester, department, dates, column
  // headers — read noticeably darker and warmer than this app had it, and
  // the whole page got heavier. These are the values the helpdesk was built
  // and tuned against: a cooler, lighter grey-blue for muted text.
  static const textPrimaryLight = Color(0xFF141414);
  static const textPrimaryDark = Color(0xFFF0F6FC);
  static const textSecondaryLight = Color(0xFF565C68);
  static const textSecondaryDark = Color(0xFFC9D1D9);

  Color get textPrimary => isLight ? textPrimaryLight : textPrimaryDark;
  Color get textSecondary => isLight ? textSecondaryLight : textSecondaryDark;
  static const textInverse = ZebuColors.textWhite;

  // --- Slate surfaces & tones -----------------------------------------------
  //
  // A cooler, quieter family than the neutral greys above, taken from the
  // approved ticket-panel design and now shared: the field-glyph tiles, the
  // view tabs, and anything else that should recede behind its content.
  //
  // These are deliberately separate from [bgTertiary] / [textSecondary] —
  // those are the app's neutral greys, these carry a blue cast.

  /// Muted chip / tile fill — field-glyph tiles, idle tab hover.
  Color get surfaceMuted =>
      isLight ? const Color(0xFFF5F6F9) : const Color(0xFF21262D);

  /// One step up from [surfaceMuted], for the same element when its row is
  /// hovered or it is the selected tab. Without the step, a tile sitting on
  /// a hovered row dissolves into it — they are a unit apart per channel.
  Color get surfaceMutedStrong =>
      isLight ? const Color(0xFFE8EBF0) : const Color(0xFF30363D);

  /// Glyph tint on [surfaceMuted].
  Color get iconMuted =>
      isLight ? const Color(0xFF64708A) : const Color(0xFF8B949E);

  /// Label text in the slate family.
  Color get textSlateMuted =>
      isLight ? const Color(0xFF596278) : const Color(0xFF8B949E);

  /// Value text in the slate family.
  Color get textSlate =>
      isLight ? const Color(0xFF34465E) : const Color(0xFFC9D1D9);

  /// Values that open a picker or link out.
  Color get linkSlate =>
      isLight ? const Color(0xFF1554C7) : const Color(0xFF58A6FF);

  /// Hairline in the slate family.
  Color get dividerSlate =>
      isLight ? const Color(0xFFE8EBF0) : const Color(0xFF21262D);

  // --- Semantic -------------------------------------------------------------
  static const success = ZebuColors.profit;
  static const warning = ZebuColors.warning;
  static const info = ZebuColors.secondary;
  static const dangerBrandLight = ZebuColors.loss;
  static const dangerBrandDark = ZebuColors.lossDark;

  Color get danger => isLight ? dangerBrandLight : dangerBrandDark;

  // Tinted semantic backgrounds — the palette carries only the foreground
  // tones, so these fills stay as the app defined them.
  Color get successLight =>
      isLight ? const Color(0xFFE6F8EE) : const Color(0xFF12261E);
  Color get dangerLight =>
      isLight ? const Color(0xFFFDE7E7) : const Color(0xFF2D1117);
  Color get warningLight =>
      isLight ? const Color(0xFFFFF4E0) : const Color(0xFF341A00);
  Color get infoLight =>
      isLight ? const Color(0xFFE3EDFA) : const Color(0xFF0C2D6B);

  // --- Card decorations -----------------------------------------------------
  BoxDecoration card({bool hover = false, bool selected = false}) {
    if (selected) {
      return BoxDecoration(
        color: accentMuted,
        borderRadius: BorderRadius.circular(ZebuRadius.rMd),
        border: Border.all(color: accent, width: 1),
      );
    }
    // Rest-state whisper shadow + hairline so cards feel lifted off the page.
    // Hover steps up for a tactile press-in-place cue without a transform.
    return BoxDecoration(
      color: bgElevated,
      borderRadius: BorderRadius.circular(ZebuRadius.rMd),
      border: Border.all(
        color: hover ? borderDefault : borderSubtle,
        width: 1,
      ),
      boxShadow: hover ? ZebuElevation.shadowSm : ZebuElevation.shadowXs,
    );
  }

  /// Floating menu / popover surface — two-layer shadow rather than a
  /// border-only look, so the overlay reads as lifted off the page.
  BoxDecoration cardElevated() => BoxDecoration(
    color: bgElevated,
    borderRadius: BorderRadius.circular(ZebuRadius.rLg),
    border: Border.all(color: borderSubtle, width: 1),
    boxShadow: ZebuElevation.popoverShadow,
  );

  /// Info-card variant — `bgTertiary` fill with a uniform subtle border. Any
  /// accent left-strip is painted separately by the consuming widget, because
  /// a non-uniform [Border] silently drops [BoxDecoration.borderRadius] in
  /// Flutter's painter.
  BoxDecoration cardAccent({bool hover = false}) => BoxDecoration(
    color: bgTertiary,
    borderRadius: BorderRadius.circular(ZebuRadius.rMd),
    border: Border.all(
      color: hover ? borderDefault : borderSubtle,
      width: 1,
    ),
    boxShadow: hover ? ZebuElevation.shadowSm : null,
  );
}
