import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../data/tickets_repository.dart';
import '../../../models/meta.dart';
import '../../../models/ticket.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/list_controls.dart' show DateRange;
import '../../../widgets/paged_list_view.dart';
import '../../../widgets/slide_over_host.dart';
import '../../../widgets/web/bulk_action_bar.dart';
import '../../../widgets/web/dots_loader.dart';
import '../../../widgets/web/list_search_input.dart';
import '../../../widgets/web/list_table_shell.dart';
import '../../../widgets/web/page_header.dart';
import '../../../widgets/web/segmented_tab_bar.dart';
import '../../../widgets/web/status_badge.dart';
import '../../../widgets/web/zebu_data_grid.dart';
import '../../../widgets/web_filter_button.dart';
import '../../../res/zebu_web_color_styles.dart';
import '../../../res/zebu_text_styles.dart';
import 'ticket_detail_panel.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

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
const double _kColNumberWidth = 100;
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

/// Assignee. Fixed rather than flex so it can't collapse to an initial on a
/// narrow viewport — "who owns this" is the column an agent scans a queue by.
const int _kColAssigneeFlex = 2;

/// Last activity. Same width as Created; both hold `29 Jun 2026` on one line.
const double _kColUpdatedWidth = 120;

/// Fixed table row height, matching the Mynt Plus Web position table's
/// `defaultRowHeight`. Uniform rows also let the layout skip a measure pass.
const double _kRowHeight = 40;

/// Minimum table width — accounts for the fixed-width columns
/// (100 + 130 + 130 + 120 + 120 = 600), the 3 px leading accent-stripe rail,
/// and a readable minimum for each flex column. Below this the table
/// horizontally scrolls instead of squeezing columns.
const double _kTableMinWidth = 1434;

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

/// Ordered saved views, each with the glyph its tab wears.
///
/// The pairings are deliberate: Open and Closed are the same ring with
/// opposite centres — a solid dot (GitHub's "issue open" glyph) against a
/// tick — and Mine/Unassigned are a person against a struck-through person.
/// Same shape, opposite state, readable without reading the label.
const _views = <({String key, String label, IconData icon})>[
  (key: 'open', label: 'Open', icon: Icons.pending_outlined),
  (key: 'mine', label: 'Mine', icon: Icons.person_outline),
  (key: 'unassigned', label: 'Unassigned', icon: Icons.person_off_outlined),
  (key: 'overdue', label: 'Overdue', icon: Icons.schedule_outlined),
  (key: 'answered', label: 'Answered', icon: Icons.mark_chat_read_outlined),
  (key: 'closed', label: 'Closed', icon: Icons.check_circle_outline),
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

  /// The row's own summary for the open ticket, handed to the panel so its
  /// header can paint the number and subject on the first frame instead of
  /// saying "Loading…" for the length of a round trip. The list already has
  /// this data — the panel was throwing it away and refetching.
  Ticket? _openSummary;
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

  // --- Bulk selection ------------------------------------------------------
  /// Ids of tickets ticked via the row checkboxes. Persists across scroll
  /// (appended pages), cleared on view/tab switch since the visible set
  /// changes underneath it.
  final Set<int> _selectedIds = {};

  /// Currently visible (filtered + sorted) tickets, reported by
  /// [PagedListView.onItems] — backs the header select-all + its tri-state.
  List<Ticket> _visibleTickets = const [];

  bool get _allChecked =>
      _visibleTickets.isNotEmpty &&
      _visibleTickets.every((t) => _selectedIds.contains(t.id));
  bool get _someChecked => _selectedIds.isNotEmpty && !_allChecked;

  void _onVisibleTickets(List<Ticket> items) {
    final next = items.map((t) => t.id).toSet();
    final cur = _visibleTickets.map((t) => t.id).toSet();
    if (next.length == cur.length && next.containsAll(cur)) return;
    setState(() => _visibleTickets = items);
  }

  void _toggleChecked(int id) => setState(() {
    if (!_selectedIds.remove(id)) _selectedIds.add(id);
  });

  void _toggleCheckAll() => setState(() {
    if (_allChecked) {
      for (final t in _visibleTickets) {
        _selectedIds.remove(t.id);
      }
    } else {
      for (final t in _visibleTickets) {
        _selectedIds.add(t.id);
      }
    }
  });

  void _clearSelection() => setState(_selectedIds.clear);

  void _toast(String msg, {ToastType type = ToastType.info}) =>
      AppToast.show(context, msg, type: type);

  /// Runs [op] against every selected ticket, tolerating per-item failures,
  /// then clears the selection and bumps the refresh sequence so rows re-fetch.
  Future<void> _bulkRun(
    Future<void> Function(int id) op, {
    required String verb,
  }) async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    var failed = 0;
    for (final id in ids) {
      try {
        await op(id);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
      _panelChangeSeq++;
    });
    final noun = ids.length == 1 ? 'ticket' : 'tickets';
    if (failed == 0) {
      _toast('$verb ${ids.length} $noun', type: ToastType.success);
    } else {
      _toast(
        '$verb ${ids.length - failed}/${ids.length} — $failed failed',
        type: ToastType.error,
      );
    }
  }

  /// Fetches a meta list and opens a picker under [anchor]; returns the id.
  Future<int?> _pickMetaId(BuildContext anchor, String kind) async {
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(kind);
    } catch (e) {
      _toast('$e', type: ToastType.error);
      return null;
    }
    if (!mounted || !anchor.mounted) return null;
    return showAppDropdown<int>(
      anchor,
      entries: [
        for (final m in items) AppDropdownItem<int>(value: m.id, label: m.name),
      ],
    );
  }

  Future<void> _bulkClaim() => _bulkRun(
    (id) async => ref.read(ticketsRepositoryProvider).claim(id),
    verb: 'Claimed',
  );

  Future<void> _bulkAssign(BuildContext anchor) async {
    final agentId = await _pickMetaId(anchor, MetaKind.agents);
    if (agentId == null) return;
    await _bulkRun(
      (id) async =>
          ref.read(ticketsRepositoryProvider).assign(id, staffId: agentId),
      verb: 'Assigned',
    );
  }

  Future<void> _bulkStatus(BuildContext anchor) async {
    final statusId = await _pickMetaId(anchor, MetaKind.statuses);
    if (statusId == null) return;
    await _bulkRun(
      (id) async => ref.read(ticketsRepositoryProvider).setStatus(id, statusId),
      verb: 'Updated',
    );
  }

  Future<void> _bulkPriority(BuildContext anchor) async {
    final priorityId = await _pickMetaId(anchor, MetaKind.priorities);
    if (priorityId == null) return;
    await _bulkRun(
      (id) async =>
          ref.read(ticketsRepositoryProvider).setPriority(id, priorityId),
      verb: 'Updated',
    );
  }

  Future<void> _bulkDelete() async {
    final n = _selectedIds.length;
    if (n == 0) return;
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete $n ${n == 1 ? 'ticket' : 'tickets'}?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    await _bulkRun(
      (id) => ref.read(ticketsRepositoryProvider).delete(id),
      verb: 'Deleted',
    );
  }

  void _openTicket(Ticket ticket) => setState(() {
    _openTicketId = ticket.id;
    _openSummary = ticket;
  });
  // Closing the panel is a pure state change — no refetch on close.
  void _closeTicket() => setState(() {
    _openTicketId = null;
    _openSummary = null;
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

  /// Per-item predicate. All values that are constant across a filter pass
  /// ([meNameLower], date [bounds], the search [needle], and the active
  /// [facetNeedles]) are computed once by the caller and passed in, so the
  /// hot path here does no allocation, `DateTime.now()`, or RegExp compile.
  bool _matches(
    Ticket t, {
    required String? meNameLower,
    required (DateTime, DateTime)? bounds,
    required String? needle,
    required Map<String, String> facetNeedles,
  }) {
    final viewOk = switch (_view) {
      'open' => !t.isClosed,
      'closed' => t.isClosed,
      'overdue' => t.isOverdue,
      'unassigned' => (t.assignee ?? '').trim().isEmpty,
      'mine' =>
        meNameLower == null || meNameLower.isEmpty
            ? true
            : (t.assignee ?? '').toLowerCase().contains(meNameLower),
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
    if (bounds != null) {
      final c = t.created;
      if (c == null) return false;
      final (from, to) = bounds;
      if (c.isBefore(from) || c.isAfter(to)) return false;
    }

    // Facet dropdowns — match by option name (case-insensitive).
    for (final entry in facetNeedles.entries) {
      final haystack = switch (entry.key) {
        'dept' => (t.departmentName ?? '').toLowerCase(),
        'status' => t.statusName.toLowerCase(),
        'priority' => (t.priority ?? '').toLowerCase(),
        'agent' => (t.assignee ?? '').toLowerCase(),
        _ => '',
      };
      if (!haystack.contains(entry.value)) return false;
    }

    if (needle == null) return true;
    return _norm(t.number).contains(needle) ||
        _norm(t.subject).contains(needle) ||
        _norm(t.requester ?? '').contains(needle) ||
        _norm(t.assignee ?? '').contains(needle) ||
        _norm(t.departmentName ?? '').contains(needle);
  }

  /// Resolves the currently-selected facet dropdowns to a
  /// `{facetKey: lowercased option name}` map — computed once per filter pass
  /// instead of re-looked-up per ticket.
  Map<String, String> _activeFacetNeedles() {
    final out = <String, String>{};
    for (final f in _ticketFacets) {
      final sel = _facetSelected[f.key];
      if (sel == null || sel == 'all') continue;
      final option = _facetOptions[f.key]
          ?.where((o) => o.id.toString() == sel)
          .firstOrNull;
      if (option == null) continue;
      out[f.key] = option.name.toLowerCase();
    }
    return out;
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

  // Compiled once — building a fresh RegExp per call was the single heaviest
  // per-item cost, since `_matches` normalizes ~5 fields for every ticket.
  static final RegExp _normPattern = RegExp(r'[#,\s₹]');
  static String _norm(String s) => s.toLowerCase().replaceAll(_normPattern, '');

  int _compare(Ticket a, Ticket b) {
    return switch (_sort) {
      'updated' => (b.updated ?? b.created ?? DateTime(0)).compareTo(
        a.updated ?? a.created ?? DateTime(0),
      ),
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

  /// The grid's single column definition — the header and every row are both
  /// rendered from this list, so the two can no longer drift apart the way
  /// the old hand-written `_TableHeader` / `_TicketRow` pair could.
  ///
  /// Assignee is deliberately absent: the `/tickets` list endpoint doesn't
  /// return it, so every row would read "Unassigned" regardless of the real
  /// state. It is available, and editable, in the detail panel where
  /// `/tickets/{id}` carries it.
  List<ZebuGridColumn<Ticket>> _columns(BuildContext context) {
    return [
      ZebuGridColumn(
        width: _kColNumberWidth,
        label: 'Ticket ID',
        cell: (ticket) => Text(
          '#${ticket.number}',
          style: ZebuTextStyles.tableCell(
            context,
            lightColor: ZebuColors.primary,
            darkColor: ZebuColors.primaryDark,
            fontWeight: ZebuFonts.semiBold,
          ).withTabularNums(),
        ),
      ),
      ZebuGridColumn(
        flex: _kColTicketFlex,
        label: 'Issue summary',
        cell: (ticket) => Text(
          ticket.subject,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ZebuTextStyles.tableCell(context),
        ),
      ),
      ZebuGridColumn(
        flex: _kColRequesterFlex,
        label: 'Requester',
        cell: (ticket) => _TextCell(text: ticket.requester ?? ''),
      ),
      ZebuGridColumn(
        flex: _kColDeptFlex,
        label: 'Department',
        cell: (ticket) => _TextCell(text: ticket.departmentName ?? ''),
      ),
      ZebuGridColumn(
        width: _kColPriorityWidth,
        label: 'Priority',
        cell: (ticket) => (ticket.priority ?? '').isEmpty
            ? Text('\u2014', style: ZebuTextStyles.small(context))
            : PriorityBadge(
                label: _titleCase(ticket.priority!),
                priority: ticket.priority,
              ),
      ),
      ZebuGridColumn(
        width: _kColStatusWidth,
        label: 'Status',
        cell: (ticket) => StatusBadge(
          label: ticket.isOverdue ? 'Overdue' : _titleCase(ticket.statusName),
          status: ticket.statusName,
          overdue: ticket.isOverdue,
        ),
      ),
      ZebuGridColumn(
        flex: _kColAssigneeFlex,
        label: 'Assigned to',
        cell: (ticket) => _TextCell(text: ticket.assignee ?? ''),
      ),
      ZebuGridColumn(
        width: _kColCreatedWidth,
        label: 'Created',
        alignRight: true,
        cell: (ticket) => Text(
          Fmt.date(ticket.created),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.right,
          style: ZebuTextStyles.tableCell(context).withTabularNums(),
        ),
      ),
      ZebuGridColumn(
        width: _kColUpdatedWidth,
        label: 'Last updated',
        alignRight: true,
        // Relative, unlike Created's absolute date. The two answer different
        // questions — Created is a fact you cite, Last updated is "has this
        // gone quiet", and "3 days ago" answers that without arithmetic.
        cell: (ticket) => Text(
          ticket.updated == null ? '—' : Fmt.ago(ticket.updated),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.right,
          style: ticket.updated == null
              ? ZebuTextStyles.small(context)
              : ZebuTextStyles.tableCell(context).withTabularNums(),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(ticketsViewRequestProvider, (_, next) {
      if (next == null) return;
      if (next != _view) setState(() => _view = next);
      ref.read(ticketsViewRequestProvider.notifier).set(null);
    });

    final t = ZebuTheme.of(context);
    final meName = ref.watch(meProvider).asData?.value.name;
    final repo = ref.watch(ticketsRepositoryProvider);
    final query = TicketQuery(view: _view, sort: _sort, order: 'desc');

    // Precompute everything the per-item filter needs exactly once per build,
    // rather than per ticket. `filterKey` captures every input `_matches` /
    // `_compare` read so PagedListView can memoize the filtered+sorted list
    // and skip the work entirely when nothing relevant changed.
    final meNameLower = meName?.toLowerCase();
    final dateBounds = _dateRange.bounds(DateTime.now());
    final searchQuery = _search.trim();
    final searchNeedle = searchQuery.isEmpty ? null : _norm(searchQuery);
    final facetNeedles = _activeFacetNeedles();
    final filterKey = Object.hash(
      _view,
      _sort,
      searchQuery,
      meNameLower,
      _dateRange,
      Object.hashAll(_priorityFilters),
      Object.hashAllUnordered([
        for (final e in facetNeedles.entries) '${e.key}=${e.value}',
      ]),
    );

    // Build the tab items from the fixed view list, folding in live counts
    // as they arrive. If a count hasn't loaded yet the pill is omitted.
    // Dot colors mirror the mobile `_viewColor` mapping.
    final tabItems = [
      for (final v in _views)
        SegmentedTabItem<String>(
          value: v.key,
          label: v.label,
          count: _counts[v.key],
          icon: v.icon,
        ),
    ];

    return SlideOverHost(
      openId: _openTicketId,
      onClose: _closeTicket,
      fullscreen: _fullscreen,
      panelBuilder: (context, id, close) => TicketDetailPanel(
        ticketId: id,
        initialTicket: _openSummary?.id == id ? _openSummary : null,
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
                  final available = c.hasBoundedWidth
                      ? c.maxWidth - filterAllowance
                      : 360.0;
                  final searchWidth = available.clamp(200.0, 360.0);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: searchWidth,
                        child: ListSearchInput(
                          hintText: 'Search',
                          onChanged: _onSearchChanged,
                        ),
                      ),
                      const SizedBox(width: ZebuSpacing.s3),

                      WebFilterButton(
                        filters: _quickFilters(),
                        sort: WebSortControl(
                          options: _sortItems,
                          selected: _sort,
                          onChanged: (k) => setState(() => _sort = k),
                        ),
                        dateRange: WebDateRangeControl(
                          value: _dateRange,
                          onChanged: (r) => setState(() => _dateRange = r),
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
                    ],
                  );
                },
              ),
            ),
            SegmentedTabBar<String>(
              items: tabItems,
              selected: _view,
              // Switching tabs refetches a different view, so the ticked rows
              // would no longer be visible — clear the selection with it.
              onSelect: (k) => setState(() {
                _view = k;
                _selectedIds.clear();
              }),
            ),
            if (_selectedIds.isNotEmpty)
              WebBulkBar(
                count: _selectedIds.length,
                onClear: _clearSelection,
                actions: [
                  WebBulkButton(
                    icon: Icons.person_pin_circle_outlined,
                    label: 'Assign to me',
                    onTap: (_) => _bulkClaim(),
                  ),
                  WebBulkButton(
                    icon: Icons.assignment_ind_outlined,
                    label: 'Assign',
                    hasMenu: true,
                    onTap: _bulkAssign,
                  ),
                  WebBulkButton(
                    icon: Icons.label_outline,
                    label: 'Status',
                    hasMenu: true,
                    onTap: _bulkStatus,
                  ),
                  WebBulkButton(
                    icon: Icons.flag_outlined,
                    label: 'Priority',
                    hasMenu: true,
                    onTap: _bulkPriority,
                  ),
                  WebBulkButton(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    tone: t.danger,
                    onTap: (_) => _bulkDelete(),
                  ),
                ],
              ),
            Expanded(
              child: ListTableShell(
                child: ZebuDataGrid<Ticket>(
                  columns: _columns(context),
                  minWidth: _kTableMinWidth,
                  rowHeight: _kRowHeight,
                  selection: ZebuGridSelection(
                    allChecked: _allChecked,
                    someChecked: _someChecked,
                    onToggleAll: _toggleCheckAll,
                  ),
                  body: (context, row) => PagedListView<Ticket>(
                    padding: EdgeInsets.zero,
                    refreshKey: '$_view|$_search|$_panelChangeSeq',
                    filterKey: filterKey,
                    itemFilter: (ticket) => _matches(
                      ticket,
                      meNameLower: meNameLower,
                      bounds: dateBounds,
                      needle: searchNeedle,
                      facetNeedles: facetNeedles,
                    ),
                    itemSort: _compare,
                    emptyMessage: 'No tickets',
                    emptyHint: 'Try a different filter or search.',
                    fetch: (page) => repo.list(query.copyWith(page: page)),
                    loadingBuilder: (_) => const DotsLoader(),
                    onItems: _onVisibleTickets,
                    itemBuilder: (context, ticket) => row(
                      ticket,
                      selected: _openTicketId == ticket.id,
                      checked: _selectedIds.contains(ticket.id),
                      onToggleChecked: () => _toggleChecked(ticket.id),
                      onTap: () => _openTicket(ticket),
                    ),
                  ),
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

// ---------------------------------------------------------------------------
// Ticket row — one single-line row per ticket, columns aligned with
// `_TableHeader`. Hover tint and selected-accent-tint match the shell
// treatment (subtle bg fill, no border shift).
// ---------------------------------------------------------------------------

String _titleCase(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

class _TextCell extends StatelessWidget {
  const _TextCell({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final empty = text.trim().isEmpty;
    final display = empty ? '—' : text;
    return Text(
      display,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // Placeholder dashes read lighter than real values.
      style: empty
          ? ZebuTextStyles.small(context)
          : ZebuTextStyles.tableCell(context),
    );
  }
}
