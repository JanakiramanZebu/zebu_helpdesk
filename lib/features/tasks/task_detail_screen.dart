import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/assets.dart';
import '../../data/agent_directory.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../models/common.dart';
import '../../models/me.dart';
import '../../models/meta.dart';
import '../../models/task.dart';
import '../../providers.dart';
import '../../widgets/action_menu.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/message_composer.dart';
import '../../widgets/pickers.dart';
import '../../widgets/reassign_dialog.dart';
import '../../widgets/states.dart';
import '../../widgets/status_chip.dart';
import '../tickets/widgets/thread_entry_tile.dart';
import 'widgets/task_card.dart';

/// Per-agent action gates for a task, ported from osTicket's
/// `Task::checkStaffPerm()` (`include/class.task.php`). The backend enforces
/// these on every mutating `/tasks/*` endpoint (403 otherwise); mirroring them
/// here hides the affordances an agent can't use — matching the SCP rule that a
/// task "cannot be edited by others". Visibility is already granted (the detail
/// loaded), so only the per-department role permission matters.
class _TaskCaps {
  const _TaskCaps({
    this.canEdit = false,
    this.canCreate = false,
    this.canAssign = false,
    this.canTransfer = false,
    this.canClose = false,
    this.canReply = false,
  });

  final bool canEdit; // task.edit — priority, dependencies
  final bool canCreate; // task.create — add subtask
  final bool canAssign; // task.assign
  final bool canTransfer; // task.transfer — department change
  final bool canClose; // task.close — close / reopen / status
  final bool canReply; // task.reply — reply + internal note

  /// At least one item in the overflow (⋮) menu is available.
  bool get hasMenuAction => canClose || canAssign || canTransfer || canEdit;

  factory _TaskCaps.from(Me? me, Task? task) {
    if (me == null || task == null) return const _TaskCaps();
    final d = task.departmentId;
    return _TaskCaps(
      canEdit: me.canOn('task.edit', d),
      canCreate: me.canOn('task.create', d),
      canAssign: me.canOn('task.assign', d),
      canTransfer: me.canOn('task.transfer', d),
      canClose: me.canOn('task.close', d),
      canReply: me.canOn('task.reply', d),
    );
  }
}

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId, this.seed});
  final int taskId;

  /// The list row's task, passed via the route's `extra` when navigating from a
  /// list/subtask. The detail endpoint (`/tasks/{id}`) omits the due date, but
  /// the list summary carries it — so we graft the seed's due date onto the
  /// fetched detail when the response lacks one. Null for deep-link/push entry.
  final Task? seed;

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  // Controls the outer (header) scroll view of the NestedScrollView, so its
  // offset tells us when the collapsing header (which holds the title) has
  // scrolled behind the pinned app bar.
  final ScrollController _headerScroll = ScrollController();

  Task? _task;
  List<ThreadEntry> _thread = [];
  List<ThreadEvent> _events = [];
  List<Task> _subtasks = [];
  List<TaskDependency> _dependencies = [];
  Object? _error;
  bool _loading = true;
  bool _acting = false;
  bool _titleInBar = false;
  // Message the composer is quoting (set from a bubble's long-press → Reply).
  ThreadEntry? _replyTo;

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

  // [silent] refreshes the data in place without flashing the full-screen
  // loader â€” used after sending a message so the conversation just updates.
  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    final repo = ref.read(tasksRepositoryProvider);
    try {
      var task = await repo.get(widget.taskId);
      // The detail endpoint omits the due date; graft it from the list row we
      // came in with (same task) so the Due row and overdue chip still show.
      final seed = widget.seed;
      if (task.duedate == null &&
          seed != null &&
          seed.id == task.id &&
          seed.duedate != null) {
        task = task.copyWith(duedate: seed.duedate, overdue: seed.overdue);
      }
      final thread = await repo.thread(widget.taskId, limit: 50);
      final events = await repo.events(widget.taskId);
      final subtasks = await repo.subtasks(widget.taskId);
      final dependencies = await repo.dependencies(widget.taskId);
      if (!mounted) return;
      setState(() {
        _task = task;
        _thread = thread.items;
        _events = events;
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

  /// Composer transport: post the body (reply or internal note) plus any
  /// attachments, then silently refresh the thread. Returns false on failure so
  /// the composer keeps the draft.
  Future<bool> _sendMessage({
    required bool note,
    required String html,
    required List<MultipartFile> files,
  }) async {
    final repo = ref.read(tasksRepositoryProvider);
    try {
      if (note) {
        await repo.note(widget.taskId, body: html, files: files);
      } else {
        await repo.reply(widget.taskId, body: html, alert: true, files: files);
      }
      await _load(silent: true);
      // A reply can reopen a closed task and always bumps last activity, both of
      // which the list reflects (status / thread-activity sort).
      _markChanged();
      return true;
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
      return false;
    }
  }

  void _apply(Task updated) {
    _markChanged();
    setState(() => _task = updated);
  }

  /// Signal the Tasks list (and any other listener) that this task changed, so
  /// it refetches instead of showing a stale row after the user backs out. The
  /// list route stays mounted behind us, so it reloads while we're still on top.
  void _markChanged() => ref.read(tasksChangedProvider.notifier).bump();

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

  PopupMenuButton<String> _menu(Task t, _TaskCaps caps) =>
      PopupMenuButton<String>(
        onSelected: _onMenu,
        shape: AppActionMenu.shape,
        color: Theme.of(context).colorScheme.surface,
        elevation: AppActionMenu.elevation,
        menuPadding: AppActionMenu.menuPadding,
        // Only surface actions the agent may perform — each gated by the same
        // permission the matching /tasks endpoint enforces (checkStaffPerm).
        // Collaborators stays available to everyone: the sheet also *views*
        // collaborators, and its add/remove are enforced server-side.
        itemBuilder: (_) => [
          // Workflow.
          if (caps.canClose) ...[
            if (t.isOpen)
              appMenuItem(value: 'close', asset: Assets.actClose, label: 'Close')
            else
              appMenuItem(
                value: 'reopen',
                asset: Assets.actReopen,
                label: 'Reopen',
              ),
          ],
          if (caps.hasMenuAction) const PopupMenuDivider(),
          // Assignment & attributes.
          if (caps.canAssign)
            appMenuItem(value: 'assign', asset: Assets.actAssign, label: 'Assign'),
          if (caps.canTransfer)
            appMenuItem(
              value: 'transfer',
              asset: Assets.actTransfer,
              label: 'Transfer dept',
            ),
          if (caps.canEdit)
            appMenuItem(
              value: 'priority',
              asset: Assets.actPriority,
              label: 'Set priority',
            ),
          if (caps.hasMenuAction) const PopupMenuDivider(),
          // Metadata.
          appMenuItem(
            value: 'collaborators',
            asset: Assets.actCollaborators,
            label: 'Collaborators',
          ),
          // Tags edit the task, so gate on task.edit (matches the ticket menu).
          if (caps.canEdit)
            appMenuItem(value: 'tags', asset: Assets.actTag, label: 'Tags'),
        ],
      );

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

    // Per-agent action gates (ported from Task::checkStaffPerm). `me` is loaded
    // app-wide at startup, so asData is populated by the time this opens; until
    // then caps default to none (safe — the backend would 403 anyway).
    final me = ref.watch(meProvider).asData?.value;
    final caps = _TaskCaps.from(me, t);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
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
                  actions: [_menu(t, caps)],
                ),
                SliverToBoxAdapter(child: _CollapsingHeader(task: t)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverTabBarDelegate(
                    TabBar(
                      controller: _tabs,
                      indicatorPadding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 2,
                      ),
                      tabs: const [
                        Tab(text: 'Conversation'),
                        Tab(text: 'Details'),
                        Tab(text: 'Activity'),
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
                        _ConversationTab(
                          thread: _thread,
                          onReply: (e) => setState(() => _replyTo = e),
                          headerController: _headerScroll,
                        ),
                        _DetailsTab(
                          task: t,
                          caps: caps,
                          onEdit: _onMenu,
                          subtasks: _subtasks,
                          onSubtaskTap: (st) =>
                              context.push(Routes.task(st.id), extra: st),
                          onAddSubtask: _addSubtask,
                          dependencies: _dependencies,
                          onAddDependency: _addDependency,
                          onRemoveDependency: _removeDependency,
                        ),
                        _ActivityTab(events: _events),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The composer floats over the bottom of the conversation (frosted
          // glass), so messages scroll behind it. Rebuild on every swipe frame
          // (the controller's own listener only fires on settled index changes)
          // so the composer hides the instant the user drags off Conversation.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ListenableBuilder(
              listenable: _tabs.animation!,
              // Reply and internal note both require task.reply on the backend,
              // so a single canReply gate covers the whole composer.
              builder: (context, _) => _onConversationTab && caps.canReply
                  ? MessageComposer(
                      hintReply: 'Reply to this task...',
                      replyTo: _replyTo,
                      onClearReply: () => setState(() => _replyTo = null),
                      onSend:
                          ({required note, required html, required files}) =>
                              _sendMessage(
                                note: note,
                                html: html,
                                files: files,
                              ),
                    )
                  : const SizedBox.shrink(),
            ),
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
        await _reassign();
      case 'transfer':
        await _pickMeta(MetaKind.departments, title: 'Transfer department',
            selectedId: _task?.departmentId, (id) async {
          await _runAction(
            () => repo.transfer(widget.taskId, id),
            success: 'Transferred',
          );
          await _load();
        });
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
      case 'tags':
        await showDialog<void>(
          context: context,
          builder: (_) => _TaskTagsSheet(taskId: widget.taskId),
        );
    }
  }

  Future<void> _addSubtask() async {
    final created = await showAppSheet<bool>(
      context: context,
      builder: (_) => _SubtaskSheet(taskId: widget.taskId),
    );
    if (created == true) {
      _markChanged();
      await _load();
    }
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
    _markChanged();
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
    _markChanged();
    await _load();
  }

  /// osTicket-style reassign flow: pick a new assignee and, optionally, record
  /// a reason and keep the current assignee's referral access. Mirrors the web
  /// reassign form rather than the bare agent picker.
  Future<void> _reassign() async {
    // Scoped to the task's department: the server only accepts an assignee that
    // department allows (Dept::canAssign), so the whole roster would offer
    // picks that come back 422.
    final AgentPickList agents;
    setState(() => _acting = true);
    try {
      agents = await ref
          .read(agentDirectoryProvider)
          .assignable(
            departmentName: _task?.departmentName,
            departmentId: _task?.departmentId,
          );
    } on ApiException catch (e) {
      _toast(e.message);
      return;
    } finally {
      if (mounted) setState(() => _acting = false);
    }
    if (!mounted) return;
    final current = _task?.assignee;
    final result = await showReassignDialog(
      context,
      assignees: agents.agents,
      allAssignees: agents.scoped ? agents.all : null,
      scopeDepartment: agents.departmentName,
      title: (current != null && current.isNotEmpty) ? 'Reassign' : 'Assign',
      assigneeLabel: 'Assignee',
      currentAssignee: current,
    );
    if (result == null) return;
    await _runAction(
      () => ref.read(tasksRepositoryProvider).assign(
            widget.taskId,
            staffId: result.assigneeId,
            comments: result.comments,
            refer: result.maintainReferral,
          ),
      success: 'Assigned',
    );
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
  const _ConversationTab({
    required this.thread,
    this.onReply,
    this.headerController,
  });
  final List<ThreadEntry> thread;
  final ValueChanged<ThreadEntry>? onReply;
  final ScrollController? headerController;

  @override
  Widget build(BuildContext context) {
    if (thread.isEmpty) {
      return const EmptyView(message: 'No messages yet');
    }
    // Reserve room for the floating composer so the newest message clears it.
    return ConversationList(
      thread: thread,
      onReply: onReply,
      headerController: headerController,
      bottomReserve: 104 + MediaQuery.of(context).padding.bottom,
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.task,
    required this.caps,
    required this.onEdit,
    required this.subtasks,
    required this.onSubtaskTap,
    required this.onAddSubtask,
    required this.dependencies,
    required this.onAddDependency,
    required this.onRemoveDependency,
  });
  final Task task;

  /// Per-agent action gates — a null onTap/actionLabel below renders the row or
  /// button read-only when the agent lacks the matching permission.
  final _TaskCaps caps;

  /// Routes an edit intent (matching the â‹®-menu action keys) back to the host.
  final ValueChanged<String> onEdit;

  final List<Task> subtasks;
  final ValueChanged<Task> onSubtaskTap;
  final VoidCallback onAddSubtask;

  final List<TaskDependency> dependencies;
  final VoidCallback onAddDependency;
  final ValueChanged<int> onRemoveDependency;

  @override
  Widget build(BuildContext context) {
    // Cards (subtasks/dependencies) carry their own horizontal margin, so the
    // list itself is only padded vertically and the attribute sections get an
    // explicit horizontal inset to line up with the cards.
    const hPad = EdgeInsets.symmetric(horizontal: 16);
    return ListView(
      // Pad the bottom past the system gesture bar / home indicator so the last
      // row (dependencies) isn't tucked under it.
      padding: EdgeInsets.only(
        top: 16,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        // Editable attributes â€” tap to open the matching picker/editor.
        Padding(
          padding: hPad,
          child: _DetailSection(
            title: 'Attributes',
            children: [
              _DetailRow(
                icon: Icons.published_with_changes,
                label: 'Status',
                value: task.statusName,
                onTap: caps.canClose ? () => onEdit('status') : null,
              ),
              _DetailRow(
                icon: Icons.flag_outlined,
                label: 'Priority',
                value: task.priority?.name,
                placeholder: 'Set priority',
                onTap: caps.canEdit ? () => onEdit('priority') : null,
              ),
              _DetailRow(
                icon: Icons.apartment_outlined,
                label: 'Department',
                value: task.departmentName,
                placeholder: 'Transfer',
                onTap: caps.canTransfer ? () => onEdit('transfer') : null,
              ),
              _DetailRow(
                icon: Icons.assignment_ind_outlined,
                label: 'Assignee',
                value: task.assignee,
                placeholder: 'Assign',
                onTap: caps.canAssign ? () => onEdit('assign') : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Read-only metadata.
        Padding(
          padding: hPad,
          child: _DetailSection(
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
        ),
        if (task.customFields.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: hPad,
            child: _DetailSection(
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
          ),
        ],
        const SizedBox(height: 20),
        Padding(
          padding: hPad,
          child: _SectionHeader(
            title: 'Subtasks',
            // Adding a subtask hits POST /tasks/{id}/subtask → PERM_CREATE.
            actionLabel: caps.canCreate ? 'Add subtask' : null,
            onAction: caps.canCreate ? onAddSubtask : null,
          ),
        ),
        const SizedBox(height: 4),
        if (subtasks.isEmpty)
          const _EmptySection(message: 'No subtasks')
        else
          for (final st in subtasks)
            TaskCard(task: st, onTap: () => onSubtaskTap(st)),
        const SizedBox(height: 20),
        Padding(
          padding: hPad,
          child: _SectionHeader(
            title: 'Dependencies',
            // Managing dependencies hits /tasks/{id}/dependencies → PERM_EDIT.
            actionLabel: caps.canEdit ? 'Add dependency' : null,
            onAction: caps.canEdit ? onAddDependency : null,
          ),
        ),
        const SizedBox(height: 4),
        if (dependencies.isEmpty)
          const _EmptySection(message: 'No dependencies')
        else
          for (final dep in dependencies)
            _DependencyCard(
              dep: dep,
              onRemove:
                  caps.canEdit ? () => onRemoveDependency(dep.id) : null,
            ),
      ],
    );
  }
}

/// A section heading with an optional trailing "add" text button, matching the
/// uppercase caption style used by [_DetailSection].
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: AppText.custmText(
            context,
            title.toUpperCase(),
            fs: 10,
            color: scheme.onSurfaceVariant,
            fw: 2,
            letterSpacing: 0.5,
          ),
        ),
        const Spacer(),
        if (actionLabel != null)
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add, size: 18),
            label: Text(actionLabel!),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
      ],
    );
  }
}

/// A muted placeholder shown when a Details section (subtasks/dependencies) is
/// empty, inset to align with the cards.
class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: AppText.subText(
        context,
        message,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A single dependency row rendered as a card (extracted from the former
/// Dependencies tab so it can live inside the Details list).
class _DependencyCard extends StatelessWidget {
  const _DependencyCard({required this.dep, this.onRemove});
  final TaskDependency dep;

  /// Null when the agent lacks task.edit — the remove control is then hidden.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final blocker = dep.blocker;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
        trailing: onRemove == null
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Remove',
                onPressed: onRemove,
              ),
      ),
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

// --- Activity tab -----------------------------------------------------------

/// The task's event history (`GET /tasks/{id}/events`) as a vertical timeline —
/// status changes, assignments, transfers, notes, etc. Mirrors the ticket
/// Activity tab so both entities present history the same way.
class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.events});
  final List<ThreadEvent> events;

  /// (icon, colour) for an event, derived from its state slug.
  static (IconData, Color) _style(String state) {
    final s = state.toLowerCase();
    if (s.contains('close') || s.contains('resolved')) {
      return (Icons.check_circle_outline, AppTheme.closed);
    }
    if (s.contains('open') || s.contains('reopen')) {
      return (Icons.play_circle_outline, AppTheme.open);
    }
    if (s.contains('assign') || s.contains('claim') || s.contains('owner')) {
      return (Icons.person_outline, AppTheme.brand);
    }
    if (s.contains('transfer')) {
      return (Icons.swap_horiz, AppTheme.warning);
    }
    if (s.contains('overdue')) {
      return (Icons.warning_amber_rounded, AppTheme.overdue);
    }
    if (s.contains('note')) {
      return (Icons.sticky_note_2_outlined, AppTheme.brandLight);
    }
    if (s.contains('reply') || s.contains('message')) {
      return (Icons.reply, AppTheme.open);
    }
    return (Icons.fiber_manual_record, AppTheme.brand);
  }

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const EmptyView(message: 'No activity');
    final scheme = Theme.of(context).colorScheme;
    // Newest first: the API returns events oldest→newest (ordered by
    // timestamp), so reverse it — this keeps same-second events (e.g. "Created"
    // then "assigned") in the right relative order and puts "Created" last. A
    // timestamp sort can't, since same-second ties would shuffle.
    final ordered = events.reversed.toList();
    return SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: ordered.length,
        itemBuilder: (context, i) {
          final e = ordered[i];
          final (icon, color) = _style(e.state);
          final isLast = i == ordered.length - 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timeline rail: a coloured icon node with a connector below.
                Column(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 17, color: color),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: scheme.outlineVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 18, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText.subText(
                          context,
                          e.description ?? e.state,
                          fw: 1,
                          lineHeight: 1.3,
                        ),
                        const SizedBox(height: 2),
                        AppText.paraText(
                          context,
                          [
                            if ((e.actor ?? '').isNotEmpty) e.actor!,
                            Fmt.ago(e.created),
                          ].join(' · '),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
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

// --- Tags sheet -------------------------------------------------------------

/// Lists a task's tags and lets the agent add/remove them
/// (`GET/POST/DELETE /tasks/{id}/tags`). Mirrors the ticket Tags sheet.
class _TaskTagsSheet extends ConsumerStatefulWidget {
  const _TaskTagsSheet({required this.taskId});
  final int taskId;

  @override
  ConsumerState<_TaskTagsSheet> createState() => _TaskTagsSheetState();
}

class _TaskTagsSheetState extends ConsumerState<_TaskTagsSheet> {
  List<Tag> _tags = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await ref.read(tasksRepositoryProvider).tags(widget.taskId);
      if (mounted) {
        setState(() {
          _tags = t;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppSnack.error(context, e.message);
      }
    }
  }

  Future<void> _add() async {
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(MetaKind.tags);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => _MetaPickerDialog(title: 'Add tag', items: items),
    );
    if (chosen == null) return;
    setState(() => _busy = true);
    try {
      final t = await ref
          .read(tasksRepositoryProvider)
          .addTag(widget.taskId, tagId: chosen);
      if (mounted) setState(() => _tags = t);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(int tagId) async {
    setState(() => _busy = true);
    try {
      final t = await ref
          .read(tasksRepositoryProvider)
          .removeTag(widget.taskId, tagId);
      if (mounted) setState(() => _tags = t);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Tags',
      actionLabel: 'Add tag',
      onAction: _busy ? null : _add,
      actionEnabled: !_busy,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : _tags.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AppText.subText(context, 'No tags'),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _tags)
                  Chip(
                    label: Text(t.name),
                    onDeleted: _busy ? null : () => _remove(t.id),
                  ),
              ],
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
