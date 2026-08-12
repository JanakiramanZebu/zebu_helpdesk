import 'package:flutter/material.dart';

import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';
import 'status_pill.dart';

/// The labelled field rows a ticket or task detail panel shows in its
/// sidebar — assignee, department, status, dates.
///
/// Shared rather than duplicated: both panels render the same shape of row
/// against different models, and the sidebar treatment (icon tile, stacked
/// label over value, chevron on editable rows) is fiddly enough that a second
/// copy drifts within a week. The task panel had already drifted — flat rows,
/// no tiles, no group headings.

/// Label column width in the narrow, stacked layout.
const double kZebuFieldLabelWidth = 88;

/// Value column width in the narrow, stacked layout.
const double kZebuFieldValueWidth = 280;

/// Row height in the sidebar layout.
const double kZebuSidebarRowHeight = 40;

/// Single row: `[icon 16] [label 110 muted] [value expanded]`. Clickable
/// rows tint the value on hover so the affordance is discoverable without
/// the row growing a border or shadow.
class ZebuFieldRow extends StatefulWidget {
  const ZebuFieldRow({
    super.key,
    this.rowKey,
    required this.icon,
    required this.label,
    required this.value,
    required this.sidebar,
    this.onTap,
  });

  /// GlobalKey attached to the outlined select pill (not the whole row) so
  /// `rowKey.currentContext` returns the pill's element. Popup anchors
  /// under the pill instead of the row's left edge, keeping the dropdown
  /// visually attached to the value it's editing.
  final GlobalKey? rowKey;
  final IconData icon;
  final String label;
  final Widget value;

  /// True when the row is rendered inside the wide-mode right rail. In
  /// sidebar mode the clickable value slot flexes to fill remaining space
  /// instead of using the fixed [kZebuFieldValueWidth] pill width — the
  /// sidebar itself is only ~320 px wide, so a 280 px value would clip.
  final bool sidebar;

  /// Non-null makes the row clickable. Receives the pill's build context
  /// so the caller can anchor a popup directly beneath the value.
  final ValueChanged<BuildContext>? onTap;

  @override
  State<ZebuFieldRow> createState() => _ZebuFieldRowState();
}

class _ZebuFieldRowState extends State<ZebuFieldRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final clickable = widget.onTap != null;
    return widget.sidebar
        ? _buildSidebar(context, t, clickable)
        : _buildInline(context, t, clickable);
  }

  /// Sidebar rail: a leading glyph, then the label stacked above its value,
  /// with a chevron on rows that open a picker.
  ///
  /// Stacked rather than label-left/value-right because the rail is only
  /// 360 px wide — side by side, a fixed label column ate a quarter of it and
  /// long values (assignee names, timestamps) had nowhere to go. The chevron
  /// is the one thing that separates an editable field from a read-only one,
  /// so it stays.
  Widget _buildSidebar(BuildContext context, ZebuTheme t, bool clickable) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s2,
        vertical: 7,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Glyph sits in a tinted tile, as the design specifies. It gives
          // the rail a consistent left rhythm a bare icon on white doesn't,
          // and keeps narrow glyphs (flag) optically the same size as wide
          // ones (calendar).
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? t.surfaceMutedStrong : t.surfaceMuted,
              borderRadius: BorderRadius.circular(ZebuRadius.rSm),
            ),
            child: Icon(widget.icon, size: 16, color: t.iconMuted),
          ),
          const SizedBox(width: ZebuSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: ZebuTextStyles.small(context, color: t.textSlateMuted),
                ),
                const SizedBox(height: 3),
                widget.value,
              ],
            ),
          ),
          if (clickable)
            Icon(
              Icons.expand_more,
              size: 16,
              color: _hover ? t.linkSlate : t.iconMuted,
            ),
        ],
      ),
    );
    if (!clickable) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The whole row is the dropdown's anchor now that there is no pill
        // to hang it on, so the popup lands under the full-width field.
        onTap: () => widget.onTap!(widget.rowKey?.currentContext ?? context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgElevated,
            borderRadius: BorderRadius.circular(ZebuRadius.rXs),
          ),
          child: KeyedSubtree(key: widget.rowKey, child: row),
        ),
      ),
    );
  }

  /// Narrow single-column card: label left, value right on one line.
  Widget _buildInline(BuildContext context, ZebuTheme t, bool clickable) {
    final Widget valueSlot;
    if (clickable) {
      // Key on the pill (not the row) — dropdown popups anchor here so
      // they land under the value, aligned with the trigger's left edge.
      final Widget pill = KeyedSubtree(
        key: widget.rowKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: widget.value),
              Icon(
                Icons.expand_more,
                size: 16,
                color: _hover ? t.accent : t.textSecondary,
              ),
            ],
          ),
        ),
      );
      valueSlot = SizedBox(width: kZebuFieldValueWidth, child: pill);
    } else {
      valueSlot = Expanded(child: widget.value);
    }
    final row = SizedBox(
      height: 30,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s1),
        child: Row(
          children: [
            SizedBox(
              width: kZebuFieldLabelWidth,
              child: Text(
                widget.label,
                style: ZebuTextStyles.body(
                  context,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: ZebuSpacing.s3),
            valueSlot,
          ],
        ),
      ),
    );
    if (!clickable) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap!(widget.rowKey?.currentContext ?? context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          color: t.bgElevated,
          child: row,
        ),
      ),
    );
  }
}

/// Small-caps heading over a run of field rows ("ASSIGNMENT", "SCHEDULE").
///
/// Borrowed from the grouped design: the dividers alone told you fields were
/// related but not why. Rendered without that design's blue rule and tinted
/// icon tiles — at 360 px wide the chrome competed with the values.
class ZebuFieldGroupLabel extends StatelessWidget {
  const ZebuFieldGroupLabel(
    this.label, {
    super.key,
    this.first = false,
    this.count,
    this.trailing,
  });
  final String label;

  /// Optional count shown after the label, for groups that hold a list.
  final int? count;

  /// Optional action on the group's right edge — an add button, usually.
  final Widget? trailing;

  /// Skips the top divider on the first group, which would otherwise sit
  /// directly under the panel header.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: ZebuSpacing.s2,
        right: ZebuSpacing.s2,
        top: first ? 0 : ZebuSpacing.s4,
        bottom: ZebuSpacing.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!first) ...[
            Divider(height: 1, thickness: 1, color: t.dividerSlate),
            const SizedBox(height: ZebuSpacing.s4),
          ],
          Row(
            children: [
              Text(
                label,
                style: ZebuTextStyles.eyebrow(context, color: t.textSlateMuted),
              ),
              if (count != null && count! > 0) ...[
                const SizedBox(width: ZebuSpacing.s2),
                Text(
                  '$count',
                  style: ZebuTextStyles.eyebrow(
                    context,
                    color: t.textSlateMuted,
                  ).withTabularNums(),
                ),
              ],
              if (trailing != null) ...[const Spacer(), trailing!],
            ],
          ),
        ],
      ),
    );
  }
}

/// Plain text value used by read-only rows and the assignee / department /
/// requester rows when set.
class ZebuTextValue extends StatefulWidget {
  const ZebuTextValue({
    super.key,
    required this.text,
    this.tone,
    this.linked = false,
  });
  final String text;

  /// Optional semantic tone (e.g. red for an overdue due-date, accent
  /// blue for an editable link). Falls back to `textPrimary` when null.
  final Color? tone;

  /// When true, the value tracks its own hover state and underlines the
  /// text under the pointer — same "anchor tag" affordance a form link
  /// would carry. Used on editable text values (Assignee, Department
  /// with real names) to reinforce click-to-edit.
  final bool linked;

  @override
  State<ZebuTextValue> createState() => _ZebuTextValueState();
}

class _ZebuTextValueState extends State<ZebuTextValue> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final color = widget.tone ?? t.textPrimary;
    // Inherit the ambient DefaultTextStyle base so the sidebar's bumped
    // 14 px wrap propagates into value text — the surrounding column
    // wraps in a DefaultTextStyle.merge with `bodyBase`, and this pulls
    // that size out of the ambient rather than hard-pinning to `bodySm`.
    final base = DefaultTextStyle.of(context).style;
    final child = Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(
        color: color,
        fontWeight: FontWeight.w500,
        decoration: widget.linked && _hover
            ? TextDecoration.underline
            : TextDecoration.none,
        decorationColor: color,
      ),
    );
    if (!widget.linked) return child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: child,
    );
  }
}

class ZebuStatusValuePill extends StatelessWidget {
  const ZebuStatusValuePill({
    super.key,
    required this.label,
    required this.color,
  });
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: StatusPill(label: label, color: color),
    );
  }
}

/// Muted placeholder value shown when the field has no data yet. Reads as
/// "click to set" — the parent row's caret already carries the affordance
/// so no extra chrome is needed here.
class ZebuEmptyValue extends StatelessWidget {
  const ZebuEmptyValue({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ZebuTextStyles.body(
        context,
      ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w500),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity subheader — sits above the thread. Left label + sort toggle on
// the right, hairline borders top & bottom.
// ---------------------------------------------------------------------------
