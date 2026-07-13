import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../data/tickets_repository.dart';
import '../../../models/meta.dart';
import '../../../models/ticket.dart';
import '../../../providers.dart';
import '../../../widgets/list_controls.dart' show DateRange;
import '../../../widgets/paged_list_view.dart';
import '../../../widgets/slide_over_host.dart';
import '../../../widgets/web/list_search_input.dart';
import '../../../widgets/web/list_table_shell.dart';
import '../../../widgets/web/page_header.dart';
import '../../../widgets/web/segmented_tab_bar.dart';
import '../../../widgets/web/status_pill.dart';
import '../../../widgets/web_filter_button.dart';
import '../../dashboard/web/_tokens.dart';
import 'ticket_detail_panel.dart';

// Column layout for the tickets table. Header and every row share these
// so the vertical grid lines up pixel-for-pixel without a `Table`/`Row`
// per-cell wrapper.
// Ticket column carries the number + subject and needs the most horizontal
// room; Department is a short label and can afford the tightest flex.
//
// Assignee is intentionally NOT rendered here — the `/tickets` list
// endpoint doesn't return the field, so every row would fall back to
// "Unassigned" regardless of the ticket's real state. The value is
// available (and editable) inside the detail panel where the `/tickets/
// {id}` endpoint carries it.
/// Ticket ID column — fixed 90 px, wide enough for a padded 6-digit
/// ticket like `#020817` at `bodySm` w600 plus the shared `s3` cell
/// padding. Split out of the "Ticket" column so the number reads as its
/// own sortable value.
const double _kColNumberWidth = 90;
const int _kColTicketFlex = 5;
const int _kColRequesterFlex = 2;
// Bumped from 1 to 2 so "Department" doesn't wrap in the header when
// the Assignee column dropped out and squeezed this cell — matches the
// Requester flex so the two mid-columns balance.
const int _kColDeptFlex = 2;
const double _kColPriorityWidth = 130;
const double _kColStatusWidth = 130;
// Wide enough to fit `29 Jun 2026` on one line at the current bodySm
// size — the previous 100 px forced the year to wrap onto a second row.
const double _kColCreatedWidth = 120;

/// Minimum table width — accounts for the fixed-width columns
/// (90 + 130 + 130 + 120 = 470), the 3 px leading accent-stripe rail, and
/// a readable minimum for each flex column. Below this the table
/// horizontally scrolls instead of squeezing columns.
const double _kTableMinWidth = 1120;

/// Web-only tickets list.
///
/// Same data sources as the mobile `TicketsListScreen`
/// ([ticketsRepositoryProvider]) — only the visual language differs:
/// [PageHeader] + [SegmentedTabBar] + a full-width table wrapped in a
/// hairline-bordered surface. The filter popover, sort menu, and PagedListView
/// wiring are unchanged.
class TicketsListScreenWeb extends ConsumerStatefulWidget {
  const TicketsListScreenWeb({super.key});

  @override
  ConsumerState<TicketsListScreenWeb> createState() =>
      _TicketsListScreenWebState();
}

const _views = <({String key, String label})>[
  (key: 'open', label: 'Open'),
  (key: 'mine', label: 'Mine'),
  (key: 'unassigned', label: 'Unassigned'),
  (key: 'overdue', label: 'Overdue'),
  (key: 'answered', label: 'Answered'),
  (key: 'closed', label: 'Closed'),
];

/// Ordered sort options mirrored from the mobile filter menu.
const _sortItems = <({String key, String label})>[
  (key: 'created', label: 'Most Recently Created'),
  (key: 'updated', label: 'Most Recently Updated'),
  (key: 'due', label: 'Due Date'),
  (key: 'number', label: 'Ticket Number'),
];

/// Facet keys we load meta for and expose in the Filter popover.
const _ticketFacets = <({String key, String label, String metaKind})>[
  (key: 'dept', label: 'Department', metaKind: MetaKind.departments),
  (key: 'status', label: 'Status', metaKind: MetaKind.statuses),
  (key: 'priority', label: 'Priority', metaKind: MetaKind.priorities),
  (key: 'agent', label: 'Agent', metaKind: MetaKind.agents),
  (key: 'tag', label: 'Tag', metaKind: MetaKind.tags),
];

class _TicketsListScreenWebState extends ConsumerState<TicketsListScreenWeb> {
  String _view = 'open';
  String _search = '';
  Timer? _debounce;
  Map<String, int> _counts = const {};
  int? _openTicketId;
  bool _fullscreen = false;

  /// Bumped whenever the detail panel signals a mutation. Threaded into
  /// [PagedListView.refreshKey] so the list refetches and the row picks
  /// up the new assignee / status / department instead of staying on
  /// the stale value from the last fetch.
  int _panelChangeSeq = 0;

  // Shared horizontal scroll controller for the table (header + rows).
  // Keeps them in sync when the table overflows below `_kTableMinWidth`.
  final ScrollController _tableHScroll = ScrollController();

  // Client-side priority quick-filter chips.
  final Set<String> _priorityFilters = {};

  // Full filter format: date range, sort, and per-facet selection.
  DateRange _dateRange = DateRange.all;
  String _sort = 'created';
  final Map<String, String> _facetSelected = {
    for (final f in _ticketFacets) f.key: 'all',
  };
  Map<String, List<MetaItem>> _facetOptions = const {};

  void _openTicket(int id) => setState(() => _openTicketId = id);
  // Closing the panel is a pure state change — no refetch on close.
  void _closeTicket() => setState(() {
        _openTicketId = null;
        _fullscreen = false;
      });
  void _toggleFullscreen() => setState(() => _fullscreen = !_fullscreen);

  @override
  void initState() {
    super.initState();
    final requested = ref.read(ticketsViewRequestProvider);
    if (requested != null) {
      _view = requested;
      Future.microtask(
        () => ref.read(ticketsViewRequestProvider.notifier).set(null),
      );
    }
    _loadCounts();
    _loadFacets();
  }

  /// Loads every facet's option list in parallel and caches them on
  /// [_facetOptions] so the Filter popover can render dropdown labels
  /// without a per-open API call.
  Future<void> _loadFacets() async {
    final metaRepo = ref.read(metaRepositoryProvider);
    final entries = await Future.wait(
      _ticketFacets.map((f) async {
        try {
          return MapEntry(f.key, await metaRepo.get(f.metaKind));
        } catch (_) {
          return MapEntry(f.key, const <MetaItem>[]);
        }
      }),
    );
    if (!mounted) return;
    setState(() => _facetOptions = Map.fromEntries(entries));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tableHScroll.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    final repo = ref.read(ticketsRepositoryProvider);
    final entries = await Future.wait(
      _views.map((v) async {
        try {
          return MapEntry(v.key, await repo.count(view: v.key));
        } catch (_) {
          return MapEntry(v.key, -1);
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      _counts = {
        for (final e in entries)
          if (e.value >= 0) e.key: e.value,
      };
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final next = value.trim();
      if (next != _search && mounted) setState(() => _search = next);
    });
  }

  bool _matches(Ticket t, String? meName) {
    final viewOk = switch (_view) {
      'open' => !t.isClosed,
      'closed' => t.isClosed,
      'overdue' => t.isOverdue,
      'unassigned' => (t.assignee ?? '').trim().isEmpty,
      'mine' =>
        meName == null || meName.isEmpty
            ? true
            : (t.assignee ?? '').toLowerCase().contains(meName.toLowerCase()),
      _ => true,
    };
    if (!viewOk) return false;

    // Quick-filter priority buckets (client-side substring match).
    if (_priorityFilters.isNotEmpty) {
      final p = (t.priority ?? '').toLowerCase();
      final hit = _priorityFilters.any((k) => p.contains(k));
      if (!hit) return false;
    }

    // Date range filter — matches against the ticket's created date.
    final bounds = _dateRange.bounds(DateTime.now());
    if (bounds != null) {
      final c = t.created;
      if (c == null) return false;
      final (from, to) = bounds;
      if (c.isBefore(from) || c.isAfter(to)) return false;
    }

    // Facet dropdowns — match by option name (case-insensitive).
    for (final f in _ticketFacets) {
      final sel = _facetSelected[f.key];
      if (sel == null || sel == 'all') continue;
      final option = _facetOptions[f.key]
          ?.where((o) => o.id.toString() == sel)
          .firstOrNull;
      if (option == null) continue;
      final needle = option.name.toLowerCase();
      final haystack = switch (f.key) {
        'dept' => (t.departmentName ?? '').toLowerCase(),
        'status' => t.statusName.toLowerCase(),
        'priority' => (t.priority ?? '').toLowerCase(),
        'agent' => (t.assignee ?? '').toLowerCase(),
        _ => '',
      };
      if (!haystack.contains(needle)) return false;
    }

    final q = _search.trim();
    if (q.isEmpty) return true;
    final needle = _norm(q);
    return _norm(t.number).contains(needle) ||
        _norm(t.subject).contains(needle) ||
        _norm(t.requester ?? '').contains(needle) ||
        _norm(t.assignee ?? '').contains(needle) ||
        _norm(t.departmentName ?? '').contains(needle);
  }

  List<WebQuickFilter> _quickFilters() {
    const buckets = ['Emergency', 'High', 'Normal', 'Low'];
    return [
      for (final label in buckets)
        WebQuickFilter(
          label: label,
          active: _priorityFilters.contains(label.toLowerCase()),
          onToggle: () => setState(() {
            final key = label.toLowerCase();
            if (!_priorityFilters.add(key)) _priorityFilters.remove(key);
          }),
        ),
    ];
  }

  /// Facet-dropdown controls for the popover.
  List<WebFacetControl> _facetControls() {
    return [
      for (final f in _ticketFacets)
        WebFacetControl(
          label: f.label,
          options: [
            (value: 'all', text: 'All ${f.label.toLowerCase()}s'),
            for (final o in _facetOptions[f.key] ?? const <MetaItem>[])
              (value: o.id.toString(), text: o.name),
          ],
          selected: _facetSelected[f.key] ?? 'all',
          onChanged: (v) => setState(() => _facetSelected[f.key] = v),
        ),
    ];
  }

  void _clearAllFilters() {
    setState(() {
      _priorityFilters.clear();
      _dateRange = DateRange.all;
      for (final f in _ticketFacets) {
        _facetSelected[f.key] = 'all';
      }
    });
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[#,\s₹]'), '');

  int _compare(Ticket a, Ticket b) {
    return switch (_sort) {
      'updated' => (b.updated ?? b.created ?? DateTime(0))
          .compareTo(a.updated ?? a.created ?? DateTime(0)),
      'due' => _dueCompare(a.due, b.due),
      'number' => b.number.compareTo(a.number),
      _ => (b.created ?? DateTime(0)).compareTo(a.created ?? DateTime(0)),
    };
  }

  /// Nulls-last so tickets without a due date drop to the bottom of the sort
  /// instead of clumping at the top.
  int _dueCompare(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(ticketsViewRequestProvider, (_, next) {
      if (next == null) return;
      if (next != _view) setState(() => _view = next);
      ref.read(ticketsViewRequestProvider.notifier).set(null);
    });

    final t = WebTokens.of(context);
    final meName = ref.watch(meProvider).asData?.value.name;
    final repo = ref.watch(ticketsRepositoryProvider);
    final query = TicketQuery(view: _view, sort: _sort, order: 'desc');

    // Build the tab items from the fixed view list, folding in live counts
    // as they arrive. If a count hasn't loaded yet the pill is omitted.
    final tabItems = [
      for (final v in _views)
        SegmentedTabItem<String>(
          value: v.key,
          label: v.label,
          count: _counts[v.key],
        ),
    ];

    return SlideOverHost(
      openId: _openTicketId,
      onClose: _closeTicket,
      fullscreen: _fullscreen,
      panelBuilder: (context, id, close) => TicketDetailPanel(
        ticketId: id,
        onClose: close,
        isFullscreen: _fullscreen,
        onToggleFullscreen: _toggleFullscreen,
        // Bump the refresh sequence — the PagedListView below picks
        // this up in its refreshKey and refetches so the row reflects
        // the panel's mutation (assign / transfer / status change).
        onChanged: () => setState(() => _panelChangeSeq++),
      ),
      child: ColoredBox(
        color: t.bgPrimary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Tickets',
              trailing: LayoutBuilder(
                builder: (context, c) {
                  // Search width is responsive to the trailing slot
                  // itself. When the header stays side-by-side the slot
                  // is wide and the search runs the full 360 cap; when
                  // the header stacks under a narrowed list column the
                  // slot expands to the row width and the search still
                  // fits with the filter button beside it.
                  final filterAllowance = 48.0; // filter btn + gap
                  final available =
                      c.hasBoundedWidth ? c.maxWidth - filterAllowance : 360.0;
                  final searchWidth =
                      available.clamp(200.0, 360.0);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      WebFilterButton(
                        filters: _quickFilters(),
                        sort: WebSortControl(
                          options: _sortItems,
                          selected: _sort,
                          onChanged: (k) => setState(() => _sort = k),
                        ),
                        dateRange: WebDateRangeControl(
                          value: _dateRange,
                          onChanged: (r) =>
                              setState(() => _dateRange = r),
                        ),
                        facets: _facetControls(),
                        // Always pass the reset callback — the popover
                        // decides visibility itself from its live local
                        // state. Passing `null` when nothing's active
                        // used to freeze the button visibility at
                        // open-time, so a filter selected after opening
                        // never revealed "Clear all" until reopen.
                        onClear: _clearAllFilters,
                      ),
                      const SizedBox(width: WebTokens.s3),
                      SizedBox(
                        width: searchWidth,
                        child: ListSearchInput(
                          hintText: 'Search',
                          onChanged: _onSearchChanged,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            SegmentedTabBar<String>(
              items: tabItems,
              selected: _view,
              onSelect: (k) => setState(() => _view = k),
            ),
            Expanded(
              child: ListTableShell(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalScroll =
                        constraints.maxWidth <= _kTableMinWidth;
                    final tableWidth = horizontalScroll
                        ? _kTableMinWidth
                        : constraints.maxWidth;
                    return Scrollbar(
                    controller: _tableHScroll,
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    child: SingleChildScrollView(
                      controller: _tableHScroll,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _TableHeader(scrollGutter: horizontalScroll),
                            Expanded(
                              child: ColoredBox(
                                color: t.bgElevated,
                                child: PagedListView<Ticket>(
                                  padding: EdgeInsets.zero,
                                  refreshKey:
                                      '$_view|$_search|$_panelChangeSeq',
                                  itemFilter: (t) => _matches(t, meName),
                                  itemSort: _compare,
                                  emptyMessage: 'No tickets',
                                  emptyHint:
                                      'Try a different filter or search.',
                                  fetch: (page) =>
                                      repo.list(query.copyWith(page: page)),
                                  loadingBuilder: (_) =>
                                      const _TicketTableSkeleton(),
                                  itemBuilder: (context, ticket) =>
                                      _TicketRow(
                                    ticket: ticket,
                                    selected: _openTicketId == ticket.id,
                                    onTap: () => _openTicket(ticket.id),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Table header — column labels rendered on a `bgTertiary` strip so the
// header reads separated from body rows without shadows or extra borders.
// Shares the exact column widths every row uses via the `_kCol*` constants
// so the grid aligns pixel-for-pixel.
// ---------------------------------------------------------------------------

class _TableHeader extends StatelessWidget {
  const _TableHeader({this.scrollGutter = false});

  /// When true, reserves 10 px of trailing space at the right edge of
  /// the header to line up with the horizontal scrollbar sitting under
  /// the body. Off when the table isn't horizontally scrolling — the
  /// gutter would otherwise create a dead strip past "Created".
  final bool scrollGutter;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    // Same structure the Recent Tickets card on the dashboard uses: an
    // IntrinsicHeight Row of `_HeaderCell` boxes whose right-border
    // creates the vertical grid line. Removing the outer horizontal
    // padding keeps the vertical hairlines flush with the last cell's
    // outer edge — same rhythm as the dashboard card.
    return Container(
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(
          top: BorderSide(color: t.borderSubtle, width: 1),
          bottom: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      child: IntrinsicHeight(
        // No leading spacer here — the body row's accent-stripe rail was
        // removed, so a 3 px offset in the header would shift every
        // column 3 px right of its corresponding body cell. Both header
        // and body now start at x = 0.
        child: Row(
          children: [
            const _HeaderCell(width: _kColNumberWidth, label: '#'),
            const _HeaderCell(flex: _kColTicketFlex, label: 'Ticket'),
            const _HeaderCell(flex: _kColRequesterFlex, label: 'Requester'),
            const _HeaderCell(flex: _kColDeptFlex, label: 'Department'),
            const _HeaderCell(width: _kColPriorityWidth, label: 'Priority'),
            const _HeaderCell(width: _kColStatusWidth, label: 'Status'),
            const _HeaderCell(
              width: _kColCreatedWidth,
              label: 'Created',
              alignRight: true,
              last: true,
            ),
            if (scrollGutter) const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

/// Column header cell — mirrors the Recent Tickets `_HeaderCell` exactly
/// so both tables read as one grid: hairline right border (except on the
/// last cell), `s3` horizontal padding, `tableHeader` typography.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    this.flex,
    this.width,
    this.last = false,
    this.alignRight = false,
  });
  final String label;
  final int? flex;
  final double? width;
  final bool last;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s3,
        vertical: WebTokens.s3,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(right: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      // Header labels must stay on one line — "Department" was
      // wrapping to "Depart\nment" when the column got narrow. Ellipsis
      // keeps the row height fixed instead of the header stretching
      // taller than the body rows below.
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: t.tableHeader,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
      ),
    );
    if (flex != null) return Expanded(flex: flex!, child: content);
    if (width != null) return SizedBox(width: width!, child: content);
    return content;
  }
}

/// Body cell — mirrors the Recent Tickets `_BodyCell` exactly.
/// Right-border creates the vertical grid line; 10 px vertical padding
/// gives a tighter table rhythm than the header's `s3`.
class _BodyCell extends StatelessWidget {
  const _BodyCell({
    required this.child,
    this.flex,
    this.width,
    this.last = false,
    this.alignRight = false,
  });
  final Widget child;
  final int? flex;
  final double? width;
  final bool last;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final content = Container(
      // Tighter vertical rhythm (6 px) than the previous 10 px so more
      // rows fit on-screen without feeling squeezed — matches the row
      // heights users typically expect from a data-dense table.
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s3,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(right: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
    if (flex != null) return Expanded(flex: flex!, child: content);
    if (width != null) return SizedBox(width: width!, child: content);
    return content;
  }
}

// ---------------------------------------------------------------------------
// Ticket row — one single-line row per ticket, columns aligned with
// `_TableHeader`. Hover tint and selected-accent-tint match the shell
// treatment (subtle bg fill, no border shift).
// ---------------------------------------------------------------------------

class _TicketRow extends StatefulWidget {
  const _TicketRow({
    required this.ticket,
    required this.onTap,
    this.selected = false,
  });
  final Ticket ticket;
  final VoidCallback onTap;
  final bool selected;

  @override
  State<_TicketRow> createState() => _TicketRowState();
}

class _TicketRowState extends State<_TicketRow> {
  bool _hover = false;

  // Color maps mirror the Recent Tickets card on the dashboard so both
  // tables read as one product: Unassigned = calm info-blue (not alarming
  // amber), Normal priority = info-blue (not dead grey), High = warning
  // amber (Emergency stays red).
  Color _statusColor(WebTokens t) {
    final ticket = widget.ticket;
    if (ticket.isOverdue) return t.danger;
    final s = ticket.statusName.toLowerCase();
    if (s.contains('closed') || s.contains('resolved')) return t.textSecondary;
    if (s.contains('unassigned')) return WebTokens.info;
    if (s.contains('open') || s.contains('new')) return WebTokens.success;
    return WebTokens.info;
  }

  Color _priorityColor(WebTokens t) {
    final p = (widget.ticket.priority ?? '').toLowerCase();
    if (p.contains('emergency') || p.contains('urgent')) return t.danger;
    if (p.contains('high')) return WebTokens.warning;
    if (p.contains('low')) return WebTokens.success;
    if (p.contains('normal')) return WebTokens.info;
    return WebTokens.info;
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final ticket = widget.ticket;
    // Left accent stripe — red on overdue rows (permanent), brand-blue on
    // hover, transparent otherwise. Kept in the layout on every row so
    // content never shifts.
    final Color stripeColor;
    if (ticket.isOverdue) {
      stripeColor = t.danger;
    } else if (widget.selected) {
      stripeColor = t.accent;
    } else if (_hover) {
      stripeColor = t.accent;
    } else {
      stripeColor = Colors.transparent;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            color: widget.selected
                ? t.accentMuted
                : (_hover ? t.bgHover : t.bgElevated),
            border: Border(
              bottom: BorderSide(color: t.borderSubtle, width: 1),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // AnimatedContainer(
                //   duration: const Duration(milliseconds: 120),
                //   curve: Curves.easeOut,
                //   width: 3,
                //   color: stripeColor,
                // ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BodyCell(
                        width: _kColNumberWidth,
                        child: Text(
                          '#${ticket.number}',
                          style: t.bodySm
                              .copyWith(
                                fontWeight: FontWeight.w600,
                                color: t.accent,
                              )
                              .withTabularNums(),
                        ),
                      ),
                      _BodyCell(
                        flex: _kColTicketFlex,
                        child: Text(
                          ticket.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyBase
                              .copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      _BodyCell(
                        flex: _kColRequesterFlex,
                        child: _TextCell(text: ticket.requester ?? ''),
                      ),
                      _BodyCell(
                        flex: _kColDeptFlex,
                        child: _TextCell(text: ticket.departmentName ?? ''),
                      ),
                      _BodyCell(
                        width: _kColPriorityWidth,
                        child: (ticket.priority ?? '').isEmpty
                            ? Text('—', style: t.bodySm)
                            : StatusPill(
                                label: _titleCase(ticket.priority!),
                                color: _priorityColor(t),
                                icon: Icons.flag_rounded,
                              ),
                      ),
                      _BodyCell(
                        width: _kColStatusWidth,
                        child: StatusPill(
                          label: ticket.isOverdue
                              ? 'Overdue'
                              : _titleCase(ticket.statusName),
                          color: _statusColor(t),
                        ),
                      ),
                      _BodyCell(
                        width: _kColCreatedWidth,
                        last: true,
                        alignRight: true,
                        child: Text(
                          Fmt.date(ticket.created),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          textAlign: TextAlign.right,
                          style: t.bodySm
                              .copyWith(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w500,
                              )
                              .withTabularNums(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}

class _TextCell extends StatelessWidget {
  const _TextCell({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final empty = text.trim().isEmpty;
    final display = empty ? '—' : text;
    return Text(
      display,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.bodySm.copyWith(
        color: empty ? t.textSecondary : t.textPrimary,
        fontWeight: empty ? FontWeight.w400 : FontWeight.w500,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton loader — rendered by [PagedListView.loadingBuilder] on the first
// paint before ticket rows arrive. Mirrors the real row's column grid
// (same `_kCol*` widths and `_ColDivider` spacers) so the transition to
// live data is a swap-in-place rather than a layout jump.
// A single shared pulse controller drives the greyscale opacity across
// every placeholder block for a synchronised "one heartbeat" feel.
// ---------------------------------------------------------------------------

class _TicketTableSkeleton extends StatefulWidget {
  const _TicketTableSkeleton();

  @override
  State<_TicketTableSkeleton> createState() => _TicketTableSkeletonState();
}

class _TicketTableSkeletonState extends State<_TicketTableSkeleton>
    with SingleTickerProviderStateMixin {
  // Approximate row height (`_BodyCell` vertical padding × 2 + content
  // height + hairline border) — used only to decide how many skeleton
  // rows to render so the placeholder fills the viewport instead of
  // stopping halfway down.
  static const double _kApproxRowHeight = 32;

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    // Standard controller lifecycle — created in initState, disposed in
    // dispose. Using the constructor-side `..repeat()` on a `late final`
    // field ran the risk of ticking after the widget was unmounted when
    // the parent swapped this skeleton for the loaded rows, which was
    // surfacing as "Trying to render a disposed EngineFlutterView".
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fill the full available height with skeleton rows rather than
        // rendering a fixed eight — otherwise short screens look OK but
        // tall viewports show blank space below the loader.
        final rowCount = constraints.maxHeight.isFinite
            ? (constraints.maxHeight / _kApproxRowHeight).ceil().clamp(6, 40)
            : 12;
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final color = Color.lerp(t.bgTertiary, t.bgHover, _pulse.value)!;
            return ColoredBox(
              color: t.bgElevated,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < rowCount; i++)
                    _SkeletonRow(shade: color),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.shade});
  final Color shade;

  Widget _block(double width) => _SkeletonBlock(width: width, color: shade);

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: IntrinsicHeight(
        // No leading spacer — matches the header and live rows which
        // both start at x = 0 now that the accent stripe rail is gone.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _BodyCell(
              width: _kColNumberWidth,
              child: _block(56),
            ),
            _BodyCell(
              flex: _kColTicketFlex,
              child: _block(260),
            ),
            _BodyCell(
              flex: _kColRequesterFlex,
              child: _block(110),
            ),
            _BodyCell(
              flex: _kColDeptFlex,
              child: _block(60),
            ),
            _BodyCell(
              width: _kColPriorityWidth,
              child: _block(70),
            ),
            _BodyCell(
              width: _kColStatusWidth,
              child: _block(80),
            ),
            _BodyCell(
              width: _kColCreatedWidth,
              last: true,
              alignRight: true,
              child: _block(66),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.width, required this.color});
  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

