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
  /// so the two must not look alike. Burnt amber rather than the purple this
  /// used to be, matching the hatched note card in the thread — the composer
  /// and the thread must agree, or the same concept wears two colours one
  /// scroll apart. Distinct from [warning] (`#FFB038`, High priority): far
  /// darker and lower-chroma, so it reads as ink, not as a status.
  static const noteLight = Color(0xFF9A4B06);
  static const noteDark = Color(0xFFE0A96D);
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

  // --- Thread bubble fills -------------------------------------------------
  // Three fills for the ticket / task conversation, one per osTicket thread
  // type. Kept here rather than in the panels because the ticket thread and
  // the task thread render the same entries and must not drift apart.
  //
  // All three are pale enough that body copy keeps full contrast against
  // them — the fill says *who*, the text stays the text.

  /// The scroll area behind the bubbles. Plain white in light mode: both
  /// sides now carry their own fill, so the canvas no longer has to be tinted
  /// to make one of them visible. Asking an off-white canvas to hold a white
  /// bubble apart puts the whole layout on a one-unit difference, which is
  /// the first thing lost to a cheap monitor or a bright room.
  Color get threadCanvas =>
      isLight ? const Color(0xFFFFFFFF) : const Color(0xFF0D1117);

  /// Inbound — a message from the requester. Neutral grey against the reply's
  /// blue: the pair reads at a glance without either side depending on the
  /// canvas to define it.
  Color get bubbleInbound =>
      isLight ? const Color(0xFFF2F4F7) : const Color(0xFF21262D);
  Color get bubbleInboundBorder =>
      isLight ? const Color(0xFFE6E9EF) : const Color(0xFF30363D);

  /// Message body ink — the app's primary text tone, not the softer grey used
  /// for long-form copy. A ticket thread is correspondence, not an article:
  /// the message *is* the content, so it reads at full strength, the way
  /// Gmail and Slack set message text. Near-black rather than pure black —
  /// `#000` on white makes letters vibrate and is tiring over a long thread.
  Color get bubbleInboundInk => textPrimary;

  /// Outbound — a staff reply that was emailed to the customer. Brand-tinted,
  /// with ink deep enough to stay readable on the tint rather than the
  /// default body grey, which goes muddy on blue.
  Color get bubbleOutbound =>
      isLight ? const Color(0xFFEEF2FD) : const Color(0xFF16263C);
  Color get bubbleOutboundBorder =>
      isLight ? const Color(0xFFDBE3FB) : const Color(0xFF1F3A5F);

  /// Deliberately the same neutral as [bubbleInboundInk], not a navy tinted
  /// to match the fill. Blue ink on a blue fill is the callout/quote
  /// convention — every docs site uses it for "Note:" boxes — so a reply
  /// stopped reading as something a person said and started reading as a
  /// quoted block. The tint already says who wrote it; the letters only have
  /// to be read. Kept as its own token so it can diverge again if the fill
  /// ever darkens enough to need it.
  Color get bubbleOutboundInk => bubbleInboundInk;

  // --- Internal note -------------------------------------------------------
  // A note never leaves the building, and sending one to a customer by
  // mistake is the worst thing this screen can do. So a note is deliberately
  // *not* a chat bubble: it spans the full column, carries a diagonal hatch
  // and a dashed edge, and states the consequence in its label. Hatching is
  // the one texture nothing else in the app uses — it survives being
  // recognised out of the corner of the eye.

  /// The two bands of the 45° hatch.
  Color get noteHatchBase =>
      isLight ? const Color(0xFFFFFAF1) : const Color(0xFF221B10);
  Color get noteHatchStripe =>
      isLight ? const Color(0xFFFEF6E7) : const Color(0xFF2A2114);

  /// Dashed edge of the note card.
  Color get noteBorder =>
      isLight ? const Color(0xFFE8CFA3) : const Color(0xFF5C4A2A);

  /// Note body copy — warm-shifted, not the neutral body grey.
  Color get noteBody =>
      isLight ? const Color(0xFF5C4A2A) : const Color(0xFFD9C9A8);

  /// Tinted circle behind a note author's initials.
  Color get noteAvatarBg =>
      isLight ? const Color(0xFFFDF1DC) : const Color(0xFF3A2E18);

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
      border: Border.all(color: hover ? borderDefault : borderSubtle, width: 1),
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
    border: Border.all(color: hover ? borderDefault : borderSubtle, width: 1),
    boxShadow: hover ? ZebuElevation.shadowSm : null,
  );
}
