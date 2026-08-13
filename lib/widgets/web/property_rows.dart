import 'package:flutter/material.dart';

import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';

/// The "Properties" block a create form shows for its optional settings.
///
/// A flat two-column grid of `label → value` rows: no boxes, no leading
/// glyphs, no group headings. One hairline per row is the only chrome, and
/// the value itself is the control — accent when set, muted when not, under a
/// dashed rule that says "editable in place" without drawing a box.
///
/// This replaces a grid of outlined selects. Eight bordered boxes inside a
/// bordered dialog gave every optional setting the same weight as the Subject
/// and Message fields you actually have to fill in, and the borders drew more
/// of the eye than the values inside them.
///
/// Colours come from the approved mock and are pinned here rather than taken
/// from the slate family the detail panel uses — that family is bluer and
/// heavier, which is right for a panel you read and wrong for a form you skim.
class ZebuPropertyGrid extends StatelessWidget {
  const ZebuPropertyGrid({
    super.key,
    required this.rows,
    this.title = 'Properties',
    this.hint = 'all optional',
  });

  final List<ZebuPropertySpec> rows;

  /// Eyebrow above the grid.
  final String title;

  /// Sits beside [title] in the muted tone. Saying it once here is what lets
  /// every row below drop its own "(optional)".
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              title,
              // Weight goes through the constructor, never `copyWith`.
              // `google_fonts` picks the face by family name (`Inter_600`),
              // so a weight set afterwards changes the number and not a
              // single pixel — the family still points at the 400 file.
              style: ZebuTextStyles.body(
                context,
                color: t.textSlate,
                fontWeight: ZebuFonts.regular,
              ),
            ),
            // if (hint != null) ...[
            //   const SizedBox(width: ZebuSpacing.s2),
            //   Text(
            //     hint!,
            //     style: ZebuTextStyles.small(
            //       context,
            //     ).copyWith(fontSize: 12, color: zebuPropertyMuted(t)),
            //   ),
            // ],
          ],
        ),
        const SizedBox(height: 8),
        _grid(),
      ],
    );
  }

  /// Two rows per line; a trailing odd row keeps its half rather than
  /// stretching, so both columns stay on the same rails all the way down.
  Widget _grid() {
    final lines = <Widget>[];
    for (var i = 0; i < rows.length; i += 2) {
      final right = i + 1 < rows.length ? rows[i + 1] : null;
      lines.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _PropertyRow(spec: rows[i])),
            const SizedBox(width: ZebuSpacing.s8),
            Expanded(
              child: right == null
                  ? const SizedBox.shrink()
                  : _PropertyRow(spec: right),
            ),
          ],
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: lines);
  }
}

/// One settable property.
class ZebuPropertySpec {
  const ZebuPropertySpec({
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    this.placeholder = 'None',
    this.dotColor,
    this.anchorToRow = false,
  });

  final String label;
  final String? value;

  /// Glyph in a tinted tile before the label. Gives the column a fixed left
  /// rhythm so the eye finds a row by shape before it reads the word, which
  /// matters in a grid of eight near-identical rows.
  final IconData? icon;

  /// Shown in the muted tone when [value] is empty — "None", "Auto-assign",
  /// "Open (default)". Naming the default beats a blank: it says what will
  /// happen if you leave the row alone.
  final String placeholder;

  /// Paints an 8 px circle before a set value. Used on Status and Priority,
  /// where the colour carries as much meaning as the word.
  final Color? dotColor;

  /// Receives a context to anchor the menu on — the value by default, or the
  /// whole row when [anchorToRow] is set.
  final ValueChanged<BuildContext> onTap;

  /// Hands [onTap] the row instead of the value.
  ///
  /// Menus are right-aligned to their anchor and can match its width, so a
  /// menu opened from a short value like `#4263` has nothing to grow into and
  /// stays at the narrow default. That is right for Status or Priority, whose
  /// rows are one word each. It is wrong for anything with a search box and
  /// two-line rows, where the label needs the whole row's width to be legible.
  final bool anchorToRow;
}

// --- Tones -----------------------------------------------------------------
// From the mock. Dark values are the nearest existing dark-mode step, so the
// block does not blow out when the theme flips.

/// Row label.
Color zebuPropertyLabel(ZebuTheme t) =>
    t.isLight ? const Color(0xFF4A4A4A) : const Color(0xFFC9D1D9);

/// Unset value, and the "all optional" hint.
Color zebuPropertyMuted(ZebuTheme t) =>
    t.isLight ? const Color(0xFF9AA1A9) : const Color(0xFF8B949E);

/// Section eyebrow.
Color zebuPropertyEyebrow(ZebuTheme t) =>
    t.isLight ? const Color(0xFF6B6B6B) : const Color(0xFF8B949E);

/// Tile behind a row's leading glyph.
Color zebuPropertyCodeBg(ZebuTheme t) =>
    t.isLight ? const Color(0xFFE4ECFB) : const Color(0x2E2F81F7);

/// Per-row hairline.
Color zebuPropertyRule(ZebuTheme t) =>
    t.isLight ? const Color(0xFFF1F3F8) : const Color(0xFF21262D);

/// Dashed rule under an unset value.
///
/// Its own tone rather than the placeholder text at reduced alpha: `#9AA1A9`
/// at 55% is lighter than the row divider it sits above, so the affordance
/// that says "this is editable" was the faintest mark on the row. A dash is
/// broken into 2 px segments, which reads lighter than a solid line of the
/// same colour — it has to start darker than the text to land level with it.
Color zebuPropertyRuleUnset(ZebuTheme t) =>
    t.isLight ? const Color(0xFF8A929B) : const Color(0xFF6E7681);

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({required this.spec});
  final ZebuPropertySpec spec;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final isSet = spec.value != null && spec.value!.isNotEmpty;
    final ink = isSet ? t.accent : zebuPropertyMuted(t);

    return LayoutBuilder(
      builder: (context, box) {
        // The value is a non-flex child, so it is laid out before the label
        // gets the remainder — a fixed 180 cap therefore overflowed the row
        // once a column got narrower than label + gap + 180. Reserving room
        // for the label first keeps the cap at 180 on a full-width dialog and
        // lets it give way below that instead of overflowing.
        final hasIcon = spec.icon != null;
        final valueMax = (box.maxWidth - (hasIcon ? 126 : 96)).clamp(
          56.0,
          180.0,
        );

        // The `Builder` sits inside the row it anchors: `findRenderObject`
        // walks down, so a context taken from outside would measure the
        // column, not this row.
        return Builder(
          builder: (rowContext) => Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: zebuPropertyRule(t), width: 1),
              ),
            ),
            child: Row(
              children: [
                if (hasIcon) ...[
                  _IconTile(icon: spec.icon!),
                  const SizedBox(width: ZebuSpacing.s2),
                ],
                // `Expanded`, and no `Spacer` after it. This was `Flexible` plus
                // a `Spacer`: both default to `flex: 1`, so RenderFlex split the
                // free space equally between them. The label is loose and only
                // drew what it needed, but the half allocated to it was still
                // consumed and never reached the Spacer — leaving dead space on
                // the right that grew as the value got shorter. Expanded takes
                // the whole remainder and pushes the value hard against the
                // row's right edge.
                Expanded(
                  child: Text(
                    spec.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZebuTextStyles.small(context).copyWith(
                      fontSize: 13,
                      color: zebuPropertyLabel(t),
                      fontWeight: ZebuFonts.regular,
                    ),
                  ),
                ),
                const SizedBox(width: ZebuSpacing.s2),
                // Cursor only. The pointer turning to a hand is the whole hover
                // signal now — the rule stays put, so an idle row and a hovered
                // row read as the same row.
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Builder(
                    builder: (anchor) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          spec.onTap(spec.anchorToRow ? rowContext : anchor),
                      // No fill and no border. The dashed underline under the
                      // value is the whole affordance — it says "editable in
                      // place" the way a form field would without putting a box
                      // on the row, which is what the outlined selects did wrong.
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSet && spec.dotColor != null) ...[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: spec.dotColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: valueMax),
                              child: Text(
                                isSet ? spec.value! : spec.placeholder,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    ZebuTextStyles.small(
                                      context,
                                      fontWeight: ZebuFonts.semiBold,
                                    ).copyWith(
                                      fontSize: 13,
                                      color: ink,
                                      decoration: TextDecoration.underline,
                                      // Always dashed, in both states — the rule
                                      // means "editable in place", which does
                                      // not stop being true once a value is set.
                                      // Only the colour moves: grey while empty,
                                      // accent once filled, matching the text
                                      // above it. No hover step; the rule is not
                                      // a hover affordance and brightening it
                                      // made an idle row look half-disabled.
                                      decorationStyle:
                                          TextDecorationStyle.dashed,
                                      decorationColor: isSet
                                          ? t.accent
                                          : zebuPropertyRuleUnset(t),
                                      decorationThickness: 1,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Tinted glyph tile before a property label.
class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Icon(icon, size: 18, color: t.accent);
  }
}
