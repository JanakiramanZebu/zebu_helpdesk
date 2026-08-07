import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../res/zebu_theme.dart';
import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';

/// Premium KPI card — the primary read across the top of the web dashboard.
///
/// Anatomy (Linear / ClickUp reference):
///   * a tone-tinted rounded icon badge, top-left;
///   * a small hover-revealed "open" chevron, top-right — signals the whole
///     card is a click target into the matching filtered list;
///   * a large tabular value, the hero of the card;
///   * a muted label beneath it;
///   * an honest ratio strip at the bottom (a proportional bar + "X of Y"
///     caption) built from real `ReportSummary` numbers — no invented trend.
///
/// Hover lifts the card in place: the border deepens, the whisper shadow
/// steps up, the icon tint warms, and the chevron fades in. Every change
/// rides one 160 ms [Curves.easeOut] so the feedback reads as a single
/// continuous motion, never a "pop".
///
/// Sizing is fluid so the card fills whatever slot the responsive grid gives
/// it (4 / 2 / 1 columns on the dashboard).
class KpiTile extends StatefulWidget {
  const KpiTile({
    super.key,
    required this.svg,
    this.svgAsset,
    required this.value,
    required this.label,
    required this.tone,
    this.onTap,
    this.current,
    this.denominator,
    this.denominatorLabel,
  });

  /// Raw SVG markup rendered via [SvgPicture.string]. Painted with a
  /// [ColorFilter.mode] tinted to [tone] so callers can paste any monochrome
  /// icon (fill/stroke color in the source SVG is ignored).
  final String svg;

  /// Bundled SVG asset path (`Assets.*`) — when set, takes precedence over
  /// the inline [svg] markup so tiles can use the mobile icon set.
  final String? svgAsset;
  final String value;
  final String label;
  final Color tone;
  final VoidCallback? onTap;

  /// Numerator of the ratio shown at the bottom of the tile — normally the
  /// same number rendered by [value], as an int. Null hides the ratio strip.
  final int? current;

  /// Denominator of the ratio (parent group total). Null hides the ratio
  /// strip.
  final int? denominator;

  /// Short suffix on the caption: e.g. `'total'`, `'open'`, `'all tasks'`
  /// → renders as "16 of 45 total".
  final String? denominatorLabel;

  @override
  State<KpiTile> createState() => _KpiTileState();
}

class _KpiTileState extends State<KpiTile> {
  bool _hover = false;

  static const _dur = Duration(milliseconds: 160);
  static const _curve = Curves.easeOut;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final interactive = widget.onTap != null;
    final lifted = _hover && interactive;

    // Strip is rendered whenever the caller supplies both numerator and
    // denominator so every card in the KPI row lines up to the same height —
    // a 0-denominator tile draws an empty track and reads "0 of 0" instead
    // of collapsing shorter than its siblings.
    final showRatio = widget.current != null && widget.denominator != null;
    final fraction = (showRatio && widget.denominator! > 0)
        ? (widget.current! / widget.denominator!).clamp(0.0, 1.0)
        : 0.0;
    final pct = (fraction * 100).round();

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _dur,
          curve: _curve,
          padding: const EdgeInsets.all(ZebuSpacing.s4),
          decoration: BoxDecoration(
            color: t.bgElevated,
            // 16px — unified card-surface radius (see [PremiumCard]).
            borderRadius: BorderRadius.circular(ZebuRadius.r2xl),
            // Hover deepens the hairline border and steps the whisper shadow
            // up a notch — a quiet, in-place cue with no positional jump.
            border: Border.all(
              color: lifted ? t.borderStrong : t.borderSubtle,
              width: 1,
            ),
            boxShadow: lifted ? ZebuElevation.shadowMd : ZebuElevation.shadowXs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- Icon badge + hover chevron -----------------------------
              Row(
                children: [
                  AnimatedContainer(
                    duration: _dur,
                    curve: _curve,
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.tone.withValues(
                        alpha: lifted ? 0.18 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(ZebuRadius.rLg),
                      border: Border.all(
                        color: widget.tone.withValues(alpha: 0.16),
                        width: 1,
                      ),
                    ),
                    child: widget.svgAsset != null
                        ? SvgPicture.asset(
                            widget.svgAsset!,
                            width: 20,
                            height: 20,
                            colorFilter: ColorFilter.mode(
                              widget.tone,
                              BlendMode.srcIn,
                            ),
                          )
                        : SvgPicture.string(
                            widget.svg,
                            width: 20,
                            height: 20,
                            colorFilter: ColorFilter.mode(
                              widget.tone,
                              BlendMode.srcIn,
                            ),
                          ),
                  ),
                  const Spacer(),
                  // Hover-revealed "open" affordance. Kept in the layout at
                  // all times (opacity only) so the header never reflows.
                  AnimatedOpacity(
                    duration: _dur,
                    curve: _curve,
                    opacity: lifted ? 1 : 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: t.bgTertiary,
                        borderRadius: BorderRadius.circular(ZebuRadius.rSm),
                      ),
                      child: Icon(
                        Icons.arrow_outward_rounded,
                        size: 15,
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZebuSpacing.s3),

              // --- Value + label ------------------------------------------
              Text(
                widget.value,
                style: ZebuTextStyles.hero(context)
                    .withTabularNums()
                    .copyWith(fontSize: 30, letterSpacing: -0.8),
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: ZebuTextStyles.body(context).copyWith(
                  color: t.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),

              if (showRatio) ...[
                const SizedBox(height: ZebuSpacing.s3),
                _RatioStrip(
                  fraction: fraction,
                  pct: pct,
                  tone: widget.tone,
                  caption:
                      '${widget.current} of ${widget.denominator}'
                      '${widget.denominatorLabel == null ? '' : ' ${widget.denominatorLabel}'}',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin ratio strip — a rounded track with a proportional fill, paired with a
/// "X of Y" caption on the left and a bold percentage on the right. Sits at
/// the bottom of a [KpiTile] to give an honest "how much of the whole" read.
class _RatioStrip extends StatelessWidget {
  const _RatioStrip({
    required this.fraction,
    required this.pct,
    required this.tone,
    required this.caption,
  });

  final double fraction;
  final int pct;
  final Color tone;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Track + proportional fill in the card's tone. The fill animates its
        // width so the bar "draws in" when data arrives / the card rebuilds.
        ClipRRect(
          borderRadius: BorderRadius.circular(ZebuRadius.rFull),
          child: Container(
            height: 6,
            color: tone.withValues(alpha: 0.12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction == 0 ? 0.0001 : fraction,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, child) => Opacity(
                    opacity: v,
                    child: Container(
                      decoration: BoxDecoration(
                        color: tone,
                        borderRadius: BorderRadius.circular(ZebuRadius.rFull),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZebuTextStyles.caption(context),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$pct%',
              style: ZebuTextStyles.caption(context).copyWith(
                color: tone,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
