import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/assets.dart';
import '../../core/router/routes.dart';
import '../../data/tasks_repository.dart';
import '../../providers.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/paged_list_view.dart';
import '../../widgets/segmented_tabs.dart';
import '../../widgets/svg_icon.dart';
import 'widgets/task_card.dart';

/// App filter pills (the `view` param on GET /tasks).
const _views = <({String key, String label})>[
  (key: 'open', label: 'Open'),
  (key: 'mine', label: 'Mine'),
  (key: 'overdue', label: 'Overdue'),
  (key: 'collaborator', label: 'Collaborator'),
  (key: 'all', label: 'All'),
  (key: 'closed', label: 'Closed'),
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
  int? _total;
  int _refresh = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _createTask() async {
    await context.push(Routes.taskNew);
    if (mounted) setState(() => _refresh++);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(tasksRepositoryProvider);
    final query = TaskQuery(
      view: _view,
      q: _search.isEmpty ? null : _search,
      sort: 'created',
      order: 'desc',
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tasks'),
            if (_total != null)
              Text('$_total total',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          IconButton(
            icon: const SvgIcon(Assets.bell, size: 22),
            onPressed: () => context.push(Routes.notifications),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: AppSearchField(
                  controller: _searchCtrl,
                  hintText: 'Search tasks or #number',
                  onSubmitted: (v) => setState(() => _search = v.trim()),
                  onClear: () => setState(() => _search = ''),
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
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createTask,
        tooltip: 'New task',
        child: const Icon(Icons.add),
      ),
      body: PagedListView(
        fabClearance: true,
        refreshKey: '$_view|$_search|$_refresh',
        onTotalChanged: (t) {
          if (mounted && t != _total) setState(() => _total = t);
        },
        emptyMessage: 'No tasks',
        emptyHint: 'Try a different filter or search.',
        fetch: (page) => repo.list(query.copyWith(page: page)),
        itemBuilder: (context, t) => TaskCard(
          task: t,
          onTap: () => context.push(Routes.task(t.id)),
        ),
      ),
    );
  }
}
