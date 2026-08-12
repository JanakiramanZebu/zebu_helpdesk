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
import '../../../widgets/web/dots_loader.dart';
import '../../../widgets/web/list_search_input.dart';
import '../../../widgets/web/list_table_shell.dart';
import '../../../widgets/web/page_header.dart';
import '../../../widgets/web/segmented_tab_bar.dart';
import '../../../widgets/web/status_badge.dart';
import '../../../widgets/web/zebu_data_grid.dart';
import '../../../widgets/web_filter_button.dart';
import 'task_detail_panel.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

// Column layout for the tasks table. Header and every row share these so the
// vertical grid lines up pixel-for-pixel without a `Table`/`Row` per-cell
// wrapper. Task column carries the title (and optional blocked lock);
// Department is a short label and can afford the tightest flex.
/// Task ID column — matches the tickets table so both grids share the same
/// leading width. Split out of the "Task" column so the number reads as its
/// own sortable value.
const double _kColNumberWidth = 100;
const int _kColTaskFlex = 6;
const int _kColAssigneeFlex = 2;
const int _kColDeptFlex = 2;
const double _kColPriorityWidth = 110;
const double _kColStatusWidth = 130;
// Wide enough to fit `29 Jun 2026` on one line at the current bodySm size.
const double _kColDueWidth = 120;

/// Last activity. Same width as Due; both hold `29 Jun 2026` on one line.
const double _kColUpdatedWidth = 120;

/// Fixed table row height — uniform, Asana-style rows. Replaces the previous
/// `IntrinsicHeight` sizing so every row is the same height and the layout
/// skips an extra measure pass.
const double _kRowHeight = 44;

/// Minimum table width — accounts for the fixed-width columns
/// (90 + 110 + 130 + 120 = 450), the 3 px leading accent-stripe rail, and
/// a readable minimum for each flex column. Below this the table
/// horizontally scrolls instead of squeezing columns.
const double _kTableMinWidth = 1364;

/// Web-only tasks list.
///
/// Same data sources as the mobile `TasksListScreen`
/// ([tasksRepositoryProvider]) — only the visual language differs:
/// [PageHeader] + [SegmentedTabBar] + a full-width table wrapped in a
/// hairline-bordered surface. Mirrors the tickets list treatment so both
/// tables read as one product.
class TasksListScreenWeb extends ConsumerStatefulWidget {
  const TasksListScreenWeb({super.key, this.openTaskId});

  /// Task to open the detail panel on at first paint.
  ///
  /// Serves the `/tasks/:id` deep link. That route used to render a separate
  /// full-page screen which nothing in the app ever navigated to — the list
  /// has always opened this panel instead — so the URL now lands on the list
  /// with the panel already up, and there is one task UI rather than two.
  final int? openTaskId;

  @override
  ConsumerState<TasksListScreenWeb> createState() => _TasksListScreenWebState();
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
/// Facets that get their own labelled dropdown in the filter popover.
///
/// Priority is deliberately absent: it has only four values, so the quick
/// checkboxes at the top of the panel cover it in one click with every option
/// visible. Keeping both meant a task's priority could be set in two places
/// and have them disagree.
const _taskFacets = <({String key, String label, String metaKind})>[
  (key: 'dept', label: 'Department', metaKind: MetaKind.departments),
  (key: 'agent', label: 'Agent', metaKind: MetaKind.agents),
  (key: 'tag', label: 'Tag', metaKind: MetaKind.tags),
];

class _TasksListScreenWebState extends ConsumerState<TasksListScreenWeb> {
  String _view = 'open';
  String _search = '';
  Timer? _debounce;
  Map<String, int> _counts = const {};
  int? _openTaskId;

  /// The row's own summary for the open task, handed to the panel so its
  /// header can paint on the first frame instead of saying "Loading…".
  Task? _openSummary;
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

  void _openTask(Task task) => setState(() {
    _openTaskId = task.id;
    _openSummary = task;
  });
  // Closing the panel is a pure state change — no refetch on close.
  void _closeTask() => setState(() {
    _openTaskId = null;
    _openSummary = null;
    _fullscreen = false;
  });
  void _toggleFullscreen() => setState(() => _fullscreen = !_fullscreen);

  @override
  void initState() {
    super.initState();
    _openTaskId = widget.openTaskId;
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
      'updated' => (b.updated ?? b.created ?? DateTime(0)).compareTo(
        a.updated ?? a.created ?? DateTime(0),
      ),
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

  /// The grid's single column definition — the header and every row are both
  /// rendered from this list, so the two can no longer drift apart the way
  /// the old hand-written `_TableHeader` / `_TaskRow` pair could.
  List<ZebuGridColumn<Task>> _columns(BuildContext context) {
    final t = ZebuTheme.of(context);
    return [
      ZebuGridColumn(
        width: _kColNumberWidth,
        label: 'Task ID',
        cell: (task) => Text(
          '#${task.number}',
          style: ZebuTextStyles.tableCell(
            context,
            color: t.accent,
            fontWeight: ZebuFonts.semiBold,
          ).withTabularNums(),
        ),
      ),
      ZebuGridColumn(
        flex: _kColTaskFlex,
        label: 'Task summary',
        cell: (task) => Row(
          children: [
            Flexible(
              child: Text(
                task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZebuTextStyles.tableCell(context),
              ),
            ),
            // Blocked tasks can't be actioned until their parent clears, so
            // the padlock has to survive the title being ellipsised.
            if (task.blocked) ...[
              const SizedBox(width: ZebuSpacing.s2),
              Icon(Icons.lock_outline, size: 14, color: t.danger),
            ],
          ],
        ),
      ),
      ZebuGridColumn(
        flex: _kColDeptFlex,
        label: 'Department',
        cell: (task) => ZebuGridTextCell(text: task.departmentName ?? ''),
      ),
      ZebuGridColumn(
        width: _kColPriorityWidth,
        label: 'Priority',
        cell: (task) => (task.priority?.name ?? '').isEmpty
            ? Text('\u2014', style: ZebuTextStyles.small(context))
            : PriorityBadge(
                label: _titleCase(task.priority!.name),
                priority: task.priority?.name,
              ),
      ),
      ZebuGridColumn(
        width: _kColStatusWidth,
        label: 'Status',
        cell: (task) => StatusBadge(
          label: task.overdue ? 'Overdue' : _titleCase(task.statusName),
          status: task.statusName,
          overdue: task.overdue,
        ),
      ),
      ZebuGridColumn(
        flex: _kColAssigneeFlex,
        label: 'Assigned to',
        cell: (task) => ZebuGridTextCell(
          text: task.assignee ?? '',
          emptyLabel: 'Unassigned',
        ),
      ),
      ZebuGridColumn(
        width: _kColDueWidth,
        label: 'Due',
        alignRight: true,
        cell: (task) => Text(
          Fmt.date(task.duedate ?? task.created),
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
        // Relative, unlike Due's absolute date. The two answer different
        // questions — Due is a commitment you cite, Last updated is "has this
        // gone quiet", and "3 days ago" answers that without arithmetic.
        cell: (task) => Text(
          task.updated == null ? '\u2014' : Fmt.ago(task.updated),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.right,
          style: task.updated == null
              ? ZebuTextStyles.small(context)
              : ZebuTextStyles.tableCell(context).withTabularNums(),
        ),
      ),
    ];
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
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
        initialTask: _openSummary?.id == id ? _openSummary : null,
        // Subtask / dependency rows swap the panel in place rather than
        // routing, so comparing two related tasks costs no animation.
        onOpenTask: (next) => setState(() {
          _openTaskId = next;
          _openSummary = null;
        }),
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
                        // state.
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
            // Bulk actions float over the table (see the Stack below), so nothing
            // is inserted here — ticking a box must not move the rows.
            Expanded(
              child: Stack(
                children: [
                  ListTableShell(
                    child: ZebuDataGrid<Task>(
                      columns: _columns(context),
                      minWidth: _kTableMinWidth,
                      rowHeight: _kRowHeight,
                      selection: ZebuGridSelection(
                        allChecked: _allChecked,
                        someChecked: _someChecked,
                        onToggleAll: _toggleCheckAll,
                      ),
                      body: (context, row) => PagedListView<Task>(
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
                        emptyHint: 'Try a different filter or search.',
                        fetch: (page) => repo.list(query.copyWith(page: page)),
                        loadingBuilder: (_) => const DotsLoader(),
                        onItems: _onVisibleTasks,
                        itemBuilder: (context, task) => row(
                          task,
                          selected: _openTaskId == task.id,
                          checked: _selectedIds.contains(task.id),
                          onToggleChecked: () => _toggleChecked(task.id),
                          onTap: () => _openTask(task),
                        ),
                      ),
                    ),
                  ),
                  if (_selectedIds.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 32,
                      child: WebBulkBar(
                        count: _selectedIds.length,
                        onClear: _clearSelection,
                        actions: [
                          WebBulkAction(
                            icon: Icons.check_circle_outline,
                            label: 'Complete',
                            primary: true,
                            onTap: (_) => _bulkComplete(),
                          ),
                          WebBulkAction(
                            icon: Icons.replay,
                            label: 'Reopen',
                            primary: true,
                            onTap: (_) => _bulkReopen(),
                          ),
                          WebBulkAction(
                            icon: Icons.assignment_ind_outlined,
                            label: 'Assign',
                            hasMenu: true,
                            onTap: _bulkAssign,
                          ),
                          WebBulkAction(
                            icon: Icons.flag_outlined,
                            label: 'Priority',
                            hasMenu: true,
                            onTap: _bulkPriority,
                          ),
                          WebBulkAction(
                            icon: Icons.business_outlined,
                            label: 'Transfer',
                            hasMenu: true,
                            onTap: _bulkTransfer,
                          ),
                        ],
                      ),
                    ),
                ],
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

// ---------------------------------------------------------------------------
// Task row — one single-line row per task, columns aligned with
// `_TableHeader`. Hover tint and selected-accent-tint match the tickets
// treatment (subtle bg fill, no border shift).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
