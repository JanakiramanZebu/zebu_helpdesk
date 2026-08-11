import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../data/tasks_repository.dart';
import '../../../models/meta.dart';
import '../../../models/task.dart';
import '../../../providers.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/list_controls.dart' show DateRange;
import '../../../widgets/paged_list_view.dart';
import '../../../widgets/slide_over_host.dart';
import '../../../widgets/web/bulk_action_bar.dart';
import '../../../widgets/web/list_search_input.dart';
import '../../../widgets/web/list_table_shell.dart';
import '../../../widgets/web/page_header.dart';
import '../../../widgets/web/segmented_tab_bar.dart';
import '../../../widgets/web/select_checkbox.dart';
import '../../../widgets/web/status_pill.dart';
import '../../../widgets/web_filter_button.dart';
import 'task_detail_panel.dart';
import '../../../res/zebu_status_colors.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

// Column layout for the tasks table. Header and every row share these so the
// vertical grid lines up pixel-for-pixel without a `Table`/`Row` per-cell
// wrapper. Task column carries the title (and optional blocked lock);
// Department is a short label and can afford the tightest flex.
/// Task ID column — fixed 90 px, matches the tickets table so both grids
/// share the same # column width. Split out of the "Task" column so the
/// number reads as its own sortable value.
/// Leading select-checkbox column, shared by header + rows + skeleton.
const double _kColSelectWidth = 44;
const double _kColNumberWidth = 90;
const int _kColTaskFlex = 6;
const int _kColAssigneeFlex = 2;
const int _kColDeptFlex = 2;
const double _kColPriorityWidth = 110;
const double _kColStatusWidth = 130;
// Wide enough to fit `29 Jun 2026` on one line at the current bodySm size.
const double _kColDueWidth = 120;

/// Fixed table row height — uniform, Asana-style rows. Replaces the previous
/// `IntrinsicHeight` sizing so every row is the same height and the layout
/// skips an extra measure pass.
const double _kRowHeight = 44;

/// Minimum table width — accounts for the fixed-width columns
/// (90 + 110 + 130 + 120 = 450), the 3 px leading accent-stripe rail, and
/// a readable minimum for each flex column. Below this the table
/// horizontally scrolls instead of squeezing columns.
const double _kTableMinWidth = 1204;

/// Web-only tasks list.
///
/// Same data sources as the mobile `TasksListScreen`
/// ([tasksRepositoryProvider]) — only the visual language differs:
/// [PageHeader] + [SegmentedTabBar] + a full-width table wrapped in a
/// hairline-bordered surface. Mirrors the tickets list treatment so both
/// tables read as one product.
class TasksListScreenWeb extends ConsumerStatefulWidget {
  const TasksListScreenWeb({super.key});

  @override
  ConsumerState<TasksListScreenWeb> createState() =>
      _TasksListScreenWebState();
}

/// Ordered saved views, each with the glyph its tab wears. Open and Closed
/// share the tickets pairing — the same ring with opposite centres.
const _views = <({String key, String label, IconData icon})>[
  (key: 'open', label: 'Open', icon: Icons.pending_outlined),
  (key: 'mine', label: 'Mine', icon: Icons.person_outline),
  (key: 'overdue', label: 'Overdue', icon: Icons.schedule_outlined),
  (key: 'collaborator', label: 'Collaborator', icon: Icons.people_outline),
  (key: 'all', label: 'All', icon: Icons.all_inbox_outlined),
  (key: 'closed', label: 'Closed', icon: Icons.check_circle_outline),
];

/// Ordered sort options mirrored from the mobile filter menu.
const _sortItems = <({String key, String label})>[
  (key: 'created', label: 'Most Recently Created'),
  (key: 'updated', label: 'Most Recently Updated'),
  (key: 'due', label: 'Due Date'),
  (key: 'number', label: 'Task Number'),
];

/// Facet keys we load meta for and expose in the Filter popover.
const _taskFacets = <({String key, String label, String metaKind})>[
  (key: 'dept', label: 'Department', metaKind: MetaKind.departments),
  (key: 'priority', label: 'Priority', metaKind: MetaKind.taskPriorities),
  (key: 'agent', label: 'Agent', metaKind: MetaKind.agents),
  (key: 'tag', label: 'Tag', metaKind: MetaKind.tags),
];

class _TasksListScreenWebState extends ConsumerState<TasksListScreenWeb> {
  String _view = 'open';
  String _search = '';
  Timer? _debounce;
  Map<String, int> _counts = const {};
  int? _openTaskId;
  bool _fullscreen = false;

  // Shared horizontal scroll controller for the table (header + rows).
  // Keeps them in sync when the table overflows below `_kTableMinWidth`.
  final ScrollController _tableHScroll = ScrollController();

  /// Extra Quick-Filter toggles driven by the Filter popover.
  final Set<String> _quickFlags = {};

  // Full filter format: date range, sort, and per-facet selection.
  DateRange _dateRange = DateRange.all;
  String _sort = 'created';
  final Map<String, String> _facetSelected = {
    for (final f in _taskFacets) f.key: 'all',
  };
  Map<String, List<MetaItem>> _facetOptions = const {};

  // --- Bulk selection ------------------------------------------------------
  /// Ids of tasks ticked via the row checkboxes. Cleared on view/tab switch
  /// since the visible set changes underneath it.
  final Set<int> _selectedIds = {};

  /// Currently visible (filtered + sorted) tasks, from [PagedListView.onItems]
  /// — backs the header select-all + its tri-state.
  List<Task> _visibleTasks = const [];

  /// Bumped after a bulk action so the [PagedListView] refetches and rows
  /// reflect the change (the tasks list has no panel-change counter otherwise).
  int _refreshSeq = 0;

  bool get _allChecked =>
      _visibleTasks.isNotEmpty &&
      _visibleTasks.every((t) => _selectedIds.contains(t.id));
  bool get _someChecked => _selectedIds.isNotEmpty && !_allChecked;

  void _onVisibleTasks(List<Task> items) {
    final next = items.map((t) => t.id).toSet();
    final cur = _visibleTasks.map((t) => t.id).toSet();
    if (next.length == cur.length && next.containsAll(cur)) return;
    setState(() => _visibleTasks = items);
  }

  void _toggleChecked(int id) => setState(() {
        if (!_selectedIds.remove(id)) _selectedIds.add(id);
      });

  void _toggleCheckAll() => setState(() {
        if (_allChecked) {
          for (final t in _visibleTasks) {
            _selectedIds.remove(t.id);
          }
        } else {
          for (final t in _visibleTasks) {
            _selectedIds.add(t.id);
          }
        }
      });

  void _clearSelection() => setState(_selectedIds.clear);

  void _toast(String msg, {ToastType type = ToastType.info}) =>
      AppToast.show(context, msg, type: type);

  /// Runs [op] against every selected task, tolerating per-item failures, then
  /// clears the selection and bumps the refresh sequence so rows re-fetch.
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
      _refreshSeq++;
    });
    final noun = ids.length == 1 ? 'task' : 'tasks';
    if (failed == 0) {
      _toast('$verb ${ids.length} $noun', type: ToastType.success);
    } else {
      _toast('$verb ${ids.length - failed}/${ids.length} — $failed failed',
          type: ToastType.error);
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

  Future<void> _bulkComplete() => _bulkRun(
        (id) async => ref.read(tasksRepositoryProvider).close(id),
        verb: 'Completed',
      );

  Future<void> _bulkReopen() => _bulkRun(
        (id) async => ref.read(tasksRepositoryProvider).reopen(id),
        verb: 'Reopened',
      );

  Future<void> _bulkAssign(BuildContext anchor) async {
    final agentId = await _pickMetaId(anchor, MetaKind.agents);
    if (agentId == null) return;
    await _bulkRun(
      (id) async =>
          ref.read(tasksRepositoryProvider).assign(id, staffId: agentId),
      verb: 'Assigned',
    );
  }

  Future<void> _bulkPriority(BuildContext anchor) async {
    final priorityId = await _pickMetaId(anchor, MetaKind.taskPriorities);
    if (priorityId == null) return;
    await _bulkRun(
      (id) async =>
          ref.read(tasksRepositoryProvider).edit(id, priorityId: priorityId),
      verb: 'Updated',
    );
  }

  Future<void> _bulkTransfer(BuildContext anchor) async {
    final deptId = await _pickMetaId(anchor, MetaKind.departments);
    if (deptId == null) return;
    await _bulkRun(
      (id) async => ref.read(tasksRepositoryProvider).transfer(id, deptId),
      verb: 'Transferred',
    );
  }

  void _openTask(int id) => setState(() => _openTaskId = id);
  // Closing the panel is a pure state change — no refetch on close.
  void _closeTask() => setState(() {
        _openTaskId = null;
        _fullscreen = false;
      });
  void _toggleFullscreen() => setState(() => _fullscreen = !_fullscreen);

  @override
  void initState() {
    super.initState();
    final requested = ref.read(tasksViewRequestProvider);
    if (requested != null) {
      _view = requested;
      Future.microtask(
        () => ref.read(tasksViewRequestProvider.notifier).set(null),
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
      _taskFacets.map((f) async {
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
    final repo = ref.read(tasksRepositoryProvider);
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
    Task t, {
    required String? meNameLower,
    required (DateTime, DateTime)? bounds,
    required String? needle,
    required Map<String, String> facetNeedles,
  }) {
    final viewOk = switch (_view) {
      'open' => t.isOpen,
      'closed' => !t.isOpen,
      'overdue' => t.overdue,
      'mine' =>
        meNameLower == null || meNameLower.isEmpty
            ? true
            : (t.assignee ?? '').toLowerCase().contains(meNameLower),
      _ => true,
    };
    if (!viewOk) return false;
    if (_quickFlags.contains('incomplete') && !t.isOpen) return false;
    if (_quickFlags.contains('completed') && t.isOpen) return false;
    if (_quickFlags.contains('overdue') && !t.overdue) return false;
    if (_quickFlags.contains('unassigned') &&
        (t.assignee ?? '').trim().isNotEmpty) {
      return false;
    }

    // Date range filter — matches against the task's created date.
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
        'priority' => (t.priority?.name ?? '').toLowerCase(),
        'agent' => (t.assignee ?? '').toLowerCase(),
        _ => '',
      };
      if (haystack.isNotEmpty && !haystack.contains(entry.value)) return false;
    }

    if (needle == null) return true;
    return _norm(t.number).contains(needle) ||
        _norm(t.title).contains(needle) ||
        _norm(t.assignee ?? '').contains(needle) ||
        _norm(t.departmentName ?? '').contains(needle);
  }

  /// Resolves the currently-selected facet dropdowns to a
  /// `{facetKey: lowercased option name}` map — computed once per filter pass
  /// instead of re-looked-up per task.
  Map<String, String> _activeFacetNeedles() {
    final out = <String, String>{};
    for (final f in _taskFacets) {
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
    WebQuickFilter chip(String key, String label) => WebQuickFilter(
          label: label,
          active: _quickFlags.contains(key),
          onToggle: () => setState(() {
            if (!_quickFlags.add(key)) _quickFlags.remove(key);
          }),
        );
    return [
      chip('incomplete', 'Incomplete tasks'),
      chip('completed', 'Completed tasks'),
      chip('overdue', 'Overdue'),
      chip('unassigned', 'Unassigned'),
    ];
  }

  /// Facet-dropdown controls for the popover.
  List<WebFacetControl> _facetControls() {
    return [
      for (final f in _taskFacets)
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
      _quickFlags.clear();
      _dateRange = DateRange.all;
      for (final f in _taskFacets) {
        _facetSelected[f.key] = 'all';
      }
    });
  }

  // Compiled once — building a fresh RegExp per call was the single heaviest
  // per-item cost, since `_matches` normalizes ~4 fields for every task.
  static final RegExp _normPattern = RegExp(r'[#,\s₹]');
  static String _norm(String s) => s.toLowerCase().replaceAll(_normPattern, '');

  int _compare(Task a, Task b) {
    return switch (_sort) {
      'updated' => (b.updated ?? b.created ?? DateTime(0))
          .compareTo(a.updated ?? a.created ?? DateTime(0)),
      'due' => _dueCompare(a.duedate, b.duedate),
      'number' => b.number.compareTo(a.number),
      _ => (b.created ?? DateTime(0)).compareTo(a.created ?? DateTime(0)),
    };
  }

  /// Nulls-last so tasks without a due date drop to the bottom of the sort
  /// instead of clumping at the top.
  int _dueCompare(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(tasksViewRequestProvider, (_, next) {
      if (next == null) return;
      if (next != _view) setState(() => _view = next);
      ref.read(tasksViewRequestProvider.notifier).set(null);
    });

    final t = ZebuTheme.of(context);
    final meName = ref.watch(meProvider).asData?.value.name;
    final repo = ref.watch(tasksRepositoryProvider);
    final query = TaskQuery(view: _view, sort: _sort, order: 'desc');

    // Precompute everything the per-item filter needs exactly once per build,
    // rather than per task. `filterKey` captures every input `_matches` /
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
      Object.hashAllUnordered(_quickFlags),
      Object.hashAllUnordered([
        for (final e in facetNeedles.entries) '${e.key}=${e.value}',
      ]),
    );

    // Build the tab items from the fixed view list, folding in live counts
    // as they arrive. If a count hasn't loaded yet the pill is omitted.
    // Dot colors mirror the mobile tasks `_viewColor` mapping.
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
      openId: _openTaskId,
      onClose: _closeTask,
      fullscreen: _fullscreen,
      panelBuilder: (context, id, close) => TaskDetailPanel(
        taskId: id,
        onClose: close,
        isFullscreen: _fullscreen,
        onToggleFullscreen: _toggleFullscreen,
      ),
      child: ColoredBox(
        color: t.bgPrimary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Tasks',
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
                        // state.
                        onClear: _clearAllFilters,
                      ),
                      const SizedBox(width: ZebuSpacing.s3),
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
                    icon: Icons.check_circle_outline,
                    label: 'Complete',
                    onTap: (_) => _bulkComplete(),
                  ),
                  WebBulkButton(
                    icon: Icons.replay,
                    label: 'Reopen',
                    onTap: (_) => _bulkReopen(),
                  ),
                  WebBulkButton(
                    icon: Icons.assignment_ind_outlined,
                    label: 'Assign',
                    hasMenu: true,
                    onTap: _bulkAssign,
                  ),
                  WebBulkButton(
                    icon: Icons.flag_outlined,
                    label: 'Priority',
                    hasMenu: true,
                    onTap: _bulkPriority,
                  ),
                  WebBulkButton(
                    icon: Icons.business_outlined,
                    label: 'Transfer',
                    hasMenu: true,
                    onTap: _bulkTransfer,
                  ),
                ],
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
                            _TableHeader(
                              scrollGutter: horizontalScroll,
                              allChecked: _allChecked,
                              someChecked: _someChecked,
                              onToggleAll: _toggleCheckAll,
                            ),
                            Expanded(
                              child: ColoredBox(
                                color: t.bgElevated,
                                child: PagedListView<Task>(
                                  padding: EdgeInsets.zero,
                                  refreshKey: '$_view|$_search|$_refreshSeq',
                                  filterKey: filterKey,
                                  itemFilter: (task) => _matches(
                                    task,
                                    meNameLower: meNameLower,
                                    bounds: dateBounds,
                                    needle: searchNeedle,
                                    facetNeedles: facetNeedles,
                                  ),
                                  itemSort: _compare,
                                  emptyMessage: 'No tasks',
                                  emptyHint:
                                      'Try a different filter or search.',
                                  fetch: (page) =>
                                      repo.list(query.copyWith(page: page)),
                                  loadingBuilder: (_) =>
                                      const _TaskTableSkeleton(),
                                  onItems: _onVisibleTasks,
                                  itemBuilder: (context, task) => _TaskRow(
                                    task: task,
                                    selected: _openTaskId == task.id,
                                    checked: _selectedIds.contains(task.id),
                                    onToggleChecked: () =>
                                        _toggleChecked(task.id),
                                    onTap: () => _openTask(task.id),
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
// Table header — column labels rendered on a `bgElevated` strip so the
// header reads separated from body rows without shadows or extra borders.
// Shares the exact column widths every row uses via the `_kCol*` constants
// so the grid aligns pixel-for-pixel.
// ---------------------------------------------------------------------------

class _TableHeader extends StatelessWidget {
  const _TableHeader({
    this.scrollGutter = false,
    required this.allChecked,
    required this.someChecked,
    required this.onToggleAll,
  });

  /// When true, reserves 10 px of trailing space at the right edge of
  /// the header to line up with the horizontal scrollbar sitting under
  /// the body. Off when the table isn't horizontally scrolling — the
  /// gutter would otherwise create a dead strip past "Due".
  final bool scrollGutter;

  /// Header select-all tri-state (`allChecked`/`someChecked`) + its toggle.
  final bool allChecked;
  final bool someChecked;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(
          top: BorderSide(color: t.borderSubtle, width: 1),
          bottom: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Leading 3 px offset matches the row's accent-stripe rail so
            // column starts line up with row content pixel-for-pixel.
            const SizedBox(width: 3),
            SizedBox(
              width: _kColSelectWidth,
              child: Center(
                child: SelectCheckbox(
                  value: allChecked ? true : (someChecked ? null : false),
                  onChanged: (_) => onToggleAll(),
                  tooltip: allChecked ? 'Deselect all' : 'Select all',
                ),
              ),
            ),
            const _HeaderCell(width: _kColNumberWidth, label: '#'),
            const _HeaderCell(flex: _kColTaskFlex, label: 'Task'),
            const _HeaderCell(flex: _kColAssigneeFlex, label: 'Assignee'),
            const _HeaderCell(flex: _kColDeptFlex, label: 'Department'),
            const _HeaderCell(width: _kColPriorityWidth, label: 'Priority'),
            const _HeaderCell(width: _kColStatusWidth, label: 'Status'),
            const _HeaderCell(
              width: _kColDueWidth,
              label: 'Due',
              alignRight: true,
            ),
            if (scrollGutter) const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

/// Column header cell — hairline right border (except on the last cell),
/// `s3` horizontal padding, `tableHeader` typography. Mirrors the tickets
/// list treatment so both tables read as one grid.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    this.flex,
    this.width,
    this.alignRight = false,
  });
  final String label;
  final int? flex;
  final double? width;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: ZebuSpacing.s3,
      ),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        label,
        style: ZebuTextStyles.tableHeader(context),
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
      ),
    );
    if (flex != null) return Expanded(flex: flex!, child: content);
    if (width != null) return SizedBox(width: width!, child: content);
    return content;
  }
}

/// Body cell — right-border creates the vertical grid line; 8 px vertical
/// padding gives a tighter table rhythm than the header's `s3`.
class _BodyCell extends StatelessWidget {
  const _BodyCell({
    required this.child,
    this.flex,
    this.width,
    this.alignRight = false,
  });
  final Widget child;
  final int? flex;
  final double? width;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: 8,
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
// Task row — one single-line row per task, columns aligned with
// `_TableHeader`. Hover tint and selected-accent-tint match the tickets
// treatment (subtle bg fill, no border shift).
// ---------------------------------------------------------------------------

class _TaskRow extends StatefulWidget {
  const _TaskRow({
    required this.task,
    required this.onTap,
    required this.checked,
    required this.onToggleChecked,
    this.selected = false,
  });
  final Task task;
  final VoidCallback onTap;
  /// Row selection (bulk-action checkbox) — distinct from [selected], which
  /// flags the row whose detail panel is open.
  final bool checked;
  final VoidCallback onToggleChecked;
  final bool selected;

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _hover = false;

  // Color maps mirror the tickets list so both tables read as one product:
  // Normal priority = info-blue (not dead grey), High = warning amber,
  // Emergency = red, Low = success green.
  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final task = widget.task;
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
          child: SizedBox(
            height: _kRowHeight,
            child: Row(
              children: [
                      SizedBox(
                        width: _kColSelectWidth,
                        child: Center(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onToggleChecked,
                            child: SelectCheckbox(
                              value: widget.checked,
                              onChanged: (_) => widget.onToggleChecked(),
                            ),
                          ),
                        ),
                      ),
                      _BodyCell(
                        width: _kColNumberWidth,
                        child: Text(
                          '#${task.number}',
                          style: ZebuTextStyles.small(context)
                              .copyWith(
                                fontWeight: FontWeight.w600,
                                color: t.accent,
                              )
                              .withTabularNums(),
                        ),
                      ),
                      _BodyCell(
                        flex: _kColTaskFlex,
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                task.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZebuTextStyles.body(context)
                                    .copyWith(fontWeight: FontWeight.w500),
                              ),
                            ),
                            if (task.blocked) ...[
                              const SizedBox(width: ZebuSpacing.s2),
                              Icon(
                                Icons.lock_outline,
                                size: 14,
                                color: t.danger,
                              ),
                            ],
                          ],
                        ),
                      ),
                      _BodyCell(
                        flex: _kColAssigneeFlex,
                        child: _TextCell(
                          text: task.assignee ?? '',
                          emptyLabel: 'Unassigned',
                        ),
                      ),
                      _BodyCell(
                        flex: _kColDeptFlex,
                        child: _TextCell(text: task.departmentName ?? ''),
                      ),
                      _BodyCell(
                        width: _kColPriorityWidth,
                        child: (task.priority?.name ?? '').isEmpty
                            ? Text('—', style: ZebuTextStyles.small(context))
                            : StatusPill(
                                label: _titleCase(task.priority!.name),
                                color: zebuPriorityColor(widget.task.priority?.name, t),
                                icon: Icons.flag_rounded,
                              ),
                      ),
                      _BodyCell(
                        width: _kColStatusWidth,
                        child: StatusPill(
                          label: task.overdue
                              ? 'Overdue'
                              : _titleCase(task.statusName),
                          color: zebuStatusColor(
                            widget.task.statusName,
                            t,
                            overdue: widget.task.overdue,
                          ),
                        ),
                      ),
                      _BodyCell(
                        width: _kColDueWidth,
                        alignRight: true,
                        child: Text(
                          Fmt.date(task.duedate ?? task.created),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          textAlign: TextAlign.right,
                          style: ZebuTextStyles.small(context)
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
  const _TextCell({required this.text, this.emptyLabel});

  final String text;

  /// Placeholder shown when [text] is empty (e.g. "Unassigned" for the
  /// assignee cell). If omitted, an em-dash is used.
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final empty = text.trim().isEmpty;
    final display = empty ? (emptyLabel ?? '—') : text;
    return Text(
      display,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ZebuTextStyles.small(context).copyWith(
        color: empty ? t.textSecondary : t.textPrimary,
        fontWeight: empty ? FontWeight.w400 : FontWeight.w500,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton loader — rendered by [PagedListView.loadingBuilder] on the first
// paint before task rows arrive. Mirrors the real row's column grid (same
// `_kCol*` widths) so the transition to live data is a swap-in-place rather
// than a layout jump. A single shared pulse controller drives the greyscale
// opacity across every placeholder block for a synchronised "one heartbeat"
// feel.
// ---------------------------------------------------------------------------

class _TaskTableSkeleton extends StatefulWidget {
  const _TaskTableSkeleton();

  @override
  State<_TaskTableSkeleton> createState() => _TaskTableSkeletonState();
}

class _TaskTableSkeletonState extends State<_TaskTableSkeleton>
    with SingleTickerProviderStateMixin {
  // Approximate row height — used only to decide how many skeleton rows to
  // render so the placeholder fills the viewport instead of stopping halfway
  // down.
  static const double _kApproxRowHeight = 32;

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
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
    final t = ZebuTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
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
    final t = ZebuTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Leading spacer that matches the real row's accent-stripe
            // width — keeps content columns pixel-aligned with the live
            // table so nothing shifts when data arrives.
            const SizedBox(width: 3),
            const SizedBox(width: _kColSelectWidth),
            _BodyCell(
              width: _kColNumberWidth,
              child: _block(56),
            ),
            _BodyCell(
              flex: _kColTaskFlex,
              child: _block(260),
            ),
            _BodyCell(
              flex: _kColAssigneeFlex,
              child: _block(110),
            ),
            _BodyCell(
              flex: _kColDeptFlex,
              child: _block(90),
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
              width: _kColDueWidth,
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
