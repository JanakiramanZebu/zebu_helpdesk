import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/assets.dart';
import '../../core/export/table_export.dart';
import '../../core/format.dart';
import '../../core/list_layout.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../data/tickets_repository.dart';
import '../../models/meta.dart';
import '../../models/ticket.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/filter_chip_tabs.dart';
import '../../widgets/filter_sheet.dart';
import '../../widgets/glass.dart';
import '../../widgets/list_controls.dart';
import '../../widgets/paged_list_view.dart';
import '../../widgets/pickers.dart';
import '../../widgets/selection_controls.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/svg_icon.dart';
import 'widgets/ticket_row.dart';

/// App filter pills (the `view` param on GET /tickets). Order/labels mirror the
/// web Tickets nav's default system queues exactly: Open · All Tickets ·
/// My Tickets · Closed. ("Search" is the search bar + filter button, and
/// "New Ticket" is the bottom-nav "+", so neither is a tab here.) `all` returns
/// the full visible set server-side.
const _views = <({String key, String label})>[
  (key: 'open', label: 'Open'),
  (key: 'all', label: 'All Tickets'),
  (key: 'mine', label: 'My Tickets'),
  (key: 'closed', label: 'Closed'),
];

/// Sort options (the `sort` param on GET /tickets), mirroring the web menu.
const _sortItems = <({String key, String label})>[
  (key: 'updated', label: 'Most Recently Updated'),
  (key: 'created', label: 'Most Recently Created'),
  (key: 'due', label: 'Due Date'),
  (key: 'number', label: 'Ticket Number'),
  (key: 'thread', label: 'Longest Thread'),
];

/// Advanced filter facets opened from the search bar's filter button.
const _filterFacets = <FilterFacet>[
  FilterFacet(key: 'dept', label: 'Department', metaKind: MetaKind.departments),
  FilterFacet(key: 'status', label: 'Status', metaKind: MetaKind.statuses),
  FilterFacet(key: 'priority', label: 'Priority', metaKind: MetaKind.priorities),
  FilterFacet(key: 'agent', label: 'Agent', metaKind: MetaKind.agents),
  FilterFacet(key: 'tag', label: 'Tag', metaKind: MetaKind.tags),
];

class TicketsListScreen extends ConsumerStatefulWidget {
  const TicketsListScreen({super.key});

  @override
  ConsumerState<TicketsListScreen> createState() => _TicketsListScreenState();
}

class _TicketsListScreenState extends ConsumerState<TicketsListScreen> {
  String _view = 'open';
  // Drives the swipeable filter pages; kept in sync with [_view] and the chips.
  late final PageController _pageController;
  String _search = '';
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  int? _total;
  int _refresh = 0;
  bool _exporting = false;

  // Filter + sort controls.
  DateRange _dateRange = DateRange.all;
  String _sort = 'created';
  final Map<String, MetaItem?> _filters = {};
  Map<String, List<MetaItem>> _facetOptions = const {};

  // Multi-select / bulk state.
  final Set<int> _selected = {};
  List<int> _visibleIds = const [];
  bool _bulkBusy = false;

  /// Department name per row seen so far, so a bulk assign can scope its agent
  /// picker the way the detail screen does. List rows only carry the name (the
  /// summary payload has no department id), which is all the scope needs.
  final Map<int, String> _deptOf = {};

  // Per-tab count badges.
  Map<String, int> _counts = const {};

  // Assignee names resolved via the detail endpoint for rows whose list
  // summary lacks the field (the list API doesn't send `assignee` yet).
  // Keyed by ticket id, cached for the session — powers search-by-assignee
  // and the Agent facet until the backend adds the field to list rows.
  final Map<int, String?> _assignees = {};
  final Set<int> _assigneeFetching = {};

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Honor a filter requested before this screen was first built (e.g. tapping
    // a dashboard stat tile that switched to the Tickets tab).
    final requested = ref.read(ticketsViewRequestProvider);
    if (requested != null) {
      _view = requested;
      Future.microtask(
        () => ref.read(ticketsViewRequestProvider.notifier).set(null),
      );
    }
    _pageController = PageController(initialPage: _indexOf(_view));
    _loadCounts();
    _loadFacets();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // --- Tab / page sync ------------------------------------------------------

  int _indexOf(String view) {
    final i = _views.indexWhere((v) => v.key == view);
    return i < 0 ? 0 : i;
  }

  /// Chip tapped → highlight it immediately, then move the pager. Neighboring
  /// pages glide; distant ones jump so the PageView doesn't build every list in
  /// between. [_onPageChanged] re-adopts the same view when the move settles.
  void _selectView(String view) {
    if (view == _view) return;
    final from = _indexOf(_view);
    final to = _indexOf(view);
    _adoptView(view);
    if (!_pageController.hasClients) return;
    if ((to - from).abs() > 1) {
      _pageController.jumpToPage(to);
    } else {
      _pageController.animateToPage(
        to,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Swipe settled on a new page → adopt that view.
  void _onPageChanged(int index) {
    final next = _views[index].key;
    if (next != _view) _adoptView(next);
  }

  /// Switch the active view, dropping any multi-select that belonged to the
  /// one we're leaving.
  ///
  /// Selection is inherently per-view: [_visibleIds] only ever tracks the
  /// ACTIVE list, so a selection carried across tabs leaves the "N selected"
  /// count — and every bulk action, including delete — pointing at tickets the
  /// user can no longer see. Clearing [_visibleIds] too keeps select-all from
  /// acting on the old tab's rows in the frame before the new list reports in.
  void _adoptView(String next) {
    setState(() {
      _view = next;
      _selected.clear();
      _visibleIds = const [];
    });
  }

  /// Jump the pager to [view] without animation (cross-tab filter requests).
  void _jumpToView(String view) {
    _adoptView(view);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(_indexOf(view));
    }
  }

  void _toast(String msg) => AppSnack.info(context, msg);

  /// True when [view]'s badge must be counted client-side: My Tickets (server
  /// view=mine also counts closed assignments), or ANY filter active — the
  /// backend drops the `view` scope whenever a filter param is present, so its
  /// per-tab totals are untrustworthy under filters; [_countable]'s membership
  /// guards + exact date bounds produce the correct numbers instead.
  bool _clientCounted(String view) =>
      view == 'mine' ||
      _dateRange != DateRange.all ||
      _search.trim().isNotEmpty ||
      _filters.values.any((v) => v != null);

  /// Fetch the count for every tab in parallel, honoring the active facet and
  /// date filters so the badges always match what each tab would show.
  Future<void> _loadCounts() async {
    final repo = ref.read(ticketsRepositoryProvider);
    final entries = await Future.wait(
      _views.map((v) async {
        try {
          if (_clientCounted(v.key)) {
            // _matches = membership + facets + date + live search text, so
            // the badge counts exactly what the tab would display.
            final rows = await _gatherAll(_queryFor(v.key));
            return MapEntry(v.key, rows.where((t) => _matches(t, v.key)).length);
          }
          return MapEntry(v.key, await repo.count(query: _queryFor(v.key)));
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
      // Keep the app-bar total in step with the corrected My Tickets count.
      if (_view == 'mine' && _counts['mine'] != null) _total = _counts['mine'];
    });
  }

  /// Debounced live search — narrows the list as the user types, and recounts
  /// the tab badges so they follow the search text.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final next = value.trim();
      if (next != _search && mounted) {
        setState(() => _search = next);
        _loadCounts();
      }
    });
  }

  void _applySearch(String value) {
    _debounce?.cancel();
    final next = value.trim();
    if (next != _search) {
      setState(() => _search = next);
      _loadCounts();
    }
  }

  String get _order => _sort == 'due' ? 'asc' : 'desc';

  /// Semantic dot color for each view chip, mirroring the dashboard's status
  /// palette (open green, mine brand, closed grey, all neutral accent).
  static Color _viewColor(String key) => switch (key) {
    'open' => AppTheme.open,
    'mine' => Glass.indigo, // My Tickets
    'closed' => AppTheme.closed,
    _ => Glass.accent, // 'all' (All Tickets)
  };

  (DateTime, DateTime)? get _dateBounds => _dateRange.bounds(DateTime.now());

  /// Refetch the server list whenever the filter selection changes.
  String get _filterSig =>
      _filters.entries.map((e) => '${e.key}:${e.value?.id}').join(',');

  /// Load every facet's option list (cached by the meta repository) so the
  /// dropdown pills can offer choices.
  Future<void> _loadFacets() async {
    final repo = ref.read(metaRepositoryProvider);
    final entries = await Future.wait(
      _filterFacets.map((f) async {
        try {
          return MapEntry(f.key, await repo.get(f.metaKind));
        } catch (_) {
          return MapEntry(f.key, <MetaItem>[]);
        }
      }),
    );
    if (!mounted) return;
    setState(() => _facetOptions = {for (final e in entries) e.key: e.value});
  }

  /// Whether any create-date or facet filter is currently narrowing the list
  /// (drives the search bar's filter-button active state). Sort is excluded — it
  /// reorders rather than filters.
  bool get _hasActiveFilters =>
      _dateRange != DateRange.all || _filters.values.any((v) => v != null);

  /// Open the filter/sort bottom sheet and apply the result on Apply.
  Future<void> _openFilters() async {
    final result = await showFilterSheet(
      context: context,
      dateRange: _dateRange,
      sort: _sort,
      defaultSort: 'created',
      sortItems: _sortItems,
      facets: _filterFacets,
      facetOptions: _facetOptions,
      selected: _filters,
    );
    if (result == null || !mounted) return;
    setState(() {
      _dateRange = result.dateRange;
      _sort = result.sort;
      _filters
        ..clear()
        ..addAll(result.filters);
    });
    // Badges follow the facet/date selection, so recount with the new filters.
    _loadCounts();
  }

  // Search and the date range are also enforced client-side (see [_matches]);
  // the query carries the tab's view, sort, create-date window and facet
  // filters for the server.
  TicketQuery _queryFor(String view) {
    final b = _dateBounds;
    // Send status_id to the server only on All Tickets: the backend lets
    // status override view (instead of ANDing), so on the other tabs the
    // status facet is enforced client-side in [_matches] to avoid the leak.
    final status = view == 'all' ? _filters['status'] : null;
    final tag = _filters['tag'];
    return TicketQuery(
      view: view,
      sort: _sort,
      order: _order,
      // The server compares created_from/to against UTC timestamps while our
      // bounds are local (IST), so convert the local window's endpoints to
      // UTC before taking their calendar dates — e.g. "Today" (15 Aug IST)
      // becomes 14..15 Aug UTC, which fully covers 15 Aug IST. The server
      // window is therefore a superset; [_countable] applies the exact local
      // bounds on top.
      createdFrom: b == null ? null : Fmt.apiDate(b.$1.toUtc()),
      createdTo: b == null ? null : Fmt.apiDate(b.$2.toUtc()),
      deptId: _filters['dept']?.id,
      statusId: status == null ? null : [status.id],
      priorityId: _filters['priority']?.id,
      // My Tickets always pins the assignee to the signed-in agent (like the
      // web's assigned-to-me queue): with any filter param present the server
      // skips view=mine, so without this pin other agents' tickets leak in.
      // The Agent facet is meaningless on this tab — it's always "me".
      assigneeId: view == 'mine' ? (_myStaffId ?? _filters['agent']?.id) : _filters['agent']?.id,
      tagId: tag == null ? null : [tag.id],
    );
  }

  /// The signed-in agent's staff id, from the cached session snapshot.
  int? get _myStaffId {
    final raw = ref.read(authControllerProvider).agent['id'];
    if (raw is num) return raw.toInt();
    return int.tryParse('$raw');
  }

  /// The best-known assignee for [t]: the list row's own value, else the
  /// session-cached detail lookup (see [_resolveAssignees]).
  String? _assigneeOf(Ticket t) => t.assignee ?? _assignees[t.id];

  /// Resolve missing assignees for freshly loaded [rows] — one detail fetch
  /// per ticket per session, sequential to stay gentle on the API — then
  /// rebuild so the search/facet filters see the resolved names.
  void _resolveAssignees(List<Ticket> rows) {
    final pending = [
      for (final t in rows)
        if (t.assignee == null &&
            !_assignees.containsKey(t.id) &&
            !_assigneeFetching.contains(t.id))
          t.id,
    ];
    if (pending.isEmpty) return;
    _assigneeFetching.addAll(pending);
    Future(() async {
      final repo = ref.read(ticketsRepositoryProvider);
      for (final id in pending) {
        try {
          _assignees[id] = (await repo.get(id)).assignee;
        } catch (_) {
          // Leave unresolved; a later page load may retry.
        } finally {
          _assigneeFetching.remove(id);
        }
      }
      if (!mounted) return;
      setState(() {});
      // Newly resolved names can change what an assignee search / Agent facet
      // matches — settle the badges. Safe from looping: a second pass finds
      // every id already cached and returns before reaching here.
      if (_search.trim().isNotEmpty || _filters['agent'] != null) _loadCounts();
    });
  }

  /// Client-side comparator matching the active sort (null for 'thread', which
  /// the list model can't order — that one relies on the server).
  int _compare(Ticket a, Ticket b) {
    int desc(DateTime? x, DateTime? y) =>
        (y ?? DateTime(0)).compareTo(x ?? DateTime(0));
    switch (_sort) {
      case 'updated':
        return desc(a.updated, b.updated);
      case 'due':
        if (a.due == null && b.due == null) return 0;
        if (a.due == null) return 1; // nulls last
        if (b.due == null) return -1;
        return a.due!.compareTo(b.due!); // soonest first
      case 'number':
        return (int.tryParse(b.number) ?? 0).compareTo(
          int.tryParse(a.number) ?? 0,
        );
      default: // 'created'
        return desc(a.created, b.created);
    }
  }

  // --- Selection ------------------------------------------------------------

  void _onItems(List<Ticket> items) {
    final ids = items.map((t) => t.id).toList();
    for (final t in items) {
      final dept = t.departmentName?.trim();
      if (dept != null && dept.isNotEmpty) _deptOf[t.id] = dept;
    }
    if (!listEquals(ids, _visibleIds)) setState(() => _visibleIds = ids);
  }

  /// The single department every selected row sits in, or null when the
  /// selection spans departments (or a row's department is unknown) — then the
  /// agent picker can't be scoped and offers everyone.
  String? get _selectedDepartment {
    String? shared;
    for (final id in _selected) {
      final dept = _deptOf[id];
      if (dept == null) return null;
      if (shared == null) {
        shared = dept;
      } else if (shared.toLowerCase() != dept.toLowerCase()) {
        return null;
      }
    }
    return shared;
  }

  void _toggle(int id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  void _clearSelection() => setState(_selected.clear);

  bool get _allVisibleSelected =>
      _visibleIds.isNotEmpty && _visibleIds.every(_selected.contains);

  void _toggleSelectAll() => setState(() {
    if (_allVisibleSelected) {
      _selected.removeWhere(_visibleIds.contains);
    } else {
      _selected.addAll(_visibleIds);
    }
  });

  // --- Bulk actions ---------------------------------------------------------

  Future<int?> _pickMeta(String kind, String title) async {
    final items = await ref.read(metaRepositoryProvider).get(kind);
    if (!mounted) return null;
    // Shared sheet: height-capped and scrollable, and it grows a search box
    // once the list is long enough to be tedious to scan — agent lists usually
    // are. Same rule as the ticket-details pickers.
    final picked = await pickChoice(
      context,
      title: title,
      choices: {for (final m in items) '${m.id}': m.name},
    );
    return picked == null ? null : int.tryParse(picked);
  }

  Future<void> _runBulk(String verb, Future<void> Function(int id) op) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    setState(() => _bulkBusy = true);
    var ok = 0;
    var fail = 0;
    for (final id in ids) {
      try {
        await op(id);
        ok++;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    setState(() {
      _bulkBusy = false;
      _selected.clear();
      _refresh++;
    });
    _loadCounts();
    final noun = ok == 1 ? 'ticket' : 'tickets';
    _toast(fail == 0 ? '$verb $ok $noun' : '$verb $ok $noun · $fail failed');
  }

  Future<void> _onBulkMenu(String action) async {
    final repo = ref.read(ticketsRepositoryProvider);
    switch (action) {
      case 'assign':
        // Scoped to the selection's department when they share one, so the
        // sheet doesn't offer agents the server would reject.
        final agent = await pickAgent(
          context,
          ref,
          departmentName: _selectedDepartment,
          title: 'Assign to agent',
        );
        if (agent != null) {
          await _runBulk('Assigned', (t) => repo.assign(t, staffId: agent.id));
        }
      case 'status':
        final id = await _pickMeta(MetaKind.statuses, 'Set status');
        if (id != null) await _runBulk('Updated', (t) => repo.setStatus(t, id));
      case 'priority':
        final id = await _pickMeta(MetaKind.priorities, 'Set priority');
        if (id != null) {
          await _runBulk('Updated', (t) => repo.setPriority(t, id));
        }
      case 'delete':
        await _confirmBulkDelete();
    }
  }

  Future<void> _confirmBulkDelete() async {
    final n = _selected.length;
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete $n ticket${n == 1 ? '' : 's'}?',
      message: 'This permanently removes the selected tickets.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok == true) {
      await _runBulk('Deleted', (t) => ref.read(ticketsRepositoryProvider).delete(t));
    }
  }

  // --- Export ---------------------------------------------------------------

  Future<List<Ticket>> _gatherAll(TicketQuery base) async {
    final repo = ref.read(ticketsRepositoryProvider);
    final all = <Ticket>[];
    const maxRows = 2000;
    var page = 1;
    while (all.length < maxRows) {
      final res = await repo.list(base.copyWith(page: page, limit: 100));
      all.addAll(res.items);
      if (!res.hasMore || res.items.isEmpty) break;
      page++;
    }
    return all;
  }

  Future<void> _runExport(ExportFormat format) async {
    final view = _views.firstWhere((v) => v.key == _view).label;
    setState(() => _exporting = true);
    try {
      // Export exactly what's visible: the view's rows, narrowed by the active
      // search.
      final tickets = (await _gatherAll(_queryFor(_view)))
          .where((t) => _matches(t, _view))
          .toList();
      if (tickets.isEmpty) {
        _toast('No tickets to export');
        return;
      }
      await exportTable(
        format: format,
        baseName: 'tickets-$_view',
        title: 'Tickets ($view)',
        columns: const [
          '#',
          'Subject',
          'Status',
          'Priority',
          'Department',
          'Requester',
          'Assignee',
          'Created',
          'Due',
        ],
        rows: [
          for (final t in tickets)
            [
              t.number,
              t.subject,
              t.statusName,
              t.priority ?? '',
              t.departmentName ?? '',
              t.requester ?? '',
              t.assignee ?? '',
              Fmt.date(t.created),
              Fmt.date(t.due),
            ],
        ],
      );
      if (mounted) {
        _toast('Exported ${tickets.length} tickets as ${format.label}');
      }
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Saved file but could not open it automatically');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Tab-membership + date-window + facet checks shared by the visible list
  /// ([_matches]) and the tab count badges — everything except the live search
  /// text, which narrows the list but not the badges.
  ///
  /// Open/closed membership IS re-derived here (the status name marks closed
  /// reliably) because the backend lets filter params override `view`, leaking
  /// rows across tabs. Overdue/answered membership is still left to the server
  /// — the list rows don't carry those flags reliably, and re-deriving them
  /// once emptied the Overdue tab.
  bool _countable(Ticket t, String view) {
    // Tab membership guards. "My Tickets" shows only OPEN tickets assigned to
    // me, matching the web queue (the server's view=mine also returns closed
    // assignments).
    if (view == 'mine' && t.isClosed) return false;
    if (view == 'open' && t.isClosed) return false;
    if (view == 'closed' && !t.isClosed) return false;

    final b = _dateBounds;
    if (b != null) {
      final c = t.created;
      if (c == null || c.isBefore(b.$1) || c.isAfter(b.$2)) return false;
    }

    // Facet filters (best-effort, by name; tags have no list-row data so they
    // rely on the server query). Status is enforced here on every tab so it
    // ANDs with the tab's own membership — a contradictory pick (Closed
    // status on the Open tab) yields an empty list, never leaked rows.
    return _facetOk(_filters['dept'], t.departmentName) &&
        _facetOk(_filters['status'], t.statusName) &&
        _facetOk(_filters['priority'], t.priority) &&
        _facetOk(_filters['agent'], _assigneeOf(t));
  }

  bool _matches(Ticket t, String view) {
    if (!_countable(t, view)) return false;

    final q = _search.trim();
    if (q.isEmpty) return true;
    // Normalize away the `#`, commas and spaces so "pa", "INV-26", or a raw
    // amount like "100852" all match (e.g. against "₹1,00,852.24").
    final needle = _norm(q);
    return _norm(t.number).contains(needle) ||
        _norm(t.subject).contains(needle) ||
        _norm(t.requester ?? '').contains(needle) ||
        _norm(_assigneeOf(t) ?? '').contains(needle) ||
        _norm(t.departmentName ?? '').contains(needle);
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[#,\s₹]'), '');

  /// True when no facet is selected, or the row's [value] matches the selected
  /// item's name (case-insensitive).
  ///
  /// A row that doesn't carry the field at all (list rows omit `assignee`
  /// entirely and `priority` when it's Normal) also passes — the server
  /// already filtered by the facet's id, so unknown must not mean "drop", or
  /// the Agent/Priority filters wipe out their own results.
  static bool _facetOk(MetaItem? selected, String? value) {
    if (selected == null) return true;
    final v = (value ?? '').trim();
    if (v.isEmpty) return true;
    return v.toLowerCase() == selected.name.trim().toLowerCase();
  }

  // --- UI -------------------------------------------------------------------

  /// The select-all bar shown above the list while in selection mode.
  Widget _selectionBar() => SelectionBar(
    allSelected: _allVisibleSelected,
    onToggleSelectAll: _toggleSelectAll,
  );

  PreferredSizeWidget _selectionAppBar() => buildSelectionAppBar(
    context,
    selectedCount: _selected.length,
    onCancel: _clearSelection,
    busy: _bulkBusy,
    primaryAction: IconButton(
      tooltip: 'Assign to me',
      icon: const SvgIcon(Assets.claim, size: 22),
      onPressed: () => _runBulk(
        'Claimed',
        (t) => ref.read(ticketsRepositoryProvider).claim(t),
      ),
    ),
    onMenuSelected: _onBulkMenu,
    menuItems: [
      selectionMenuItem(context, value: 'assign', label: 'Assign to agent…'),
      selectionMenuItem(context, value: 'status', label: 'Set status…'),
      selectionMenuItem(context, value: 'priority', label: 'Set priority…'),
      selectionMenuItem(
        context,
        value: 'delete',
        label: 'Delete',
        destructive: true,
      ),
    ],
  );

  PreferredSizeWidget _normalAppBar(bool compact) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.titleText(context, 'Tickets', fw: 1),
          if (_total != null)
            AppText.paraText(context, '$_total total'),
        ],
      ),
      actions: [
        IconButton(
          tooltip: compact ? 'Comfortable view' : 'Compact view',
          icon: Icon(
            compact ? Icons.view_agenda_outlined : Icons.view_headline,
          ),
          onPressed: () => ref.read(listLayoutProvider.notifier).toggle(),
        ),
        ExportMenuButton(busy: _exporting, onSelected: _runExport),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(84),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: AppSearchField(
                controller: _searchCtrl,
                hintText: 'Search tickets',
                autofocus: false,
                onChanged: _onSearchChanged,
                onSubmitted: _applySearch,
                onClear: () => _applySearch(''),
                trailing: FilterButton(
                  active: _hasActiveFilters,
                  onTap: _openFilters,
                ),
              ),
            ),
            FilterChipTabs(
              items: _views,
              selectedKey: _view,
              counts: _counts,
              colorFor: _viewColor,
              onSelected: _selectView,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Apply a filter requested from another tab while this screen is already
    // alive (the shell keeps branches in an IndexedStack), then clear it.
    // Any ticket mutation (create/edit/bulk, from any screen) refetches the
    // lists via refreshKey — recount the tab badges in the same beat (TC_150).
    ref.listen<int>(ticketsChangedProvider, (prev, next) {
      if (prev != next) _loadCounts();
    });
    ref.listen<String?>(ticketsViewRequestProvider, (_, next) {
      if (next == null) return;
      if (next != _view) _jumpToView(next);
      ref.read(ticketsViewRequestProvider.notifier).set(null);
    });

    final layout = ref.watch(listLayoutProvider);
    final compact = layout == ListLayout.compact;

    return Scaffold(
      appBar: _selectionMode ? _selectionAppBar() : _normalAppBar(compact),
      // Creating a ticket now lives on the bottom nav's center "+" button.
      body: Glass.listBackdrop(
        context: context,
        child: Column(
          children: [
            if (_selectionMode) _selectionBar(),
            Expanded(
              // Each filter tab is a swipeable page; the chips above jump the
              // pager and a swipe adopts the target view. Swiping is locked
              // during multi-select so bulk actions stay on one list.
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                physics: _selectionMode
                    ? const NeverScrollableScrollPhysics()
                    : null,
                itemCount: _views.length,
                itemBuilder: (context, index) =>
                    _buildList(_views[index].key, compact),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The paginated list for a single filter [view] — one PageView page.
  Widget _buildList(String view, bool compact) {
    final active = view == _view;
    final repo = ref.watch(ticketsRepositoryProvider);
    // Refetch this list whenever a ticket is mutated anywhere (e.g. edited on
    // the detail screen) — folded into refreshKey below.
    final changed = ref.watch(ticketsChangedProvider);
    final query = _queryFor(view);
    return PagedListView<Ticket>(
      fabClearance: !_selectionMode,
      skeleton: ListSkeleton(compact: compact),
      separated: compact,
      refreshKey: '$view|${_dateRange.name}|$_sort|$_filterSig|$_refresh|$changed',
      itemFilter: (t) => _matches(t, view),
      // 'thread' and 'due' rely on the server's ordering: list rows don't
      // carry those values, and re-sorting locally on all-equal (null) keys
      // scrambles the server's correct order (Dart's sort isn't stable).
      itemSort: (_sort == 'thread' || _sort == 'due') ? null : _compare,
      // Pull-to-refresh must also refresh the tab badges (TC_150).
      onRefresh: _loadCounts,
      // Only the visible page feeds selection state and the app-bar total.
      onItems: active ? _onItems : null,
      onTotalChanged: active
          ? (t) {
              // Tabs counted client-side (see _clientCounted) show the
              // recounted badge value; the raw server total would ignore the
              // client-enforced narrowing.
              final clientCounted = _clientCounted(view);
              final shown = clientCounted ? (_counts[view] ?? t) : t;
              if (mounted && shown != _total) setState(() => _total = shown);
              // For server-counted tabs the list's total is the freshest
              // truth — keep the badge in step without a full recount.
              if (!clientCounted && _counts[view] != t) {
                setState(() => _counts = {..._counts, view: t});
              }
            }
          : null,
      emptyMessage: 'No tickets',
      emptyHint: 'Try a different filter or search.',
      fetch: (page) async {
        final res = await repo.list(query.copyWith(page: page));
        // Kick off assignee resolution for rows the list API left blank, so
        // search-by-assignee and the Agent facet can match them.
        _resolveAssignees(res.items);
        return res;
      },
      itemBuilder: (context, t) => TicketRow(
        ticket: t,
        compact: compact,
        selectionMode: _selectionMode,
        selected: _selected.contains(t.id),
        onToggle: () => _toggle(t.id),
        onTap: () => context.push(Routes.ticket(t.id)),
      ),
    );
  }
}
