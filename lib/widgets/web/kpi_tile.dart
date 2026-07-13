import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../features/dashboard/web/_tokens.dart';

/// Vertical KPI tile — icon-in-tinted-square (top-left) then a large
/// tabular value and a muted label underneath. Optional [onTap] wires the
/// whole tile as a click target with a smooth hover transition: border
/// deepens, a soft shadow appears, and the whole tile lifts one pixel via
/// [AnimatedContainer.transform]. All state changes ride the same 160 ms
/// [Curves.easeOut] so the feedback reads as one continuous motion instead
/// of a border-and-shadow "pop".
///
/// Optional [current] + [denominator] pair renders a subtle ratio strip at
/// the bottom of the tile: a thin proportional bar plus a small "X of Y"
/// caption. Uses real data the caller already has (from
/// `ReportSummary.totals`) so the tile stops feeling empty on the right
/// side without inventing metrics — the bar fills that slack visually and
/// the caption gives an exact number underneath.
///
/// Sizing is fluid so the tile expands to fill whatever slot a parent gives
/// it (typically a 4-column / 2-column / 1-column responsive grid on the
/// dashboard).
class KpiTile extends StatefulWidget {
  const KpiTile({
    super.key,
    required this.svg,
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
    final t = WebTokens.of(context);
    final interactive = widget.onTap != null;
    final lifted = _hover && interactive;

    // Strip is rendered whenever the caller supplies both numerator and
    // denominator so every tile in the KPI row lines up to the same height —
    // a 0-denominator tile draws an empty track and reads "0 of 0" instead
    // of collapsing shorter than its siblings.
    final showRatio =
        widget.current != null && widget.denominator != null;
    final fraction = (showRatio && widget.denominator! > 0)
        ? (widget.current! / widget.denominator!).clamp(0.0, 1.0)
        : 0.0;

    return MouseRegion(
      cursor: interactive
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _dur,
          curve: _curve,
          // Subtle one-pixel lift + border/shadow shift, all sharing the
          // same curve so the tile feels like a single object responding
          // to hover rather than three separate style changes.
          transform: Matrix4.translationValues(0, lifted ? -1 : 0, 0),
          transformAlignment: Alignment.center,
          padding: const EdgeInsets.all(WebTokens.s3),
          decoration: BoxDecoration(
            color: t.bgElevated,
            borderRadius: BorderRadius.circular(WebTokens.rSm),
            border: Border.all(
              color: lifted ? t.borderStrong : t.borderSubtle,
              width: 1,
            ),
            // Whisper shadow at rest, deeper shadow on hover so the lift is
            // felt rather than seen. Both share the same easeOut curve so
            // the transition reads as one continuous motion.
            boxShadow: lifted ? WebTokens.shadowSm : WebTokens.shadowXs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // AnimatedContainer(
              //   duration: _dur,
              //   curve: _curve,
              //   width: 28,
              //   height: 28,
              //   alignment: Alignment.center,
              //   decoration: BoxDecoration(
              //     color: widget.tone.withValues(alpha: lifted ? 0.16 : 0.12),
              //     borderRadius: BorderRadius.circular(WebTokens.rXs),
              //     // Hairline tone-tinted border on the icon square. Matches
              //     // the [StatusPill] treatment so all "tone-tinted" surfaces
              //     // in the app share the same visual DNA.
              //     border: Border.all(
              //       color: widget.tone.withValues(alpha: 0.18),
              //       width: 1,
              //     ),
              //   ),
              //   child: SvgPicture.string(
              //     widget.svg,
              //     width: 16,
              //     height: 16,
              //     colorFilter: ColorFilter.mode(widget.tone, BlendMode.srcIn),
              //   ),
              // ),
              // const SizedBox(height: WebTokens.s2),
              Text(widget.value, style: t.valueLarge(t.textPrimary)),
              Text(widget.label, style: t.bodySm),
              if (showRatio) ...[
                const SizedBox(height: WebTokens.s2),
                _RatioStrip(
                  fraction: fraction,
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

/// Thin ratio strip — a rounded pill background with a proportional fill,
/// paired with a small right-aligned caption. Sits at the bottom of a
/// [KpiTile] to give the tile a tactile "how much of the whole" read.
class _RatioStrip extends StatelessWidget {
  const _RatioStrip({
    required this.fraction,
    required this.tone,
    required this.caption,
  });

  final double fraction;
  final Color tone;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bar: tinted track + proportional fill in the tile's tone. Uses
        // the same 10 % / 100 % alpha combo the StatusPill + icon square
        // use so all tone-tinted surfaces feel like one family.
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(WebTokens.rFull),
          ),
          child: FractionallySizedBox(
            widthFactor: fraction,
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                color: tone,
                borderRadius: BorderRadius.circular(WebTokens.rFull),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: t.textSecondary,
            height: 1.2,
            letterSpacing: 0.1,
          ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }
}
