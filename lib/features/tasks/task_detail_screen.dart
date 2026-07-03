import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parchment/codecs.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../models/common.dart';
import '../../models/meta.dart';
import '../../models/task.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/pickers.dart';
import '../../widgets/states.dart';
import '../../widgets/status_chip.dart';
import '../tickets/widgets/thread_entry_tile.dart';
import 'widgets/task_card.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final int taskId;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  // Controls the outer (header) scroll view of the NestedScrollView, so its
  // offset tells us when the collapsing header (which holds the title) has
  // scrolled behind the pinned app bar.
  final ScrollController _headerScroll = ScrollController();

  Task? _task;
  List<ThreadEntry> _thread = [];
  List<Task> _subtasks = [];
  List<TaskDependency> _dependencies = [];
  Object? _error;
  bool _loading = true;
  bool _acting = false;
  bool _titleInBar = false;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTab);
    _headerScroll.addListener(_onHeaderScroll);
    _load();
  }

  void _onTab() {
    if (mounted) setState(() {}); // toggle the composer per active tab
  }

  /// Whether the composer (only shown for the Conversation tab, index 0) should
  /// be visible. Uses the controller's live [animation] value rather than
  /// [index] so the field hides the instant a swipe starts moving away â€” a
  /// small threshold means it disappears as soon as the drag begins, matching
  /// the immediate hide you get when tapping another tab.
  bool get _onConversationTab => (_tabs.animation?.value ?? 0) < 0.05;

  // Show the title in the app bar once the collapsing header has scrolled
  // behind the pinned app bar.
  void _onHeaderScroll() {
    final show = _headerScroll.offset > 28;
    if (show != _titleInBar && mounted) {
      setState(() => _titleInBar = show);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _headerScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = ref.read(tasksRepositoryProvider);
    try {
      final task = await repo.get(widget.taskId);
      final thread = await repo.thread(widget.taskId, limit: 50);
      final subtasks = await repo.subtasks(widget.taskId);
      final dependencies = await repo.dependencies(widget.taskId);
      if (!mounted) return;
      setState(() {
        _task = task;
        _thread = thread.items;
        _subtasks = subtasks;
        _dependencies = dependencies;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _apply(Task updated) => setState(() => _task = updated);

  void _toast(String msg) => AppSnack.info(context, msg);

  Future<void> _runAction(
    Future<Task> Function() action, {
    String? success,
  }) async {
    setState(() => _acting = true);
    try {
      final updated = await action();
      _apply(updated);
      if (success != null) _toast(success);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  PopupMenuButton<String> _menu(Task t) => PopupMenuButton<String>(
    onSelected: _onMenu,
    itemBuilder: (_) => [
      // Workflow.
      if (t.isOpen)
        _menuItem('close', Icons.check_circle_outline, 'Close')
      else
        _menuItem('reopen', Icons.replay, 'Reopen'),
      _menuItem('progress', Icons.percent, 'Edit progress'),
      const PopupMenuDivider(),
      // Assignment & attributes.
      _menuItem('assign', Icons.assignment_ind_outlined, 'Assign'),
      _menuItem('transfer', Icons.apartment_outlined, 'Transfer dept'),
      _menuItem('priority', Icons.flag_outlined, 'Set priority'),
      const PopupMenuDivider(),
      // Metadata.
      _menuItem('collaborators', Icons.group_outlined, 'Collaborators'),
    ],
  );

  /// A â‹®-menu row with a leading icon.
  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          AppText.subText(context, label),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _task;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task')),
        body: const LoadingView(),
      );
    }
    if (_error != null || t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task')),
        body: ErrorView(error: _error ?? 'Not found', onRetry: _load),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: NestedScrollView(
              controller: _headerScroll,
              headerSliverBuilder: (context, _) => [
                SliverAppBar(
                  pinned: true,
                  title: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('#${t.number}'),
                      if (_titleInBar)
                        AppText.paraText(
                          context,
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          color: Theme.of(context)
                              .appBarTheme
                              .foregroundColor
                              ?.withValues(alpha: 0.8),
                        ),
                    ],
                  ),
                  actions: [_menu(t)],
                ),
                SliverToBoxAdapter(child: _CollapsingHeader(task: t)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverTabBarDelegate(
                    TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorPadding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 2,
                      ),
                      tabs: const [
                        Tab(text: 'Conversation'),
                        Tab(text: 'Details'),
                        Tab(text: 'Subtasks'),
                        Tab(text: 'Dependencies'),
                      ],
                    ),
                  ),
                ),
              ],
              body: Column(
                children: [
                  if (_acting) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _ConversationTab(thread: _thread),
                        _DetailsTab(task: t, onEdit: _onMenu),
                        _SubtasksTab(
                          subtasks: _subtasks,
                          onTap: (st) => context.push(Routes.task(st.id)),
                          onAdd: _addSubtask,
                        ),
                        _DependenciesTab(
                          dependencies: _dependencies,
                          onAdd: _addDependency,
                          onRemove: _removeDependency,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Rebuild on every swipe frame (the controller's own listener only
          // fires on settled index changes) so the composer hides the instant
          // the user drags away from the Conversation tab.
          ListenableBuilder(
            listenable: _tabs.animation!,
            builder: (context, _) => _onConversationTab
                ? _InlineComposer(taskId: widget.taskId, onSent: _load)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(String value) async {
    final repo = ref.read(tasksRepositoryProvider);
    switch (value) {
      case 'status':
        // From the Details tab's Status row: pick Open/Completed rather than
        // toggling instantly, so a mis-tap can't silently change state.
        await _pickStatus();
      case 'close':
        await _runAction(
          () => repo.close(widget.taskId),
          success: 'Task closed',
        );
        await _load();
      case 'reopen':
        await _runAction(
          () => repo.reopen(widget.taskId),
          success: 'Task reopened',
        );
        await _load();
      case 'assign':
        await _pickMeta(MetaKind.agents, title: 'Assign to', (id) async {
          await _runAction(
            () => repo.assign(widget.taskId, staffId: id),
            success: 'Assigned',
          );
          await _load();
        });
      case 'transfer':
        await _pickMeta(MetaKind.departments, title: 'Transfer department',
            selectedId: _task?.departmentId, (id) async {
          await _runAction(
            () => repo.transfer(widget.taskId, id),
            success: 'Transferred',
          );
          await _load();
        });
      case 'progress':
        await _editProgress();
      case 'priority':
        await _pickMeta(MetaKind.taskPriorities, title: 'Set priority',
            selectedId: _task?.priority?.id, (id) async {
          await _runAction(
            () => repo.edit(widget.taskId, priorityId: id),
            success: 'Priority updated',
          );
          await _load();
        });
      case 'collaborators':
        await showDialog<void>(
          context: context,
          builder: (_) => _TaskCollaboratorsSheet(taskId: widget.taskId),
        );
    }
  }

  Future<void> _addSubtask() async {
    final created = await showAppSheet<bool>(
      context: context,
      builder: (_) => _SubtaskSheet(taskId: widget.taskId),
    );
    if (created == true) await _load();
  }

  Future<void> _addDependency() async {
    final id = await showDialog<int>(
      context: context,
      builder: (_) => const _DependencyDialog(),
    );
    if (id == null) return;
    setState(() => _acting = true);
    try {
      final deps = await ref
          .read(tasksRepositoryProvider)
          .addDependency(widget.taskId, id);
      if (mounted) setState(() => _dependencies = deps);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
    await _load();
  }

  Future<void> _removeDependency(int depId) async {
    setState(() => _acting = true);
    try {
      final deps = await ref
          .read(tasksRepositoryProvider)
          .removeDependency(widget.taskId, depId);
      if (mounted) setState(() => _dependencies = deps);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
    await _load();
  }

  Future<void> _pickMeta(
    String kind,
    Future<void> Function(int id) onPick, {
    String title = 'Select',
    int? selectedId,
  }) async {
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(kind);
    } on ApiException catch (e) {
      _toast(e.message);
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => _MetaPickerDialog(
        title: title,
        items: items,
        selectedId: selectedId,
      ),
    );
    if (chosen != null) await onPick(chosen);
  }

  Future<void> _editProgress() async {
    final value = await showDialog<int>(
      context: context,
      builder: (_) => _ProgressDialog(initial: _task?.progress ?? 0),
    );
    if (value == null) return;
    await _runAction(
      () => ref
          .read(tasksRepositoryProvider)
          .edit(widget.taskId, progress: value),
      success: 'Progress updated',
    );
    await _load();
  }

  /// Task status is binary (Open / Completed) driven by reopen/close. Present
  /// it as a picker so the change is deliberate; apply only if it differs.
  Future<void> _pickStatus() async {
    final isOpen = _task?.isOpen ?? true;
    final wantOpen = await showDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: 'Status',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PickerOptionTile(
              label: 'Open',
              selected: isOpen,
              onTap: () => Navigator.pop(context, true),
            ),
            PickerOptionTile(
              label: 'Completed',
              selected: !isOpen,
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (wantOpen == null || wantOpen == isOpen) return; // dismissed / unchanged
    await _onMenu(wantOpen ? 'reopen' : 'close');
  }
}

// --- Collapsing header (status + progress; scrolls away under the app bar) ---

class _CollapsingHeader extends StatelessWidget {
  const _CollapsingHeader({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.titleText(
            context,
            task.title,
            fw: 2,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip.status(task.statusName, dense: true),
              if (task.priority != null)
                StatusChip.priority(task.priority!.name, dense: true),
              if (task.overdue)
                const StatusChip(
                  label: 'Overdue',
                  color: Color(0xFFD32F2F),
                  icon: Icons.warning_amber_rounded,
                  dense: true,
                ),
            ],
          ),
          if (task.progress > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (task.progress / 100).clamp(0, 1),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            AppText.paraText(
              context,
              'Progress: ${task.progress}%',
              color: theme.colorScheme.onSurface,
            ),
          ],
          if (task.blocked) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: Color(0xFFD32F2F),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppText.paraText(
                      context,
                      'Blocked by an open dependency',
                      color: const Color(0xFFD32F2F),
                      fw: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pins the tab bar below the (collapsing) header.
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate old) => old.tabBar != tabBar;
}

// --- Tabs -------------------------------------------------------------------

class _ConversationTab extends StatelessWidget {
  const _ConversationTab({required this.thread});
  final List<ThreadEntry> thread;

  @override
  Widget build(BuildContext context) {
    if (thread.isEmpty) {
      return const EmptyView(message: 'No messages yet');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: thread.length,
      itemBuilder: (_, i) => ThreadEntryTile(entry: thread[i]),
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({required this.task, required this.onEdit});
  final Task task;

  /// Routes an edit intent (matching the â‹®-menu action keys) back to the host.
  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Editable attributes â€” tap to open the matching picker/editor.
        _DetailSection(
          title: 'Attributes',
          children: [
            _DetailRow(
              icon: Icons.published_with_changes,
              label: 'Status',
              value: task.statusName,
              onTap: () => onEdit('status'),
            ),
            _DetailRow(
              icon: Icons.flag_outlined,
              label: 'Priority',
              value: task.priority?.name,
              placeholder: 'Set priority',
              onTap: () => onEdit('priority'),
            ),
            _DetailRow(
              icon: Icons.percent,
              label: 'Progress',
              value: '${task.progress}%',
              onTap: () => onEdit('progress'),
            ),
            _DetailRow(
              icon: Icons.apartment_outlined,
              label: 'Department',
              value: task.departmentName,
              placeholder: 'Transfer',
              onTap: () => onEdit('transfer'),
            ),
            _DetailRow(
              icon: Icons.assignment_ind_outlined,
              label: 'Assignee',
              value: task.assignee,
              placeholder: 'Assign',
              onTap: () => onEdit('assign'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Read-only metadata.
        _DetailSection(
          title: 'Information',
          children: [
            _DetailRow(
              icon: Icons.tag,
              label: 'Number',
              value: task.number,
            ),
            _DetailRow(
              icon: Icons.schedule,
              label: 'Created',
              value: Fmt.dateTime(task.created),
            ),
            _DetailRow(
              icon: Icons.update,
              label: 'Updated',
              value: Fmt.dateTime(task.updated),
            ),
            _DetailRow(
              icon: Icons.event_outlined,
              label: 'Due',
              value: Fmt.dateTime(task.duedate),
            ),
          ],
        ),
        if (task.customFields.isNotEmpty) ...[
          const SizedBox(height: 16),
          _DetailSection(
            title: 'Custom fields',
            children: [
              for (final e in task.customFields.entries)
                _DetailRow(
                  icon: Icons.list_alt_outlined,
                  label: e.key,
                  value: e.value,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A titled card grouping a set of [_DetailRow]s.
class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: AppText.custmText(
            context,
            title.toUpperCase(),
            fs: 10,
            color: scheme.onSurfaceVariant,
            fw: 2,
            letterSpacing: 0.5,
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i != 0) const Divider(height: 1, indent: 52),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A single detail row. When [onTap] is set it renders as tappable (chevron +
/// ripple); otherwise it's static. A null/empty [value] shows [placeholder]
/// in a muted style.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.placeholder,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? placeholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final has = value != null && value!.isNotEmpty && value != 'â€”';
    // Static rows with no value at all render nothing.
    if (!has && onTap == null) return const SizedBox.shrink();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 16),
            SizedBox(
              width: 96,
              child: AppText.subText(
                context,
                label,
                color: scheme.onSurfaceVariant,
              ),
            ),
            Expanded(
              child: AppText.subText(
                context,
                has ? value! : (placeholder ?? 'â€”'),
                fw: has ? 1 : 3,
                color: has ? scheme.onSurface : scheme.primary,
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _SubtasksTab extends StatelessWidget {
  const _SubtasksTab({
    required this.subtasks,
    required this.onTap,
    required this.onAdd,
  });
  final List<Task> subtasks;
  final ValueChanged<Task> onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add subtask'),
            ),
          ),
        ),
        Expanded(
          child: subtasks.isEmpty
              ? const EmptyView(message: 'No subtasks')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: subtasks.length,
                  itemBuilder: (_, i) => TaskCard(
                    task: subtasks[i],
                    onTap: () => onTap(subtasks[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DependenciesTab extends StatelessWidget {
  const _DependenciesTab({
    required this.dependencies,
    required this.onAdd,
    required this.onRemove,
  });
  final List<TaskDependency> dependencies;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add dependency'),
            ),
          ),
        ),
        Expanded(
          child: dependencies.isEmpty
              ? const EmptyView(message: 'No dependencies')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: dependencies.length,
                  itemBuilder: (context, i) {
                    final dep = dependencies[i];
                    final blocker = dep.blocker;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      child: ListTile(
                        leading: Icon(
                          blocker == null
                              ? Icons.link
                              : blocker.open
                              ? Icons.lock_outline
                              : Icons.check_circle_outline,
                          color: blocker != null && blocker.open
                              ? const Color(0xFFD32F2F)
                              : Theme.of(context).colorScheme.primary,
                        ),
                        title: AppText.subText(
                          context,
                          blocker == null
                              ? 'Dependency #${dep.id}'
                              : '#${blocker.number} ${blocker.title}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: AppText.subText(
                          context,
                          dep.required ? 'Required' : 'Optional',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Remove',
                          onPressed: () => onRemove(dep.id),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// --- Progress dialog --------------------------------------------------------

class _ProgressDialog extends StatefulWidget {
  const _ProgressDialog({required this.initial});
  final int initial;

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  late double _value = widget.initial.toDouble().clamp(0, 100);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppDialog(
      title: 'Edit progress',
      actionLabel: 'Save',
      onAction: () => Navigator.pop(context, _value.round()),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText.custmText(
            context,
            '${_value.round()}%',
            fs: 20,
            fw: 1,
            color: scheme.primary,
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (_value / 100).clamp(0, 1),
              minHeight: 10,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 24),
          Slider(
            value: _value,
            min: 0,
            max: 100,
            divisions: 100,
            label: '${_value.round()}%',
            onChanged: (v) => setState(() => _value = v),
            activeColor: scheme.primary,
            inactiveColor: scheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

// --- Meta picker dialog (with search) ----------------------------------------

class _MetaPickerDialog extends StatefulWidget {
  const _MetaPickerDialog({
    required this.title,
    required this.items,
    this.selectedId,
  });

  final String title;
  final List<MetaItem> items;
  final int? selectedId;

  @override
  State<_MetaPickerDialog> createState() => _MetaPickerDialogState();
}

class _MetaPickerDialogState extends State<_MetaPickerDialog> {
  final _searchCtrl = TextEditingController();
  late List<MetaItem> _filtered = widget.items;

  /// Only show the search field for lists long enough to warrant it; short
  /// pick-lists (priorities, statuses, â€¦) don't need one.
  bool get _searchable => widget.items.length > 8;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_updateFilter);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_updateFilter);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _updateFilter() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = widget.items
          .where((item) => item.name.toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      title: widget.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_searchable) ...[
            SheetSearchField(
              controller: _searchCtrl,
              hintText: 'Search',
            ),
            const SizedBox(height: 12),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: _filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: AppText.subText(
                      context,
                      'No results found',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final item in _filtered)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(context, item.id),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: AppText.subText(
                                context,
                                item.name,
                                color: item.id == widget.selectedId
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                                fw: item.id == widget.selectedId ? 2 : 3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// --- Composer (reply/note) --------------------------------------------------

class _InlineComposer extends ConsumerStatefulWidget {
  const _InlineComposer({required this.taskId, required this.onSent});
  final int taskId;
  final Future<void> Function() onSent;

  @override
  ConsumerState<_InlineComposer> createState() => _InlineComposerState();
}

class _InlineComposerState extends ConsumerState<_InlineComposer> {
  final FleatherController _controller = FleatherController();
  final FocusNode _focus = FocusNode();
  final List<PlatformFile> _files = [];
  bool _note = false; // false = reply, true = internal note
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onChange);
    _controller.addListener(_onChange);
  }

  // Rebuilds so the hint, send-enabled state and toolbar track edits/focus.
  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onChange);
    _controller.removeListener(_onChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _isEmpty => _controller.document.toPlainText().trim().isEmpty;

  void _clearDocument() {
    final len = _controller.document.length;
    if (len > 1) {
      _controller.replaceText(
        0,
        len - 1,
        '',
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
  }

  Future<void> _attach(AttachSource source) async {
    final picked = await pickAttachmentsOf(source);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (!_files.any((e) => e.name == f.name)) _files.add(f);
      }
    });
  }

  /// Sends the document (as HTML) plus attachments. Returns true on success so
  /// the fullscreen editor knows when to close.
  Future<bool> _send() async {
    final empty = _isEmpty;
    if (empty && _files.isEmpty) return false;
    setState(() => _sending = true);
    final repo = ref.read(tasksRepositoryProvider);
    try {
      final files = [
        for (final f in _files)
          if (f.bytes != null)
            MultipartFile.fromBytes(f.bytes!, filename: f.name),
      ];
      final body = empty ? '' : parchmentHtml.encode(_controller.document);
      if (_note) {
        await repo.note(widget.taskId, body: body, files: files);
      } else {
        await repo.reply(widget.taskId, body: body, alert: true, files: files);
      }
      _clearDocument();
      if (mounted) setState(() => _files.clear());
      await widget.onSent();
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        AppSnack.error(context, e.message);
      }
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openFullscreen() async {
    _focus.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FullscreenEditor(
          controller: _controller,
          note: _note,
          onSend: _send,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _note ? AppTheme.warning : scheme.primary;
    final noteTint = AppTheme.warning.withValues(alpha: isDark ? 0.10 : 0.07);
    final barColor = isDark ? const Color(0xFF121B22) : scheme.surface;
    final pillColor = isDark ? const Color(0xFF1F2C34) : Colors.white;
    final canSend = !_isEmpty || _files.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: _note ? Color.alphaBlend(noteTint, barColor) : barColor,
        border: Border(
          top: BorderSide(
            color: _note
                ? accent.withValues(alpha: 0.5)
                : scheme.outlineVariant,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ModeToggle(
                    note: _note,
                    onChanged: (v) => setState(() => _note = v),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Expand',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.open_in_full,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: _openFullscreen,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (_files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final f in _files)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(
                            Icons.insert_drive_file_outlined,
                            size: 16,
                          ),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: AppText.subText(
                              context,
                              f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          onDeleted: () => setState(() => _files.remove(f)),
                        ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: pillColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _note
                              ? accent
                              : scheme.outlineVariant.withValues(alpha: 0.7),
                          width: _note ? 1.4 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                FleatherEditor(
                                  controller: _controller,
                                  focusNode: _focus,
                                  minHeight: 24,
                                  maxHeight: 120,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                                if (_isEmpty)
                                  Positioned(
                                    left: 0,
                                    top: 10,
                                    child: IgnorePointer(
                                      child: AppText.subText(
                                        context,
                                        _note
                                            ? 'Internal note (staff only)'
                                            : 'Add a comment',
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          PopupMenuButton<AttachSource>(
                            tooltip: 'Attach',
                            position: PopupMenuPosition.over,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            icon: Transform.rotate(
                              angle: -0.7,
                              child: Icon(
                                Icons.attach_file,
                                size: 22,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            onSelected: _attach,
                            itemBuilder: (_) => attachMenuItems(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _sending
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.6),
                          ),
                        )
                      : Material(
                          color: canSend
                              ? accent
                              : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: canSend ? _send : null,
                            child: Padding(
                              padding: const EdgeInsets.all(11),
                              child: Icon(
                                _note ? Icons.note_add : Icons.send,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                ],
              ),
              if (_focus.hasFocus) ...[
                const SizedBox(height: 2),
                FleatherToolbar.basic(
                  controller: _controller,
                  hideBackgroundColor: true,
                  hideForegroundColor: true,
                  hideDirection: true,
                  hideListChecks: true,
                  hideHorizontalRule: true,
                  hideAlignment: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen rich-text editor that shares the composer's [FleatherController].
class _FullscreenEditor extends StatefulWidget {
  const _FullscreenEditor({
    required this.controller,
    required this.note,
    required this.onSend,
  });

  final FleatherController controller;
  final bool note;
  final Future<bool> Function() onSend;

  @override
  State<_FullscreenEditor> createState() => _FullscreenEditorState();
}

class _FullscreenEditorState extends State<_FullscreenEditor> {
  final FocusNode _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final ok = await widget.onSend();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.note
        ? AppTheme.warning
        : Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Collapse',
          icon: const Icon(Icons.close_fullscreen),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.note ? 'Internal note' : 'Reply'),
        actions: [
          _sending
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: accent),
                    onPressed: _send,
                    icon: Icon(
                      widget.note ? Icons.note_add : Icons.send,
                      size: 18,
                    ),
                    label: const Text('Send'),
                  ),
                ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FleatherEditor(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: true,
              expands: true,
              padding: const EdgeInsets.all(16),
            ),
          ),
          SafeArea(
            top: false,
            child: FleatherToolbar.basic(controller: widget.controller),
          ),
        ],
      ),
    );
  }
}

/// Segmented Reply / Internal note selector shown above the composer input.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.note, required this.onChanged});

  final bool note;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFF1F1F1);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            context: context,
            label: 'Reply',
            icon: Icons.reply_rounded,
            selected: !note,
            selectedColor: scheme.primary,
            onTap: () => onChanged(false),
          ),
          _segment(
            context: context,
            label: 'Internal note',
            icon: Icons.sticky_note_2_outlined,
            selected: note,
            selectedColor: AppTheme.warning,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool selected,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? selectedColor : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              AppText.custmText(
                context,
                label,
                fs: 13,
                fw: selected ? 1 : 0,
                color: selected ? Colors.white : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Subtask sheet ----------------------------------------------------------

class _SubtaskSheet extends ConsumerStatefulWidget {
  const _SubtaskSheet({required this.taskId});
  final int taskId;

  @override
  ConsumerState<_SubtaskSheet> createState() => _SubtaskSheetState();
}

class _SubtaskSheetState extends ConsumerState<_SubtaskSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _description.text.trim().isEmpty) {
      setState(() => _error = 'Title and description are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // dept_id is inherited from the parent task.
      await ref.read(tasksRepositoryProvider).createSubtask(widget.taskId, {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'New subtask',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            AppText.subText(
              context,
              _error!,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _title,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Description',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('Create subtask'),
          ),
        ],
      ),
    );
  }
}

// --- Dependency dialog ------------------------------------------------------

class _DependencyDialog extends StatefulWidget {
  const _DependencyDialog();

  @override
  State<_DependencyDialog> createState() => _DependencyDialogState();
}

class _DependencyDialogState extends State<_DependencyDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final id = int.tryParse(_ctrl.text.trim());
    if (id == null || id <= 0) {
      setState(() => _error = 'Enter a valid task id');
      return;
    }
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Add dependency',
      actionLabel: 'Add',
      onAction: _submit,
      child: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Blocking task id',
          hintText: 'e.g. 412',
          errorText: _error,
        ),
      ),
    );
  }
}

// --- Collaborators sheet ----------------------------------------------------

class _TaskCollaboratorsSheet extends ConsumerStatefulWidget {
  const _TaskCollaboratorsSheet({required this.taskId});
  final int taskId;

  @override
  ConsumerState<_TaskCollaboratorsSheet> createState() =>
      _TaskCollaboratorsSheetState();
}

class _TaskCollaboratorsSheetState
    extends ConsumerState<_TaskCollaboratorsSheet> {
  List<Collaborator> _collabs = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String m) => AppSnack.error(context, m);

  Future<void> _load() async {
    try {
      final c = await ref
          .read(tasksRepositoryProvider)
          .collaborators(widget.taskId);
      if (mounted) {
        setState(() {
          _collabs = c;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(e.message);
      }
    }
  }

  Future<void> _add() async {
    final user = await pickUser(context, ref);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(tasksRepositoryProvider)
          .addCollaborator(widget.taskId, user.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(int cid) async {
    setState(() => _busy = true);
    try {
      final c = await ref
          .read(tasksRepositoryProvider)
          .removeCollaborator(widget.taskId, cid);
      if (mounted) setState(() => _collabs = c);
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Collaborators',
      actionLabel: 'Add collaborator',
      onAction: _busy ? null : _add,
      actionEnabled: !_busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_collabs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AppText.subText(context, 'No collaborators'),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in _collabs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: AppText.subText(context, c.name),
                      subtitle: c.email != null
                          ? AppText.subText(context, c.email!)
                          : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _busy ? null : () => _remove(c.id),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
