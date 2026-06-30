import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/assets.dart';
import '../../core/export/table_export.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../data/tasks_repository.dart';
import '../../models/meta.dart';
import '../../models/task.dart';
import '../../providers.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/list_controls.dart';
import '../../widgets/paged_list_view.dart';
import '../../widgets/segmented_tabs.dart';
import '../../widgets/selection_check.dart';
import '../../widgets/svg_icon.dart';
import 'widgets/task_row.dart';

/// App filter pills (the `view` param on GET /tasks).
const _views = <({String key, String label})>[
  (key: 'open', label: 'Open'),
  (key: 'mine', label: 'Mine'),
  (key: 'overdue', label: 'Overdue'),
  (key: 'collaborator', label: 'Collaborator'),
  (key: 'all', label: 'All'),
  (key: 'closed', label: 'Closed'),
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
    _loadFacets();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

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

  Future<void> _createTask() async {
    await context.push(Routes.taskNew);
    if (mounted) setState(() => _refresh++);
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

  /// Build the dropdown-pill specs for the controls bar — one per facet that
  /// has options loaded.
  List<FacetControl> _facetControls() => [
    for (final f in _filterFacets)
      if ((_facetOptions[f.key] ?? const []).isNotEmpty)
        (
          label: f.label,
          selected: _filters[f.key]?.id.toString() ?? 'all',
          items: [
            (value: 'all', text: 'All ${f.label.toLowerCase()}'),
            for (final m in _facetOptions[f.key]!)
              (value: '${m.id}', text: m.name),
          ],
          onSelected: (v) => setState(() {
            if (v == 'all') {
              _filters.remove(f.key);
            } else {
              _filters[f.key] = _facetOptions[f.key]!.firstWhere(
                (m) => '${m.id}' == v,
              );
            }
          }),
        ),
  ];

  // Search and the date range are also enforced client-side (see [_matches]);
  // the query carries the tab's view, sort, create-date window and facet
  // filters for the server.
  TaskQuery get _query {
    final b = _dateBounds;
    final tag = _filters['tag'];
    return TaskQuery(
      view: _view,
      sort: _sort,
      order: _order,
      createdFrom: b == null ? null : Fmt.apiDate(b.$1),
      createdTo: b == null ? null : Fmt.apiDate(b.$2),
      deptId: _filters['dept']?.id,
      priorityId: _filters['priority']?.id,
      assigneeId: _filters['agent']?.id,
      tagId: tag == null ? null : [tag.id],
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
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => ListView(
        shrinkWrap: true,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final m in items)
            ListTile(
              title: Text(m.name),
              onTap: () => Navigator.pop(context, m.id),
            ),
        ],
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
    final meName = ref.read(meProvider).asData?.value.name;
    setState(() => _exporting = true);
    try {
      // Export exactly what's visible: the view's rows, narrowed by the active
      // search.
      final tasks = (await _gatherAll(_query))
          .where((t) => _matches(t, meName))
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

  /// Best-effort client-side filter so each tab visibly differs even if the
  /// backend ignores `view`, plus instant text matching as the user types.
  bool _matches(Task t, String? meName) {
    final viewOk = switch (_view) {
      'open' => t.isOpen,
      'closed' => !t.isOpen,
      'overdue' => t.overdue,
      'mine' =>
        meName == null || meName.isEmpty
            ? true // identity not loaded yet — defer to the server
            : (t.assignee ?? '').toLowerCase().contains(meName.toLowerCase()),
      _ => true, // 'collaborator'/'all' aren't derivable client-side
    };
    if (!viewOk) return false;

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
  Widget _selectionBar() {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleSelectAll,
            child: Row(
              children: [
                SelectionCheck(selected: _allVisibleSelected, size: 20),
                const SizedBox(width: 10),
                Text('Select all', style: labelStyle),
              ],
            ),
          ),
          const Spacer(),
          Text(
            '${_selected.length} selected',
            style: labelStyle.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _selectionAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel',
        onPressed: _clearSelection,
      ),
      title: Text('${_selected.length} selected'),
      actions: _bulkBusy
          ? const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ),
            ]
          : [
              IconButton(
                tooltip: 'Mark complete',
                icon: const Icon(Icons.task_alt),
                onPressed: () => _runBulk(
                  'Completed',
                  (t) => ref.read(tasksRepositoryProvider).close(t),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: _onBulkMenu,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'reopen', child: Text('Reopen')),
                  PopupMenuItem(value: 'assign', child: Text('Assign to agent…')),
                  PopupMenuItem(value: 'priority', child: Text('Set priority…')),
                  PopupMenuItem(
                    value: 'transfer',
                    child: Text('Transfer department…'),
                  ),
                ],
              ),
            ],
    );
  }

  PreferredSizeWidget _normalAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tasks'),
          if (_total != null)
            Text('$_total total', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        IconButton(
          icon: const SvgIcon(Assets.bell, size: 22),
          onPressed: () => context.push(Routes.notifications),
        ),
        if (_exporting)
          const IconButton(
            tooltip: 'Downloading…',
            onPressed: null,
            icon: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
          )
        else
          PopupMenuButton<ExportFormat>(
            tooltip: 'Download',
            position: PopupMenuPosition.under,
            icon: const SvgIcon(Assets.download, size: 22),
            onSelected: _runExport,
            itemBuilder: (context) => [
              for (final f in ExportFormat.values)
                PopupMenuItem<ExportFormat>(
                  value: f,
                  child: Row(
                    children: [
                      Icon(f.icon, size: 20),
                      const SizedBox(width: 12),
                      Text('Download ${f.label}'),
                    ],
                  ),
                ),
            ],
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(90),
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
              ),
            ),
            SegmentedTabs(
              items: _views,
              selectedKey: _view,
              onSelected: (k) => setState(() => _view = k),
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
      if (next != _view) setState(() => _view = next);
      ref.read(tasksViewRequestProvider.notifier).set(null);
    });

    final meName = ref.watch(meProvider).asData?.value.name;
    final repo = ref.watch(tasksRepositoryProvider);
    final query = _query;

    return Scaffold(
      appBar: _selectionMode ? _selectionAppBar() : _normalAppBar(),
      floatingActionButton: _selectionMode
          ? null
          : Padding(
              // Lift above the floating nav bar (it overlaps the body).
              padding: const EdgeInsets.only(bottom: 120),
              child: FloatingActionButton(
                onPressed: _createTask,
                tooltip: 'New task',
                child: const Icon(Icons.add),
              ),
            ),
      body: Column(
        children: [
          if (_selectionMode)
            _selectionBar()
          else
            ListControlsBar(
              dateRange: _dateRange,
              onDateRange: (r) => setState(() => _dateRange = r),
              sortItems: _sortItems,
              sortKey: _sort,
              onSort: (s) => setState(() => _sort = s),
              facets: _facetControls(),
            ),
          Expanded(
            child: PagedListView(
              fabClearance: !_selectionMode,
              refreshKey: '$_view|${_dateRange.name}|$_sort|$_filterSig|$_refresh',
              itemFilter: (t) => _matches(t, meName),
              itemSort: _sort == 'thread' ? null : _compare,
              onItems: _onItems,
              onTotalChanged: (t) {
                if (mounted && t != _total) setState(() => _total = t);
              },
              emptyMessage: 'No tasks',
              emptyHint: 'Try a different filter or search.',
              fetch: (page) => repo.list(query.copyWith(page: page)),
              itemBuilder: (context, t) => TaskRow(
                task: t,
                selectionMode: _selectionMode,
                selected: _selected.contains(t.id),
                onToggle: () => _toggle(t.id),
                onTap: () => context.push(Routes.task(t.id)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
