import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/assets.dart';
import '../res/zebu_theme.dart';
import '../res/zebu_spacing.dart';
import '../res/zebu_text_styles.dart';
import 'app_dropdown.dart';
import 'list_controls.dart' show DateRange;
import 'svg_icon.dart';
import 'web/select_checkbox.dart';
import 'web/zebu_select.dart';

/// One selectable quick-filter chip shown inside the [WebFilterButton]'s
/// popover.
///
/// The parent page owns the actual filter state; this class just gives
/// the popover a label to render and a callback to fire when the chip
/// is tapped.
class WebQuickFilter {
  const WebQuickFilter({
    required this.label,
    required this.active,
    required this.onToggle,
  });

  final String label;
  final bool active;
  final VoidCallback onToggle;
}

/// Date-range control shown in the popover ("Date range" section). Uses
/// the shared [DateRange] enum so the same value flows through both
/// mobile and web filter paths.
class WebDateRangeControl {
  const WebDateRangeControl({required this.value, required this.onChanged});
  final DateRange value;
  final ValueChanged<DateRange> onChanged;
}

/// Sort-by control shown in the popover ("Sort by" section).
class WebSortControl {
  const WebSortControl({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  /// Ordered list of `(key, label)` pairs. `key` is opaque to this widget
  /// and is echoed back to the parent via [onChanged].
  final List<({String key, String label})> options;
  final String selected;
  final ValueChanged<String> onChanged;
}

/// One facet dropdown (Department, Status, Priority, Agent, Tag, …).
/// Options begin with `("all", "All …")` and the parent applies the
/// selection either client-side or server-side as it prefers.
class WebFacetControl {
  const WebFacetControl({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<({String value, String text})> options;

  /// Selected option's `value`. `'all'` is the neutral "no filter" state.
  final String selected;
  final ValueChanged<String> onChanged;
}

/// "Filter" trigger button + anchored popover.
///
/// Renders as an outline pill placed before the search input on list
/// pages. Tapping opens a wide popover with sections mirroring the
/// mobile filter format:
///
///   * "Filters" header + "Clear" action
///   * Quick filters (toggleable chips)
///   * Sort by (dropdown)
///   * Date range (dropdown)
///   * One dropdown per facet (Department, Status, Priority, Agent, Tag)
///
/// Any section whose controlling parameter is `null` / empty is silently
/// omitted so a page can opt in incrementally.
class WebFilterButton extends StatefulWidget {
  const WebFilterButton({
    super.key,
    required this.filters,
    this.dateRange,
    this.sort,
    this.facets = const [],
    this.onClear,
  });

  final List<WebQuickFilter> filters;
  final WebDateRangeControl? dateRange;
  final WebSortControl? sort;
  final List<WebFacetControl> facets;

  /// Fires when the user taps "Clear" in the panel header. Null hides
  /// the action.
  final VoidCallback? onClear;

  @override
  State<WebFilterButton> createState() => _WebFilterButtonState();
}

class _WebFilterButtonState extends State<WebFilterButton> {
  bool _hover = false;

  int get _activeCount {
    var n = widget.filters.where((f) => f.active).length;
    if (widget.dateRange != null && widget.dateRange!.value != DateRange.all) {
      n++;
    }
    for (final f in widget.facets) {
      if (f.selected != 'all') n++;
    }
    return n;
  }

  Future<void> _open(BuildContext ctx) async {
    await _showFilterPanel(
      ctx,
      filters: widget.filters,
      dateRange: widget.dateRange,
      sort: widget.sort,
      facets: widget.facets,
      onClear: widget.onClear,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final active = _activeCount > 0;
    return Builder(
      builder: (btnCtx) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(btnCtx),
          // Square 40 × 40 icon button — matches the search input's
          // height so the two controls sit on a shared baseline. The
          // "Filter" label was dropped; the tune icon carries the
          // affordance on its own, and an active-count badge overlays
          // the top-right corner when any filter is applied.
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Circular icon button, matching the tradebook filter in Mynt
              // Plus Web: 36×36, an 18 px tune glyph, and no border. At rest
              // it is effectively a bare glyph — the idle fill is the card
              // tone, which is the same white as the page — and the active
              // state fills the circle solid brand blue with a white glyph.
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Tinted, not solid. A solid brand circle reads as a
                  // primary action button — the thing you press to *do*
                  // something — when all it is reporting is that a filter is
                  // on. The tint says "active" without claiming the page's
                  // strongest colour for a status.
                  color: active
                      ? t.accentSoft
                      : (_hover ? t.bgHover : t.bgHover.withValues(alpha: 0)),
                ),
                child: SvgIcon(
                  Assets.searchFilter,
                  size: 20,
                  color: active ? t.accent : t.textSecondary,
                ),
              ),
              // Count badge on the circle's top-right edge. The tradebook
              // button it copies has no count, but ours is worth keeping —
              // "filtered" alone doesn't say how much is being hidden. The
              // ring is the page bg so it reads as a notification sitting on
              // the circle rather than a chip glued to it.
              // Superscript, not a notification pill — the same treatment the
              // view tabs use for their counts. A red badge is the language
              // of "something arrived that you have not seen"; this number is
              // just how many filters the agent themselves set, and painting
              // it as an alert made the toolbar look like it had an error.
              if (active)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Text(
                    '$_activeCount',
                    style: ZebuFonts.face(
                      fontSize: 12,
                      fontWeight: ZebuFonts.semiBold,
                      color: t.accent,
                    ).copyWith(height: 1.1),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showFilterPanel(
  BuildContext anchorContext, {
  required List<WebQuickFilter> filters,
  required WebDateRangeControl? dateRange,
  required WebSortControl? sort,
  required List<WebFacetControl> facets,
  VoidCallback? onClear,
}) async {
  final box = anchorContext.findRenderObject();
  if (box is! RenderBox || !box.attached) return;
  final overlayState = Overlay.of(anchorContext, rootOverlay: true);
  final overlayBox = overlayState.context.findRenderObject()! as RenderBox;
  final anchorTopLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
  final anchorSize = box.size;
  final viewport = overlayBox.size;

  const panelWidth = 480.0;

  final panelLeft = anchorTopLeft.dx.clamp(
    8.0,
    viewport.width - panelWidth - 8.0,
  );
  final belowTop = anchorTopLeft.dy + anchorSize.height + 6;

  final completer = Completer<void>();
  late OverlayEntry entry;

  void dismiss() {
    if (completer.isCompleted) return;
    completer.complete();
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: dismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: panelLeft,
          top: belowTop,
          width: panelWidth,
          // Cap the panel height so a long facet list stays scrollable
          // rather than overflowing the viewport.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: viewport.height - belowTop - 12,
            ),
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  dismiss();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: _FilterPanel(
                filters: filters,
                dateRange: dateRange,
                sort: sort,
                facets: facets,
                onClear: onClear == null
                    ? null
                    : () {
                        onClear();
                        dismiss();
                      },
              ),
            ),
          ),
        ),
      ],
    ),
  );

  overlayState.insert(entry);
  return completer.future;
}

class _FilterPanel extends StatefulWidget {
  const _FilterPanel({
    required this.filters,
    required this.dateRange,
    required this.sort,
    required this.facets,
    required this.onClear,
  });
  final List<WebQuickFilter> filters;
  final WebDateRangeControl? dateRange;
  final WebSortControl? sort;
  final List<WebFacetControl> facets;
  final VoidCallback? onClear;

  @override
  State<_FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<_FilterPanel> {
  // Local mirrors of the controlling values. The panel lives inside an
  // OverlayEntry whose closure captures the WebSortControl / WebFacet
  // Control instances at open-time — when the parent re-renders with
  // new selection, THIS widget's `widget.sort` still points at the old
  // object and its `.selected` field never mutates. That's why picking
  // an option used to leave the dropdown label unchanged. We track the
  // current selection here and update it on pick so the label reflects
  // the choice instantly, while still forwarding to the parent so its
  // list state stays in sync.
  late DateRange _dateRange;
  late String _sortKey;
  late final Map<int, String> _facetPick;
  // Local mirror of each quick-filter's active state. The parent's
  // WebQuickFilter list is captured at open-time and never mutates in
  // place, so we track the current active state here and flip it on tap
  // (in parallel with firing the parent's onToggle callback). Without
  // this mirror the chip visual only refreshed after closing + reopening
  // the panel because `widget.filters[i].active` still pointed at the
  // stale snapshot.
  late final List<bool> _filterActive;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _dateRange = widget.dateRange?.value ?? DateRange.all;
    _sortKey = widget.sort?.selected ?? '';
    _facetPick = {
      for (var i = 0; i < widget.facets.length; i++)
        i: widget.facets[i].selected,
    };
    _filterActive = [for (final f in widget.filters) f.active];
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Any filter meaningfully non-default — used to decide whether the
  /// "Clear all" button appears. Sort is intentionally excluded: it's a
  /// display preference, not an active filter.
  bool get _anyActive {
    if (_filterActive.any((a) => a)) return true;
    if (widget.dateRange != null && _dateRange != DateRange.all) return true;
    for (final v in _facetPick.values) {
      if (v != 'all') return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    // Dedicated scroll controller so we can attach a persistent Scrollbar
    // to the panel's internal SingleChildScrollView — otherwise the user
    // has no signal that the sections continue past the visible viewport
    // when the popover clamps to the viewport height.
    // Watchlist-popover surface: one soft shadow rather than a Material
    // elevation, which stacks several umbra/penumbra layers and reads as a
    // lifted card. This is a sheet — it should look like it is resting a few
    // pixels off the page, not floating above it.
    //
    // Corners stay at 6, matching the dropdown menus inside it, rather than
    // the reference's square edge: their theme sets `radius: 0` globally, so
    // copying it here would leave one square surface among rounded ones.
    return Container(
      decoration: BoxDecoration(
        color: t.bgElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.borderSubtle, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 12,
            spreadRadius: 2,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Filters',
                          style: ZebuTextStyles.sectionTitle(
                            context,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      // Enabled state comes from LIVE local state, not
                      // from whether the parent supplied a callback at
                      // open-time: the OverlayEntry captures
                      // `widget.onClear` once, so filters set inside
                      // the panel would otherwise not light this up
                      // until it was closed and reopened.
                      //
                      // Disabled rather than absent, so the header
                      // doesn't reflow when a first filter is ticked.
                      _ClearAllButton(
                        enabled: _anyActive && widget.onClear != null,
                        onTap: () {
                          widget.onClear?.call();
                          setState(() {
                            for (var i = 0; i < _filterActive.length; i++) {
                              _filterActive[i] = false;
                            }
                            _dateRange = DateRange.all;
                            for (final k in _facetPick.keys.toList()) {
                              _facetPick[k] = 'all';
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  if (widget.filters.isNotEmpty) ...[
                    const SizedBox(height: ZebuSpacing.s3),
                    _SectionHeader(label: 'Quick filters'),
                    const SizedBox(height: ZebuSpacing.s2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < widget.filters.length; i++)
                          _FilterChip(
                            label: widget.filters[i].label,
                            active: _filterActive[i],
                            onToggled: () {
                              widget.filters[i].onToggle();
                              setState(() {
                                _filterActive[i] = !_filterActive[i];
                              });
                            },
                          ),
                      ],
                    ),
                  ],
                  // Sort + Date range live side-by-side as the first 2-col
                  // row of the panel. If only one of them is provided, the
                  // other cell falls back to an invisible spacer so the
                  // remaining control still occupies its natural half.
                  if (widget.sort != null || widget.dateRange != null) ...[
                    const SizedBox(height: ZebuSpacing.s4),
                    _TwoColumnRow(
                      left: widget.sort == null
                          ? const SizedBox.shrink()
                          : _LabelledDropdown(
                              label: 'Sort by',
                              child: _FilterDropdown<String>(
                                label: _labelFor(
                                  widget.sort!.options,
                                  _sortKey,
                                  (o) => o.key,
                                  (o) => o.label,
                                ),
                                entries: [
                                  for (final o in widget.sort!.options)
                                    _DropdownEntry(
                                      value: o.key,
                                      label: o.label,
                                    ),
                                ],
                                selected: _sortKey,
                                onSelected: (v) {
                                  setState(() => _sortKey = v);
                                  widget.sort!.onChanged(v);
                                },
                              ),
                            ),
                      right: widget.dateRange == null
                          ? const SizedBox.shrink()
                          : _LabelledDropdown(
                              label: 'Date range',
                              child: _FilterDropdown<DateRange>(
                                label: _dateRange.label,
                                entries: [
                                  for (final r in DateRange.values)
                                    _DropdownEntry(value: r, label: r.label),
                                ],
                                selected: _dateRange,
                                onSelected: (v) {
                                  setState(() => _dateRange = v);
                                  widget.dateRange!.onChanged(v);
                                },
                              ),
                            ),
                    ),
                  ],
                  if (widget.facets.isNotEmpty) ...[
                    // No section header here. Every dropdown below labels
                    // itself, and the panel is already titled "Filters" — a
                    // second one said the same word twice, fifteen pixels
                    // apart, and bought nothing.
                    const SizedBox(height: ZebuSpacing.s4),
                    // 2-column grid — pair facets up so the panel fills
                    // width evenly instead of a tall column of stacked
                    // full-width dropdowns. Odd-count trailing facet ends
                    // up alone in the last row with an empty right cell.
                    for (var i = 0; i < widget.facets.length; i += 2)
                      Padding(
                        // 16 between rows, matching the gutter between the two
                        // columns — the grid then has one spacing value in
                        // both axes instead of 8 down and 16 across.
                        padding: const EdgeInsets.only(bottom: ZebuSpacing.s4),
                        child: _TwoColumnRow(
                          left: _LabelledDropdown(
                            label: widget.facets[i].label,
                            child: _FilterDropdown<String>(
                              label: _labelFor(
                                widget.facets[i].options,
                                _facetPick[i] ?? 'all',
                                (o) => o.value,
                                (o) => o.text,
                              ),
                              entries: [
                                for (final o in widget.facets[i].options)
                                  _DropdownEntry(value: o.value, label: o.text),
                              ],
                              selected: _facetPick[i] ?? 'all',
                              onSelected: (v) {
                                setState(() => _facetPick[i] = v);
                                widget.facets[i].onChanged(v);
                              },
                            ),
                          ),
                          right: i + 1 < widget.facets.length
                              ? _LabelledDropdown(
                                  label: widget.facets[i + 1].label,
                                  child: _FilterDropdown<String>(
                                    label: _labelFor(
                                      widget.facets[i + 1].options,
                                      _facetPick[i + 1] ?? 'all',
                                      (o) => o.value,
                                      (o) => o.text,
                                    ),
                                    entries: [
                                      for (final o
                                          in widget.facets[i + 1].options)
                                        _DropdownEntry(
                                          value: o.value,
                                          label: o.text,
                                        ),
                                    ],
                                    selected: _facetPick[i + 1] ?? 'all',
                                    onSelected: (v) {
                                      setState(() => _facetPick[i + 1] = v);
                                      widget.facets[i + 1].onChanged(v);
                                    },
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Resolves the display label for the currently-selected option in a
  /// list of arbitrary records — [keyOf] extracts the option's key,
  /// [labelOf] extracts its display text. Falls back to the first entry
  /// if [selected] doesn't match anything (defensive; shouldn't happen
  /// in practice).
  static String _labelFor<T, K>(
    List<T> options,
    K selected,
    K Function(T) keyOf,
    String Function(T) labelOf,
  ) {
    if (options.isEmpty) return '';
    return labelOf(
      options.firstWhere(
        (o) => keyOf(o) == selected,
        orElse: () => options.first,
      ),
    );
  }
}

/// Two-column layout row used across the filter panel — each side gets an
/// equal `Expanded` slot with a fixed gutter between them. Pass
/// `SizedBox.shrink()` on one side to leave the trailing cell empty when
/// pairing an odd number of controls.
class _TwoColumnRow extends StatelessWidget {
  const _TwoColumnRow({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: ZebuSpacing.s4),
        Expanded(child: right),
      ],
    );
  }
}

/// Small caption above a dropdown — replaces the "Sort by" / "Date range"
/// section headers so each dropdown can label itself when placed in a
/// grid cell (rather than relying on a full-width section header row).
class _LabelledDropdown extends StatelessWidget {
  const _LabelledDropdown({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Create-SIP dialog pattern: the label sits at body size in the
        // primary ink, not as a muted caption. A field label is part of the
        // control, not commentary on it — greying it made the panel read as
        // seven captions with something under each.
        Text(
          label,
          style: ZebuTextStyles.body(
            context,
            color: t.textPrimary,
            fontWeight: ZebuFonts.medium,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Text(
      label,
      style: ZebuTextStyles.label(context).copyWith(color: t.textSecondary),
    );
  }
}

class _DropdownEntry<T> {
  const _DropdownEntry({required this.value, required this.label});
  final T value;
  final String label;
}

/// Minimal outline dropdown used by every section in the panel. Opens
/// its own inner overlay with a scrim so the parent panel doesn't
/// disappear when the user picks an option.
class _FilterDropdown<T> extends StatefulWidget {
  const _FilterDropdown({
    required this.label,
    required this.entries,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final List<_DropdownEntry<T>> entries;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  State<_FilterDropdown<T>> createState() => _FilterDropdownState<T>();
}

class _FilterDropdownState<T> extends State<_FilterDropdown<T>> {
  /// Opens the app's one dropdown menu.
  ///
  /// This used to hand-roll its own overlay — own positioning, own rows, no
  /// search field however long the list — so the same control looked different
  /// depending on which screen you opened it from. Everything the menu does
  /// now lives in `showAppDropdown`: the flip-up near the viewport bottom, the
  /// search field once a list gets long enough, and the selected-row mark.
  ///
  /// `minWidth: 0` lets the menu take the anchor's width rather than the
  /// shared 220 px floor — these sit two-up in a 420 px panel, so the floor
  /// would hang the menu past the edge of the box that opened it.
  Future<void> _open(BuildContext ctx) async {
    final picked = await showAppDropdown<T>(
      ctx,
      minWidth: 0,
      entries: [
        for (final e in widget.entries)
          AppDropdownItem<T>(
            value: e.value,
            label: e.label,
            selected: e.value == widget.selected,
          ),
      ],
    );
    if (picked != null && picked != widget.selected) {
      widget.onSelected(picked);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ZebuSelect(label: widget.label, onTap: _open);
}

class _FilterChip extends StatefulWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onToggled,
  });
  final String label;
  final bool active;
  final VoidCallback onToggled;

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final active = widget.active;
    // A checkbox, not a chip. These four toggle independently — an agent can
    // watch Emergency and High at once — and a row of pills reads as
    // pick-one no matter how it behaves. A checkbox states the arity before
    // anything is clicked.
    //
    // The whole row is the target, label included: a 16 px box is a small
    // thing to hit, and the label is the part being read.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggled,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            // Idle is the hover tone at zero alpha, never
            // `Colors.transparent` — that is transparent *black*, and a fill
            // lerping from it washes through grey on the way in.
            color: _hover ? t.bgHover : t.bgHover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Ignores its own pointer so the row's tap handler owns the
              // whole target — otherwise clicking the box and clicking the
              // label take two different code paths.
              IgnorePointer(
                child: SelectCheckbox(value: active, onChanged: (_) {}),
              ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: ZebuTextStyles.body(
                  context,
                  color: active ? t.textPrimary : t.textSecondary,
                  fontWeight: active ? ZebuFonts.semiBold : ZebuFonts.medium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClearAllButton extends StatefulWidget {
  const _ClearAllButton({required this.onTap, required this.enabled});
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_ClearAllButton> createState() => _ClearAllButtonState();
}

class _ClearAllButtonState extends State<_ClearAllButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final on = widget.enabled;
    // Ghost, sized to its label. The outlined skin came from Mynt's filter
    // dialog, where Clear is the *secondary* of a pair and a solid Apply
    // carries the weight. With no Apply beside it, that skin made the
    // loudest control in the panel the one that throws the agent's work
    // away. A footer action that undoes things should be findable, not
    // prominent.
    return MouseRegion(
      cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: on ? widget.onTap : null,
        child: Opacity(
          opacity: on ? 1 : 0.4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              // Idle is the hover tone at zero alpha, never
              // `Colors.transparent` — that is transparent *black*, and a
              // fill lerping from it washes through grey on the way in.
              color: _hover && on
                  ? t.accentSoft
                  : t.accentSoft.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Clear all',
              style: ZebuTextStyles.small(
                context,
                color: t.accent,
                fontWeight: ZebuFonts.semiBold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
