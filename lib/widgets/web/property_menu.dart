import 'dart:async';

import 'package:flutter/material.dart';

import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';
import 'ellipsis_text.dart';
import 'select_checkbox.dart';
import 'zebu_text_action.dart';
import 'anchored_popover.dart';
import 'check_mark.dart';

/// The dropdown menu from the approved mock: a popover anchored under — or
/// above — the tapped value chip. Radius 10, hairline border, soft shadow,
/// hover rows, the selected row tinted with a trailing check, and optional
/// coloured dots for Status and Priority entries.
///
/// Right-aligned to the trigger rather than left, because the value chips it
/// opens from sit at the right edge of their row; hanging the menu off the
/// left edge would have floated it away from the thing it was editing.
///
/// This is deliberately separate from [showAppDropdown], which the rest of the
/// app uses for action menus and filter selects. That one marks selection with
/// weight and colour and carries a search field on long lists; this one is the
/// property grid's own, per the mock.
/// Item count at which the menu grows a filter box. Matches the threshold in
/// `showAppDropdown` so the two behave the same on the same list.
const int kZebuMenuSearchThreshold = 6;

/// Fetches the rows for a query. Non-null turns the filter box into a remote
/// search: the field is always shown, keystrokes are debounced, and the menu
/// carries its own loading and no-results states.
///
/// Use it when the list lives on the server. A user directory runs to
/// thousands of rows, so filtering a fetched page of 25 locally would search
/// only whatever happened to load first.
typedef ZebuMenuSearch<T> =
    Future<List<ZebuPropertyMenuItem<T>>> Function(String query);

Future<T?> showZebuPropertyMenu<T>(
  BuildContext anchorContext, {
  List<ZebuPropertyMenuItem<T>> items = const [],
  ZebuMenuSearch<T>? search,
  String searchHint = 'Search',
  double minWidth = 190,
  double maxHeight = 240,

  /// Take the trigger's own width instead of [minWidth].
  ///
  /// The default suits the property grid, where the trigger is a short value
  /// at the right edge of its row — a menu as wide as the row would be a slab.
  /// A full-width select is the opposite case: a 190 px menu hanging under a
  /// 280 px control reads as belonging to something else.
  bool matchAnchorWidth = false,
}) {
  final overlay = zebuOverlayBox(anchorContext);
  if (overlay == null) return Future<T?>.value();
  final anchor = zebuAnchorRect(anchorContext, overlay);
  if (anchor == null) return Future<T?>.value();

  final width = matchAnchorWidth && anchor.width > minWidth
      ? anchor.width
      : minWidth;

  return Navigator.of(anchorContext, rootNavigator: true).push<T>(
    ZebuAnchoredRoute<T>(
      anchor: anchor,
      overlaySize: overlay.size,
      width: width,
      // Row height times count, capped — enough for the route to choose a
      // direction. The panel still sizes itself.
      // A remote search has no rows to measure yet, so assume it fills. Rows
      // carrying a subtitle are half again as tall.
      estimatedHeight: search != null
          ? maxHeight + 58
          : (items.length *
                        (items.any((i) => i.subtitle != null) ? 46.0 : 34.0) +
                    12)
                .clamp(46.0, maxHeight + 12),
      builder: (_) => _MenuPanel<T>(
        items: items,
        search: search,
        searchHint: searchHint,
        minWidth: width,
        maxHeight: maxHeight,
      ),
    ),
  );
}

/// The same menu, choosing several.
///
/// Returns the chosen set on **Done**, or null if dismissed — a multi-select
/// that committed on every tick would leave no way to back out of four
/// mistakes, and the footer's Clear would be indistinguishable from an undo.
///
/// Rows stay put when tapped. Closing after each pick is what made adding
/// three collaborators mean opening the picker three times.
Future<Set<T>?> showZebuMultiSelectMenu<T>(
  BuildContext anchorContext, {
  required Set<T> selected,
  List<ZebuPropertyMenuItem<T>> items = const [],
  ZebuMenuSearch<T>? search,
  String searchHint = 'Search',
  double minWidth = 190,
  double maxHeight = 240,
  bool matchAnchorWidth = false,
}) {
  final overlay = zebuOverlayBox(anchorContext);
  if (overlay == null) return Future<Set<T>?>.value();
  final anchor = zebuAnchorRect(anchorContext, overlay);
  if (anchor == null) return Future<Set<T>?>.value();

  final width = matchAnchorWidth && anchor.width > minWidth
      ? anchor.width
      : minWidth;

  return Navigator.of(anchorContext, rootNavigator: true).push<Set<T>>(
    ZebuAnchoredRoute<Set<T>>(
      anchor: anchor,
      overlaySize: overlay.size,
      width: width,
      // Search box, list, and a footer that is always there.
      estimatedHeight: maxHeight + 100,
      builder: (_) => _MultiPanel<T>(
        items: items,
        search: search,
        searchHint: searchHint,
        initial: selected,
        minWidth: width,
        maxHeight: maxHeight,
      ),
    ),
  );
}

class ZebuPropertyMenuItem<T> {
  const ZebuPropertyMenuItem({
    required this.value,
    required this.label,
    this.selected = false,
    this.dotColor,
    this.muted = false,
    this.subtitle,
    this.leading,
  });

  final T value;
  final String label;
  final bool selected;

  /// 8 px circle before the label, in the status or priority colour. Null
  /// hides it.
  final Color? dotColor;

  /// Grey label — for the "None" / default entry, which names what happens if
  /// you pick nothing rather than offering another value.
  final bool muted;

  /// Second line under [label] — an email, an org, a reference. Rows carrying
  /// one are taller, and the route accounts for that when it picks a side to
  /// open on.
  final String? subtitle;

  /// Leading widget, sized by the caller. An avatar, usually. Takes the
  /// [dotColor] slot when both are given.
  final Widget? leading;
}

// --- Tones -----------------------------------------------------------------
// Now shared with the date picker, which sits on the same card a hairline
// away; these are local aliases so the call sites below read unchanged.

Color _panel(ZebuTheme t) => zebuPopoverPanel(t);

Color _edge(ZebuTheme t) => zebuPopoverEdge(t);

Color _selectedBg(ZebuTheme t) => zebuPopoverSelectedBg(t);

Color _hoverBg(ZebuTheme t) => zebuPopoverHoverBg(t);

Color _ink(ZebuTheme t) => zebuPopoverInk(t);

Color _inkMuted(ZebuTheme t) => zebuPopoverInkMuted(t);

class _MenuPanel<T> extends StatefulWidget {
  const _MenuPanel({
    required this.items,
    required this.search,
    required this.searchHint,
    required this.minWidth,
    required this.maxHeight,
  });

  final List<ZebuPropertyMenuItem<T>> items;
  final ZebuMenuSearch<T>? search;
  final String searchHint;
  final double minWidth;
  final double maxHeight;

  @override
  State<_MenuPanel<T>> createState() => _MenuPanelState<T>();
}

class _MenuPanelState<T> extends State<_MenuPanel<T>> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<ZebuPropertyMenuItem<T>> _remote = const [];
  bool _loading = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.search != null) _fetch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Remote lists always get the box — you cannot scroll to a row that was
  /// never fetched. Local lists get it past the same threshold the rest of the
  /// app uses; below that, four rows are quicker to read than to type.
  bool get _showSearch =>
      widget.search != null || widget.items.length >= kZebuMenuSearchThreshold;

  void _onTyped(String q) {
    setState(() {});
    if (widget.search == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    List<ZebuPropertyMenuItem<T>> rows;
    try {
      rows = await widget.search!(q);
    } catch (_) {
      rows = const [];
    }
    // A slow early request must not overwrite a fast later one — typing
    // "ram" fires three searches and they can land out of order.
    if (!mounted || seq != _seq) return;
    setState(() {
      _remote = rows;
      _loading = false;
    });
  }

  List<ZebuPropertyMenuItem<T>> get _visible {
    if (widget.search != null) return _remote;
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    // The "None" / default entry is never filtered out. It is the way to
    // clear the field, and typing a name that does not match should not take
    // that away.
    return [
      for (final i in widget.items)
        if (i.muted || i.label.toLowerCase().contains(q)) i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final rows = _visible;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          minWidth: widget.minWidth,
          maxWidth: widget.minWidth,
          // Room for the search field on top of the list, so adding it does
          // not cost four rows of what you came here to read.
          maxHeight: widget.maxHeight + (_showSearch ? 46 : 0),
          // Remote rows arrive after the first layout; without a floor the
          // panel opens one row tall and jumps to full height a beat later.
          minHeight: widget.search != null ? 140 : 0,
        ),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _panel(t),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _edge(t)),
          boxShadow: kZebuPopoverShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showSearch) ...[
              ZebuPopoverSearch(
                controller: _query,
                hint: widget.searchHint,
                onChanged: _onTyped,
              ),
              const SizedBox(height: 4),
            ],
            Flexible(
              child: _loading && rows.isEmpty
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      child: Text(
                        'No matches',
                        style: ZebuTextStyles.small(
                          context,
                        ).copyWith(fontSize: 13, color: _inkMuted(t)),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in rows) _MenuRow<T>(item: item),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow<T> extends StatefulWidget {
  const _MenuRow({required this.item});
  final ZebuPropertyMenuItem<T> item;

  @override
  State<_MenuRow<T>> createState() => _MenuRowState<T>();
}

class _MenuRowState<T> extends State<_MenuRow<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final item = widget.item;
    // Idle is the hover tone at zero alpha, never `Colors.transparent` — that
    // is transparent *black*, and a fill lerping from it washes grey.
    final bg = item.selected
        ? _selectedBg(t)
        : (_hover ? _hoverBg(t) : _hoverBg(t).withValues(alpha: 0));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(item.value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              if (item.leading != null) ...[
                item.leading!,
                const SizedBox(width: 9),
              ] else if (item.dotColor != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: item.dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ZebuEllipsisText(
                      item.label,
                      // Medium at rest, semibold when a subtitle sits under
                      // it. Regular rendered `#121212` as grey at 13 px — the
                      // ink was right and the weight was doing the washing
                      // out. Weight goes through the constructor, never
                      // `copyWith`: `google_fonts` picks the face by family
                      // name, so a weight set afterwards changes the number
                      // and not one pixel.
                      style:
                          ZebuTextStyles.small(
                            context,
                            fontWeight: item.subtitle != null
                                ? ZebuFonts.semiBold
                                : ZebuFonts.medium,
                          ).copyWith(
                            fontSize: 13,
                            color: item.muted ? _inkMuted(t) : _ink(t),
                          ),
                    ),
                    if (item.subtitle != null)
                      ZebuEllipsisText(
                        item.subtitle!,
                        style: ZebuTextStyles.small(
                          context,
                          color: _inkMuted(t),
                        ).copyWith(fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (item.selected)
                Padding(
                  padding: const EdgeInsets.only(left: 9),
                  child: ZebuCheckMark(size: 13, color: t.accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Multi-select panel. Shares the single-select panel's chrome — same card,
/// same search box, same row tones — and differs only in carrying a checkbox
/// per row and a footer.
class _MultiPanel<T> extends StatefulWidget {
  const _MultiPanel({
    required this.items,
    required this.search,
    required this.searchHint,
    required this.initial,
    required this.minWidth,
    required this.maxHeight,
  });

  final List<ZebuPropertyMenuItem<T>> items;
  final ZebuMenuSearch<T>? search;
  final String searchHint;
  final Set<T> initial;
  final double minWidth;
  final double maxHeight;

  @override
  State<_MultiPanel<T>> createState() => _MultiPanelState<T>();
}

class _MultiPanelState<T> extends State<_MultiPanel<T>> {
  final _query = TextEditingController();
  late final Set<T> _picked = {...widget.initial};

  /// Rows already chosen, kept aside so a tick survives a search that no
  /// longer returns that row. Without this, ticking someone and then typing a
  /// different name silently dropped them from the list you were building.
  final Map<T, ZebuPropertyMenuItem<T>> _known = {};

  Timer? _debounce;
  List<ZebuPropertyMenuItem<T>> _remote = const [];
  bool _loading = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.search != null) _fetch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onTyped(String q) {
    setState(() {});
    if (widget.search == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _fetch(q));
  }

  Future<void> _fetch(String q) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    List<ZebuPropertyMenuItem<T>> rows;
    try {
      rows = await widget.search!(q);
    } catch (_) {
      rows = const [];
    }
    if (!mounted || seq != _seq) return;
    setState(() {
      _remote = rows;
      _loading = false;
    });
  }

  List<ZebuPropertyMenuItem<T>> get _visible {
    if (widget.search != null) return _remote;
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return [
      for (final i in widget.items)
        if (i.label.toLowerCase().contains(q)) i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final rows = _visible;
    for (final r in rows) {
      _known[r.value] = r;
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          minWidth: widget.minWidth,
          maxWidth: widget.minWidth,
          maxHeight: widget.maxHeight + 92,
          minHeight: widget.search != null ? 180 : 0,
        ),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _panel(t),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _edge(t)),
          boxShadow: kZebuPopoverShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ZebuPopoverSearch(
              controller: _query,
              hint: widget.searchHint,
              onChanged: _onTyped,
            ),
            const SizedBox(height: 4),
            Flexible(
              child: _loading && rows.isEmpty
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      child: Text(
                        'No matches',
                        style: ZebuTextStyles.small(
                          context,
                        ).copyWith(fontSize: 13, color: _inkMuted(t)),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final item in rows)
                            _MultiRow<T>(
                              item: item,
                              checked: _picked.contains(item.value),
                              onToggle: () => setState(
                                () => _picked.contains(item.value)
                                    ? _picked.remove(item.value)
                                    : _picked.add(item.value),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            _MultiFooter(
              count: _picked.length,
              onClear: _picked.isEmpty ? null : () => setState(_picked.clear),
              onDone: () => Navigator.of(context).pop(_picked),
            ),
          ],
        ),
      ),
    );
  }
}

class _MultiRow<T> extends StatefulWidget {
  const _MultiRow({
    required this.item,
    required this.checked,
    required this.onToggle,
  });

  final ZebuPropertyMenuItem<T> item;
  final bool checked;
  final VoidCallback onToggle;

  @override
  State<_MultiRow<T>> createState() => _MultiRowState<T>();
}

class _MultiRowState<T> extends State<_MultiRow<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final item = widget.item;
    final bg = widget.checked
        ? _selectedBg(t)
        : (_hover ? _hoverBg(t) : _hoverBg(t).withValues(alpha: 0));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The whole row toggles, not just the box — a 16 px target inside a
        // 44 px row is a miss waiting to happen.
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              IgnorePointer(
                child: SelectCheckbox(value: widget.checked, onChanged: (_) {}),
              ),
              const SizedBox(width: 10),
              if (item.leading != null) ...[
                item.leading!,
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ZebuEllipsisText(
                      item.label,
                      // Matches the single-select rows — see the note there.
                      style: ZebuTextStyles.small(
                        context,
                        fontWeight: item.subtitle != null
                            ? ZebuFonts.semiBold
                            : ZebuFonts.medium,
                      ).copyWith(fontSize: 13, color: _ink(t)),
                    ),
                    if (item.subtitle != null)
                      ZebuEllipsisText(
                        item.subtitle!,
                        style: ZebuTextStyles.small(
                          context,
                          color: _inkMuted(t),
                        ).copyWith(fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MultiFooter extends StatelessWidget {
  const _MultiFooter({
    required this.count,
    required this.onClear,
    required this.onDone,
  });

  final int count;
  final VoidCallback? onClear;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        Divider(height: 1, thickness: 1, color: _edge(t)),
        const SizedBox(height: 6),
        // Same footer as the date picker, which sits on this exact card a
        // hairline away: a red Clear pinned left, an accent Apply-style action
        // right, neither of them a filled button. A blue slab in one popover
        // and a text link in the other made two identical panels look like
        // two different components.
        Row(
          children: [
            // `Expanded`, not `Spacer` beside a `Flexible` — two flex children
            // split the free space and squeeze the label into half a row.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ZebuTextAction(
                  label: 'Clear',
                  // Unticking everything is the one destructive thing here,
                  // and the tone is what says so. Disabled when there is
                  // nothing to clear rather than hidden, so the footer keeps
                  // its shape as rows are ticked.
                  tone: ZebuActionTone.danger,
                  onTap: onClear,
                ),
              ),
            ),
            ZebuTextAction(
              label: 'Done',
              // Always live, including at zero. Clearing every row *is* the
              // change you came to make, and greying Done there left no way
              // to commit it — the only exits were dismissing, which discards,
              // or re-ticking someone you had just removed.
              onTap: onDone,
            ),
          ],
        ),
      ],
    );
  }
}
