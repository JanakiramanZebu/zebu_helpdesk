import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/export/table_export.dart';
import '../../core/format.dart';
import '../../core/list_layout.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../data/tasks_repository.dart';
import '../../models/meta.dart';
import '../../models/task.dart';
import '../../providers.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/filter_chip_tabs.dart';
import '../../widgets/filter_sheet.dart';
import '../../widgets/glass.dart';
import '../../widgets/list_controls.dart';
import '../../widgets/paged_list_view.dart';
import '../../widgets/selection_controls.dart';
import '../../widgets/skeleton.dart';
import 'widgets/task_row.dart';

/// App filter pills (the `view` param on GET /tasks). Order and labels mirror
/// the web Tasks nav (scp/tasks.php): Open · All · Overdue · Completed ·
/// Created by me · Collaborator · My Tasks. ("New Task" is the bottom-nav "+",
/// not a filter tab.) The `closed` key is kept (the backend accepts it and the
/// dashboard "Completed" tile deep-links to it) while the chip reads "Completed".
const _views = <({String key, String label})>[
  (key: 'open', label: 'Open'),
  (key: 'all', label: 'All'),
  (key: 'overdue', label: 'Overdue'),
  (key: 'closed', label: 'Completed'),
  (key: 'created', label: 'Created by me'),
  (key: 'collaborator', label: 'Collaborator'),
  (key: 'mine', label: 'My Tasks'),
];

/// Sort options (the `sort` param on GET /tasks), mirroring the web menu.
const _sortItems = <({String key, String label})>[
  (key: 'updated', label: 'Most Recently Updated'),
  (key: 'created', label: 'Most Recently Created'),
  (key: 'due', label: 'Due Date'),
  (key: 'number', label: 'Task Number'),
  (key: 'thread', label: 'Longest Thread'),
];

/// Advanced filter facets opened from the search bar's filter button.
const _filterFacets = <FilterFacet>[
  FilterFacet(key: 'dept', label: 'Department', metaKind: MetaKind.departments),
  FilterFacet(
    key: 'priority',
    label: 'Priority',
    metaKind: MetaKind.taskPriorities,
  ),
  FilterFacet(key: 'agent', label: 'Agent', metaKind: MetaKind.agents),
  FilterFacet(key: 'tag', label: 'Tag', metaKind: MetaKind.tags),
];

class TasksListScreen extends ConsumerStatefulWidget {
  const TasksListScreen({super.key});

  @override
  ConsumerState<TasksListScreen> createState() => _TasksListScreenState();
}

class _TasksListScreenState extends ConsumerState<TasksListScreen> {
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

  // Per-tab count badges.
  Map<String, int> _counts = const {};

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Honor a filter requested before this screen was first built (e.g. tapping
    // a dashboard task stat tile that switched to the Tasks tab).
    final requested = ref.read(tasksViewRequestProvider);
    if (requested != null) {
      _view = requested;
      Future.microtask(
        () => ref.read(tasksViewRequestProvider.notifier).set(null),
      );
    }
    _pageController = PageController(initialPage: _indexOf(_view));
    _loadCounts();
    _loadFacets();
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
    setState(() => _view = view);
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
    if (next != _view) setState(() => _view = next);
  }

  /// Jump the pager to [view] without animation (cross-tab filter requests).
  void _jumpToView(String view) {
    setState(() => _view = view);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(_indexOf(view));
    }
  }

  /// Fetch the count for every tab in parallel (cheap total-only queries).
  ///
  /// Uses the SAME query the list will run for each view ([_queryFor], limited
  /// to one row) rather than a bare `view` count, so the badge can't disagree
  /// with the list — notably the `status=open` scope on "My Tasks" and
  /// "Collaborator". The server's pagination total is what we read.
  Future<void> _loadCounts() async {
    final repo = ref.read(tasksRepositoryProvider);
    final entries = await Future.wait(
      _views.map((v) async {
        try {
          // Count My Tasks open-only client-side, matching the filtered list.
          if (v.key == 'mine') {
            final mine = await _gatherAll(_queryFor('mine'));
            return MapEntry('mine', mine.where((t) => t.isOpen).length);
          }
          final res = await repo.list(_queryFor(v.key).copyWith(limit: 1));
          return MapEntry(v.key, res.total);
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
      // Keep the app-bar total in step with the corrected My Tasks count.
      if (_view == 'mine' && _counts['mine'] != null) _total = _counts['mine'];
    });
  }

  /// Semantic dot color for each view chip, mirroring the dashboard's Tasks
  /// palette.
  static Color _viewColor(String key) => switch (key) {
    'open' => AppTheme.open,
    'mine' => Glass.indigo, // My Tasks (assigned to me)
    'overdue' => AppTheme.overdue,
    'collaborator' => AppTheme.warning,
    'created' => Glass.indigo, // Created by me
    'closed' => AppTheme.closed, // Completed
    _ => Glass.accent, // 'all'
  };

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _toast(String msg) => AppSnack.info(context, msg);

  /// Debounced live search — narrows the list as the user types.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final next = value.trim();
      if (next != _search && mounted) setState(() => _search = next);
    });
  }

  void _applySearch(String value) {
    _debounce?.cancel();
    final next = value.trim();
    if (next != _search) setState(() => _search = next);
  }


  String get _order => _sort == 'due' ? 'asc' : 'desc';

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
  }

  // Search and the date range are also enforced client-side (see [_matches]);
  // the query carries the tab's view, sort, create-date window and facet
  // filters for the server.
  TaskQuery _queryFor(String view) {
    final b = _dateBounds;
    final tag = _filters['tag'];
    return TaskQuery(
      view: view,
      sort: _sort,
      order: _order,
      createdFrom: b == null ? null : Fmt.apiDate(b.$1),
      createdTo: b == null ? null : Fmt.apiDate(b.$2),
      deptId: _filters['dept']?.id,
      priorityId: _filters['priority']?.id,
      assigneeId: _filters['agent']?.id,
      tagId: tag == null ? null : [tag.id],
      // The "My Tasks" (mine) and "Collaborator" views scope by assignee /
      // collaborator server-side but otherwise include completed tasks. The web
      // nav counts both as OPEN-only (Task::getStaffStats: `assigned` and
      // `collab` require the ISOPEN flag), so AND in status=open to match — the
      // backend applies it alongside the view.
      extra: (view == 'mine' || view == 'collaborator')
          ? const {'status': 'open'}
          : const {},
    );
  }

  /// Client-side comparator matching the active sort (null for 'thread', which
  /// the list model can't order — that one relies on the server).
  int _compare(Task a, Task b) {
    int desc(DateTime? x, DateTime? y) =>
        (y ?? DateTime(0)).compareTo(x ?? DateTime(0));
    switch (_sort) {
      case 'updated':
        return desc(a.updated, b.updated);
      case 'due':
        if (a.duedate == null && b.duedate == null) return 0;
        if (a.duedate == null) return 1; // nulls last
        if (b.duedate == null) return -1;
        return a.duedate!.compareTo(b.duedate!); // soonest first
      case 'number':
        return (int.tryParse(b.number) ?? 0).compareTo(
          int.tryParse(a.number) ?? 0,
        );
      default: // 'created'
        return desc(a.created, b.created);
    }
  }

  // --- Selection ------------------------------------------------------------

  void _onItems(List<Task> items) {
    final ids = items.map((t) => t.id).toList();
    if (!listEquals(ids, _visibleIds)) setState(() => _visibleIds = ids);
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
    return showAppSheet<int>(
      context: context,
      builder: (_) => AppSheet(
        title: title,
        scrollable: false,
        padding: EdgeInsets.zero,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in items)
              ListTile(
                title: AppText.subText(context, m.name),
                onTap: () => Navigator.pop(context, m.id),
              ),
          ],
        ),
      ),
    );
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
    final noun = ok == 1 ? 'task' : 'tasks';
    _toast(fail == 0 ? '$verb $ok $noun' : '$verb $ok $noun · $fail failed');
  }

  Future<void> _onBulkMenu(String action) async {
    final repo = ref.read(tasksRepositoryProvider);
    switch (action) {
      case 'reopen':
        await _runBulk('Reopened', repo.reopen);
      case 'assign':
        final id = await _pickMeta(MetaKind.agents, 'Assign to agent');
        if (id != null) {
          await _runBulk('Assigned', (t) => repo.assign(t, staffId: id));
        }
      case 'priority':
        final id = await _pickMeta(MetaKind.taskPriorities, 'Set priority');
        if (id != null) {
          await _runBulk('Updated', (t) => repo.edit(t, priorityId: id));
        }
      case 'transfer':
        final id = await _pickMeta(MetaKind.departments, 'Transfer to department');
        if (id != null) await _runBulk('Transferred', (t) => repo.transfer(t, id));
    }
  }

  // --- Export ---------------------------------------------------------------

  Future<List<Task>> _gatherAll(TaskQuery base) async {
    final repo = ref.read(tasksRepositoryProvider);
    final all = <Task>[];
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
      final tasks = (await _gatherAll(_queryFor(_view)))
          .where((t) => _matches(t, _view))
          .toList();
      if (tasks.isEmpty) {
        _toast('No tasks to export');
        return;
      }
      await exportTable(
        format: format,
        baseName: 'tasks-$_view',
        title: 'Tasks ($view)',
        columns: const [
          '#',
          'Title',
          'Status',
          'Priority',
          'Department',
          'Assignee',
          'Progress',
          'Created',
          'Due',
        ],
        rows: [
          for (final t in tasks)
            [
              t.number,
              t.title,
              t.statusName,
              t.priority?.name ?? '',
              t.departmentName ?? '',
              t.assignee ?? '',
              '${t.progress}%',
              Fmt.date(t.created),
              Fmt.date(t.duedate),
            ],
        ],
      );
      if (mounted) {
        _toast('Exported ${tasks.length} tasks as ${format.label}');
      }
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Saved file but could not open it automatically');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Narrows the server's rows by the fields we can trust client-side (live
  /// search text, create-date window, facet selections) plus instant text
  /// matching as the user types.
  ///
  /// View membership is deliberately NOT re-derived here. The server already
  /// filters by `view` (proven by the per-tab counts), and the list summary
  /// doesn't reliably carry the flags needed to reproduce that filter —
  /// overdue state, open vs closed, assignment. Re-deriving it silently dropped
  /// rows the server returned, which is what emptied the Overdue tab.
  bool _matches(Task t, String view) {
    // "My Tasks" shows only OPEN tasks assigned to me. The server scopes
    // view=mine to status=open, but guard here too so a closed row can never
    // leak into this tab (mirrors the Tickets screen).
    if (view == 'mine' && !t.isOpen) return false;

    final b = _dateBounds;
    if (b != null) {
      final c = t.created;
      if (c == null || c.isBefore(b.$1) || c.isAfter(b.$2)) return false;
    }

    // Facet filters (best-effort, by name; tags have no list-row data so they
    // rely on the server query).
    if (!_facetOk(_filters['dept'], t.departmentName) ||
        !_facetOk(_filters['priority'], t.priority?.name) ||
        !_facetOk(_filters['agent'], t.assignee)) {
      return false;
    }

    final q = _search.trim();
    if (q.isEmpty) return true;
    // Normalize away `#`, commas, spaces and `₹` so "pa", a number, or a raw
    // amount like "100852" all match (e.g. against "₹1,00,852.24").
    final needle = _norm(q);
    return _norm(t.number).contains(needle) ||
        _norm(t.title).contains(needle) ||
        _norm(t.assignee ?? '').contains(needle) ||
        _norm(t.departmentName ?? '').contains(needle);
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[#,\s₹]'), '');

  /// True when no facet is selected, or the row's [value] matches the selected
  /// item's name (case-insensitive).
  static bool _facetOk(MetaItem? selected, String? value) {
    if (selected == null) return true;
    return (value ?? '').trim().toLowerCase() ==
        selected.name.trim().toLowerCase();
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
      tooltip: 'Mark complete',
      icon: const Icon(Icons.task_alt),
      onPressed: () => _runBulk(
        'Completed',
        (t) => ref.read(tasksRepositoryProvider).close(t),
      ),
    ),
    onMenuSelected: _onBulkMenu,
    menuItems: [
      selectionMenuItem(context, value: 'reopen', label: 'Reopen'),
      selectionMenuItem(context, value: 'assign', label: 'Assign to agent…'),
      selectionMenuItem(context, value: 'priority', label: 'Set priority…'),
      selectionMenuItem(
        context,
        value: 'transfer',
        label: 'Transfer department…',
      ),
    ],
  );

  PreferredSizeWidget _normalAppBar(bool compact) {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.titleText(context, 'Tasks', fw: 1),
          if (_total != null) AppText.paraText(context, '$_total total'),
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
                hintText: 'Search tasks',
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
    ref.listen<String?>(tasksViewRequestProvider, (_, next) {
      if (next == null) return;
      if (next != _view) _jumpToView(next);
      ref.read(tasksViewRequestProvider.notifier).set(null);
    });

    final layout = ref.watch(listLayoutProvider);
    final compact = layout == ListLayout.compact;

    return Scaffold(
      appBar: _selectionMode ? _selectionAppBar() : _normalAppBar(compact),
      // Creating a task now lives on the bottom nav's center "+" button.
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
    final repo = ref.watch(tasksRepositoryProvider);
    // Refetch this list whenever a task is mutated anywhere (e.g. edited on the
    // detail screen) — folded into refreshKey below.
    final changed = ref.watch(tasksChangedProvider);
    final query = _queryFor(view);
    return PagedListView<Task>(
      fabClearance: !_selectionMode,
      skeleton: ListSkeleton(compact: compact),
      separated: compact,
      refreshKey: '$view|${_dateRange.name}|$_sort|$_filterSig|$_refresh|$changed',
      itemFilter: (t) => _matches(t, view),
      itemSort: _sort == 'thread' ? null : _compare,
      // Only the visible page feeds selection state and the app-bar total.
      onItems: active ? _onItems : null,
      onTotalChanged: active
          ? (t) {
              // Mirror the client-side open-only count for My Tasks.
              final shown = view == 'mine' ? (_counts['mine'] ?? t) : t;
              if (mounted && shown != _total) setState(() => _total = shown);
            }
          : null,
      emptyMessage: 'No tasks',
      emptyHint: 'Try a different filter or search.',
      fetch: (page) => repo.list(query.copyWith(page: page)),
      itemBuilder: (context, t) => TaskRow(
        task: t,
        compact: compact,
        selectionMode: _selectionMode,
        selected: _selected.contains(t.id),
        onToggle: () => _toggle(t.id),
        // Pass the row task so the detail can show the due date its own
        // endpoint omits (list summary carries it).
        onTap: () => context.push(Routes.task(t.id), extra: t),
      ),
    );
  }
}
