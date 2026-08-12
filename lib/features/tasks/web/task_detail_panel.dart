import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/assets.dart';
import '../../../core/format.dart';
import '../../../models/common.dart';
import '../../../models/me.dart';
import '../../../models/meta.dart';
import '../../../models/task.dart';
import '../../../providers.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/comment_composer.dart';
import '../../../widgets/states.dart';
import '../../../widgets/web/detail_fields.dart';
import '../../../widgets/web/panel_header.dart';
import '../../../widgets/web/status_badge.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';
import '../../../widgets/web/thread_view.dart';
import '../../../widgets/web/zebu_dialog.dart';
import 'task_relations.dart';

/// Web-only task-detail slide-over panel — visual parity with
/// [TicketDetailPanel]:
///   - single-row header carrying a `#{number}` chip + title on the left
///     and Actions + Fullscreen + Close on the right;
///   - fields expressed as a left-labeled table inside one rounded card;
///   - thread rows as individual cards with actor-avatar column.
///

/// Panel-body width at (or above) which the panel switches to a two-column
/// layout: activity feed on the left, fields sidebar on the right. Below
/// this breakpoint the body falls back to the vertically stacked layout so
/// narrow panels + phone-sized viewports stay legible.
const double _kTwoColumnBreakpoint = 780;

/// Fixed width of the right-hand fields sidebar in two-column mode. Wide
/// enough to fit the `[icon][label 88][value ...]` row without truncation
/// on the longer field values, tight enough that the activity column keeps
/// the majority of the panel.
const double _kFieldsSidebarWidth = 320;

/// Per-agent action gates for a task, ported from osTicket's
/// `Task::checkStaffPerm()` (`include/class.task.php`). The backend enforces
/// these on every mutating `/tasks/*` endpoint (403 otherwise); mirroring them
/// here hides/disables the affordances an agent can't use — matching the SCP
/// rule that a task "cannot be edited by others". Visibility is already granted
/// (the detail loaded), so only the per-department role permission matters.
class _TaskCaps {
  const _TaskCaps({
    this.canEdit = false,
    this.canAssign = false,
    this.canTransfer = false,
    this.canClose = false,
    this.canReply = false,
  });

  final bool canEdit; // task.edit — priority + field edits
  final bool canAssign; // task.assign
  final bool canTransfer; // task.transfer — department change
  final bool canClose; // task.close — close / reopen / status
  final bool canReply; // task.reply — reply + internal note

  /// True when at least one header (Actions dropdown) action is available.
  bool get hasHeaderAction => canClose || canEdit || canAssign || canTransfer;

  factory _TaskCaps.from(Me? me, Task? task) {
    if (me == null || task == null) return const _TaskCaps();
    final d = task.departmentId;
    return _TaskCaps(
      canEdit: me.canOn('task.edit', d),
      canAssign: me.canOn('task.assign', d),
      canTransfer: me.canOn('task.transfer', d),
      canClose: me.canOn('task.close', d),
      canReply: me.canOn('task.reply', d),
    );
  }
}

class TaskDetailPanel extends ConsumerStatefulWidget {
  const TaskDetailPanel({
    super.key,
    required this.taskId,
    required this.onClose,
    this.initialTask,
    this.onOpenTask,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    this.onChanged,
  });
  final int taskId;
  final VoidCallback onClose;

  /// The list row's summary of this task, when the host has one.
  ///
  /// Purely a first-paint optimisation: the panel still fetches the full
  /// task, but with this the header can show the number and title
  /// immediately rather than the word "Loading…". Every field it carries is
  /// replaced the moment the real fetch lands.
  final Task? initialTask;

  /// Asks the host to swap the panel to another task — used by the subtask
  /// and dependency rows. Null makes those rows inert.
  final ValueChanged<int>? onOpenTask;

  /// See [TicketDetailPanel.isFullscreen].
  final bool isFullscreen;

  /// See [TicketDetailPanel.onToggleFullscreen].
  final VoidCallback? onToggleFullscreen;

  /// Fires after a successful mutation (status flip, assign, transfer,
  /// priority, reply/note). Hosts refresh the list underneath so the row
  /// reflects the new value instead of the stale cached one.
  final VoidCallback? onChanged;

  @override
  ConsumerState<TaskDetailPanel> createState() => _TaskDetailPanelState();
}

class _TaskDetailPanelState extends ConsumerState<TaskDetailPanel> {
  Task? _task;

  /// Whether the right-hand details pane is collapsed. Panel state, not
  /// persisted: an agent who collapses it for one wide task usually wants it
  /// back on the next one.
  bool _detailsCollapsed = false;
  List<ThreadEntry> _thread = const [];
  List<Task> _subtasks = const [];
  List<TaskDependency> _dependencies = const [];
  Object? _error;
  bool _loading = true;
  bool _acting = false;

  final GlobalKey _statusRowKey = GlobalKey(debugLabel: 'task-status-row');
  final GlobalKey _priorityRowKey = GlobalKey(debugLabel: 'task-priority-row');
  final GlobalKey _assigneeRowKey = GlobalKey(debugLabel: 'task-assignee-row');
  final GlobalKey _departmentRowKey = GlobalKey(
    debugLabel: 'task-department-row',
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      // Seed from the row's summary so the header has something to draw on
      // the first frame. Null on hosts that don't pass one, which behave
      // exactly as before.
      _task ??= widget.initialTask;
      _loading = true;
      _error = null;
    });
    final repo = ref.read(tasksRepositoryProvider);
    try {
      // Relations are fetched in parallel with the thread — they are two
      // more round trips, and serialising them would double the time the
      // panel spends on its loader for data that sits below the fold.
      final task = await repo.get(widget.taskId);
      final thread = repo.thread(widget.taskId, limit: 50);
      // A task with no subtasks / dependencies 404s on some installs rather
      // than returning an empty list, so neither is allowed to fail the load.
      final subtasks = repo.subtasks(widget.taskId).catchError((_) => <Task>[]);
      final deps = repo
          .dependencies(widget.taskId)
          .catchError((_) => <TaskDependency>[]);
      final entries = await thread;
      final subs = await subtasks;
      final dependencies = await deps;
      if (!mounted) return;
      setState(() {
        _task = task;
        _thread = entries.items;
        _subtasks = subs;
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

  void _toast(String msg, {ToastType type = ToastType.info}) =>
      AppToast.show(context, msg, type: type);

  Future<void> _runAction(
    Future<Task> Function() action, {
    String? success,
  }) async {
    setState(() => _acting = true);
    try {
      final updated = await action();
      setState(() => _task = updated);
      widget.onChanged?.call();
      if (success != null) _toast(success, type: ToastType.success);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _onMenu(String value) async {
    final repo = ref.read(tasksRepositoryProvider);
    switch (value) {
      case 'close':
        await _runAction(
          () => repo.close(widget.taskId),
          success: 'Task closed',
        );
      case 'reopen':
        await _runAction(
          () => repo.reopen(widget.taskId),
          success: 'Task reopened',
        );
      case 'status':
        final ctx = _statusRowKey.currentContext;
        if (ctx != null) await _pickTaskStatus(ctx);
        return;
      case 'assign':
        final ctx = _assigneeRowKey.currentContext;
        if (ctx != null) await _pickTaskAssignee(ctx);
        return;
      case 'transfer':
        final ctx = _departmentRowKey.currentContext;
        if (ctx != null) await _pickTaskDepartment(ctx);
        return;
      case 'priority':
        final ctx = _priorityRowKey.currentContext;
        if (ctx != null) await _pickTaskPriority(ctx);
        return;
    }
    await _refreshThread();
  }

  /// Swaps the panel over to a related task without closing it. Cheaper than
  /// routing — the host's slide-over stays mounted, so there is no open /
  /// close animation between two tasks the agent is comparing.
  void _openRelated(int id) {
    if (id == widget.taskId) return;
    widget.onOpenTask?.call(id);
  }

  Future<void> _addSubtask() async {
    final task = _task;
    if (task == null) return;
    // The dialog owns the create so it can stay open on failure — and so
    // "Create another" can fire it repeatedly without reopening.
    final created = await showZebuDialog<bool>(
      context,
      barrierLabel: 'Add subtask',
      child: TaskSubtaskDialog(
        taskNumber: task.number,
        taskTitle: task.title,
        onCreate: (draft) =>
            ref.read(tasksRepositoryProvider).createSubtask(widget.taskId, {
              'title': draft.title,
              if (draft.description != null) 'description': draft.description,
            }),
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _addDependency() async {
    final task = _task;
    if (task == null) return;
    final id = await showZebuDialog<int>(
      context,
      barrierLabel: 'Add dependency',
      child: TaskDependencyDialog(
        taskNumber: task.number,
        taskTitle: task.title,
      ),
    );
    if (id == null) return;
    setState(() => _acting = true);
    try {
      final deps = await ref
          .read(tasksRepositoryProvider)
          .addDependency(widget.taskId, id);
      if (mounted) setState(() => _dependencies = deps);
      widget.onChanged?.call();
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _removeDependency(TaskDependency dep) async {
    setState(() => _acting = true);
    try {
      final deps = await ref
          .read(tasksRepositoryProvider)
          .removeDependency(widget.taskId, dep.id);
      if (mounted) setState(() => _dependencies = deps);
      widget.onChanged?.call();
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _refreshThread() async {
    try {
      final thread = await ref
          .read(tasksRepositoryProvider)
          .thread(widget.taskId, limit: 50);
      if (!mounted) return;
      setState(() => _thread = thread.items);
    } catch (_) {
      // Non-fatal — the thread will refresh on the next explicit reload.
    }
  }

  Future<void> _reloadSilent() async {
    final repo = ref.read(tasksRepositoryProvider);
    try {
      final taskFuture = repo.get(widget.taskId);
      final threadFuture = repo.thread(widget.taskId, limit: 50);
      final task = await taskFuture;
      final thread = await threadFuture;
      if (!mounted) return;
      setState(() {
        _task = task;
        _thread = thread.items;
      });
    } catch (_) {
      // Non-fatal — the next explicit action or reload will re-sync.
    }
  }

  Future<void> _pickMetaMenu(
    BuildContext anchorContext,
    String kind,
    Future<void> Function(int id) onPick, {
    String? header,
    String? currentName,
  }) async {
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(kind);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
      return;
    }
    if (!mounted || !anchorContext.mounted) return;
    final current = currentName?.trim().toLowerCase();
    final chosen = await showAppDropdown<int>(
      anchorContext,
      entries: [
        if (header != null) AppDropdownHeader<int>(header),
        for (final m in items)
          AppDropdownItem<int>(
            value: m.id,
            label: m.name,
            selected:
                current != null &&
                current.isNotEmpty &&
                m.name.trim().toLowerCase() == current,
          ),
      ],
    );
    if (chosen != null) await onPick(chosen);
  }

  /// Tasks only support Open ↔ Completed — surface a single verb that
  /// reflects the flip direction so the row reads as a decision, not a
  /// status list.
  Future<void> _pickTaskStatus(BuildContext anchorContext) async {
    final task = _task;
    if (task == null) return;
    final entries = <AppDropdownEntry<String>>[
      const AppDropdownHeader<String>('Status'),
      if (task.isOpen)
        const AppDropdownItem<String>(
          value: 'close',
          label: 'Close task',
          icon: Icons.check_circle_outline,
        )
      else
        const AppDropdownItem<String>(
          value: 'reopen',
          label: 'Reopen task',
          icon: Icons.replay,
        ),
    ];
    final picked = await showAppDropdown<String>(
      anchorContext,
      entries: entries,
    );
    if (picked != null) await _onMenu(picked);
  }

  Future<void> _pickTaskPriority(BuildContext anchorContext) async {
    final repo = ref.read(tasksRepositoryProvider);
    await _pickMetaMenu(
      anchorContext,
      MetaKind.taskPriorities,
      (id) async {
        await _runAction(
          () => repo.edit(widget.taskId, priorityId: id),
          success: 'Priority updated',
        );
        await _refreshThread();
      },
      header: 'Priority',
      currentName: _task?.priority?.name,
    );
  }

  Future<void> _pickTaskAssignee(BuildContext anchorContext) async {
    final repo = ref.read(tasksRepositoryProvider);
    await _pickMetaMenu(
      anchorContext,
      MetaKind.agents,
      (id) async {
        await _runAction(
          () => repo.assign(widget.taskId, staffId: id),
          success: 'Assigned',
        );
        await _refreshThread();
      },
      header: 'Assignee',
      currentName: _task?.assignee,
    );
  }

  Future<void> _pickTaskDepartment(BuildContext anchorContext) async {
    final repo = ref.read(tasksRepositoryProvider);
    await _pickMetaMenu(
      anchorContext,
      MetaKind.departments,
      (id) async {
        await _runAction(
          () => repo.transfer(widget.taskId, id),
          success: 'Transferred',
        );
        await _refreshThread();
      },
      header: 'Department',
      currentName: _task?.departmentName,
    );
  }

  Future<bool> _sendReply({
    required bool asNote,
    required String bodyHtml,
    required List<MultipartFile> files,
  }) async {
    if (bodyHtml.trim().isEmpty && files.isEmpty) return false;
    setState(() => _acting = true);
    final repo = ref.read(tasksRepositoryProvider);
    try {
      if (asNote) {
        await repo.note(widget.taskId, body: bodyHtml, files: files);
      } else {
        await repo.reply(
          widget.taskId,
          body: bodyHtml,
          alert: true,
          files: files,
        );
      }
      _toast(asNote ? 'Note added' : 'Reply sent', type: ToastType.success);
      widget.onChanged?.call();
      await _reloadSilent();
      return true;
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
      return false;
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Material(
      // Warm-paper ground so the panel matches the list surface behind it.
      // Cards (thread rows, header, activity strip) keep `bgElevated` so
      // they read as elevated on the paper — same layering as the list.
      color: t.bgPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: _buildBody(t),
    );
  }

  Widget _buildBody(ZebuTheme t) {
    if (_loading) {
      return Column(
        children: [
          _Header(
            // The seeded summary when we have one — the identity of the task
            // is not in doubt while its body loads.
            task: _task,
            onClose: widget.onClose,
            onMenu: null,
            isFullscreen: widget.isFullscreen,
            onToggleFullscreen: widget.onToggleFullscreen,
          ),
          const Expanded(child: LoadingView()),
        ],
      );
    }
    if (_error != null || _task == null) {
      return Column(
        children: [
          _Header(
            task: null,
            onClose: widget.onClose,
            onMenu: null,
            isFullscreen: widget.isFullscreen,
            onToggleFullscreen: widget.onToggleFullscreen,
          ),
          Expanded(
            child: ErrorView(error: _error ?? 'Not found', onRetry: _load),
          ),
        ],
      );
    }
    final task = _task!;
    // Per-agent action gates (ported from Task::checkStaffPerm). `me` is loaded
    // app-wide at startup, so valueOrNull is populated by the time this opens;
    // until then caps default to none (safe — the backend would 403 anyway).
    final me = ref.watch(meProvider).asData?.value;
    final caps = _TaskCaps.from(me, task);
    return Column(
      children: [
        _Header(
          task: task,
          caps: caps,
          onClose: widget.onClose,
          onMenu: _onMenu,
          isFullscreen: widget.isFullscreen,
          onToggleFullscreen: widget.onToggleFullscreen,
        ),
        if (_acting) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _kTwoColumnBreakpoint;
              if (wide) return _buildWide(t, task, caps);
              return _buildNarrow(t, task, caps);
            },
          ),
        ),
        // Reply and internal note both require task.reply on the backend, so a
        // single canReply gate covers the whole composer.
        CommentComposer(
          onSend: _sendReply,
          disabled: _acting || !caps.canReply,
        ),
      ],
    );
  }

  /// Narrow single-column layout: fields card on top, activity feed below,
  /// composer at the bottom. Same layout the panel shipped with before the
  /// two-column split, kept for the sub-780 px slot the panel gets when the
  /// list underneath is still visible on smaller viewports.
  Widget _buildNarrow(ZebuTheme t, Task task, _TaskCaps caps) {
    return SelectionArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: ZebuSpacing.s3),
          _FieldsTable(
            task: task,
            sidebar: false,
            statusRowKey: _statusRowKey,
            priorityRowKey: _priorityRowKey,
            assigneeRowKey: _assigneeRowKey,
            departmentRowKey: _departmentRowKey,
            onStatusTap: caps.canClose ? _pickTaskStatus : null,
            onPriorityTap: caps.canEdit ? _pickTaskPriority : null,
            onAssigneeTap: caps.canAssign ? _pickTaskAssignee : null,
            onDepartmentTap: caps.canTransfer ? _pickTaskDepartment : null,
          ),
          const SizedBox(height: ZebuSpacing.s2),
          const _ActivityHeader(),
          if (_thread.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: ZebuSpacing.s6),
              child: Center(
                child: Text(
                  'No messages yet',
                  style: ZebuTextStyles.small(context),
                ),
              ),
            )
          else ...[
            ...zebuThreadItems(_thread),
            const SizedBox(height: ZebuSpacing.s3),
          ],
        ],
      ),
    );
  }

  /// Two-column layout used at ≥ [_kTwoColumnBreakpoint] px: activity feed
  /// on the left (grows to fill), fields sidebar on the right at
  /// [_kFieldsSidebarWidth]. A hairline seam separates the two columns —
  /// matches the reference layout where the details block sits as a fixed
  /// rail alongside the message thread.
  Widget _buildWide(ZebuTheme t, Task task, _TaskCaps caps) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SelectionArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (_thread.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: ZebuSpacing.s8,
                    ),
                    child: Center(
                      child: Text(
                        'No messages yet',
                        style: ZebuTextStyles.body(context),
                      ),
                    ),
                  )
                else ...[
                  const SizedBox(height: ZebuSpacing.s3),
                  ...zebuThreadItems(_thread),
                  const SizedBox(height: ZebuSpacing.s3),
                ],
              ],
            ),
          ),
        ),
        if (!_detailsCollapsed)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: t.borderSubtle, width: 1)),
            ),
            child: SizedBox(
              width: _kFieldsSidebarWidth,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: ZebuSpacing.s4),
                children: [
                  _FieldsTable(
                    task: task,
                    sidebar: true,
                    statusRowKey: _statusRowKey,
                    priorityRowKey: _priorityRowKey,
                    assigneeRowKey: _assigneeRowKey,
                    departmentRowKey: _departmentRowKey,
                    onStatusTap: caps.canClose ? _pickTaskStatus : null,
                    onPriorityTap: caps.canEdit ? _pickTaskPriority : null,
                    onAssigneeTap: caps.canAssign ? _pickTaskAssignee : null,
                    onDepartmentTap: caps.canTransfer
                        ? _pickTaskDepartment
                        : null,
                    onCollapse: () => setState(() => _detailsCollapsed = true),
                  ),
                  // Relations sit under the fields, not above the thread: a
                  // subtask list is metadata about this task, the same kind
                  // of thing as its assignee or its due date.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ZebuSpacing.s4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TaskSubtasksSection(
                          subtasks: _subtasks,
                          onAdd: caps.canEdit && !_acting ? _addSubtask : null,
                          onOpen: (sub) => _openRelated(sub.id),
                        ),
                        TaskDependenciesSection(
                          dependencies: _dependencies,
                          onAdd: caps.canEdit && !_acting
                              ? _addDependency
                              : null,
                          onRemove: caps.canEdit && !_acting
                              ? _removeDependency
                              : null,
                          onOpen: (dep) {
                            final id = dep.blocker?.id;
                            if (id != null) _openRelated(id);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (!_detailsCollapsed) return row;

    // Collapsed, the pane is gone entirely and only its toggle remains,
    // floated in the corner it vanished from. A persistent rail was cheaper
    // to build but spent 44 px of a column agents read long quoted email in.
    return Stack(
      children: [
        row,
        Positioned(
          top: ZebuSpacing.s3,
          right: ZebuSpacing.s3,
          child: ZebuRailToggle(
            icon: Icons.keyboard_double_arrow_left_rounded,
            tooltip: 'Show details',
            onTap: () => setState(() => _detailsCollapsed = false),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// The Actions menu for a task — same gating rule as the ticket panel's:
/// every entry mirrors the permission its `/tasks` endpoint enforces.
List<AppDropdownEntry<String>> _taskActions(Task task, _TaskCaps caps) {
  return [
    const AppDropdownHeader<String>('Task actions'),
    if (caps.canClose)
      if (task.isOpen)
        const AppDropdownItem(
          value: 'close',
          label: 'Close task',
          svgAsset: Assets.actClose,
        )
      else
        const AppDropdownItem(
          value: 'reopen',
          label: 'Reopen task',
          svgAsset: Assets.actReopen,
        ),
    if (caps.canEdit)
      const AppDropdownItem(
        value: 'priority',
        label: 'Set priority',
        svgAsset: Assets.actPriority,
      ),
    if (caps.canAssign)
      const AppDropdownItem(
        value: 'assign',
        label: 'Assign',
        svgAsset: Assets.actAssign,
      ),
    if (caps.canTransfer)
      const AppDropdownItem(
        value: 'transfer',
        label: 'Transfer dept',
        svgAsset: Assets.actTransfer,
      ),
  ];
}

class _Header extends StatelessWidget {
  const _Header({
    required this.task,
    this.caps = const _TaskCaps(),
    required this.onClose,
    required this.onMenu,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });
  final Task? task;
  final _TaskCaps caps;
  final VoidCallback onClose;
  final Future<void> Function(String value)? onMenu;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s4,
        ZebuSpacing.s3,
        ZebuSpacing.s4,
        ZebuSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (task == null)
            const Expanded(child: ZebuPanelTitleSkeleton())
          else
            Expanded(
              child: ZebuPanelTitle(
                id: task!.number,
                title: task!.title,
                meta: task!.assignee,
              ),
            ),
          const SizedBox(width: ZebuSpacing.s3),
          if (task != null && onMenu != null && caps.hasHeaderAction) ...[
            ZebuPanelActionsBtn(
              onSelected: onMenu!,
              entries: _taskActions(task!, caps),
            ),
            const SizedBox(width: ZebuSpacing.s2),
          ],
          if (onToggleFullscreen != null) ...[
            ZebuPanelIconBtn(
              icon: isFullscreen ? Icons.close_fullscreen : Icons.open_in_full,
              tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
              onTap: onToggleFullscreen!,
            ),
            const SizedBox(width: ZebuSpacing.s2),
          ],
          // Not destructive — a red hover belongs to actions that lose
          // something. Dismissing the panel discards nothing.
          ZebuPanelIconBtn(icon: Icons.close, tooltip: 'Close', onTap: onClose),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fields table
// ---------------------------------------------------------------------------

class _FieldsTable extends StatelessWidget {
  const _FieldsTable({
    required this.task,
    required this.sidebar,
    required this.statusRowKey,
    required this.priorityRowKey,
    required this.assigneeRowKey,
    required this.departmentRowKey,
    required this.onStatusTap,
    required this.onPriorityTap,
    required this.onAssigneeTap,
    required this.onDepartmentTap,
    this.onCollapse,
  });
  final Task task;

  /// True when this table is rendered inside the wide-mode right rail —
  /// drops the outer rounded card + horizontal padding so the rows sit
  /// flush inside the sidebar. The sidebar's own left border acts as the
  /// separator instead.
  final bool sidebar;

  final GlobalKey statusRowKey;
  final GlobalKey priorityRowKey;
  final GlobalKey assigneeRowKey;
  final GlobalKey departmentRowKey;

  /// Null when the current agent lacks the permission for that field — the
  /// row then renders as static text (no chevron, no tap), mirroring the
  /// backend's per-action checkStaffPerm gate.
  final ValueChanged<BuildContext>? onStatusTap;
  final ValueChanged<BuildContext>? onPriorityTap;
  final ValueChanged<BuildContext>? onAssigneeTap;
  final ValueChanged<BuildContext>? onDepartmentTap;

  /// Collapses the pane. Null in the stacked (narrow) layout, where there is
  /// no sidebar to collapse.
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final priorityName = task.priority?.name.trim() ?? '';
    final assignee = (task.assignee ?? '').trim();
    final department = (task.departmentName ?? '').trim();

    // Grouped exactly like the ticket sidebar: a flat run of eight rows gave
    // an agent nothing to aim at, and the four groups are the four questions
    // actually asked of a task — who owns it, what state is it in, when is it
    // due, where did it come from.
    final cells = <Widget>[
      if (sidebar) const ZebuFieldGroupLabel('Assignment', first: true),
      ZebuFieldRow(
        rowKey: assigneeRowKey,
        icon: Icons.person_outline,
        label: 'Assignee',
        sidebar: sidebar,
        onTap: onAssigneeTap,
        value: assignee.isEmpty
            ? const ZebuEmptyValue(label: 'Unassigned')
            : ZebuTextValue(text: assignee, tone: t.accent, linked: true),
      ),
      ZebuFieldRow(
        rowKey: departmentRowKey,
        icon: Icons.business_outlined,
        label: 'Department',
        sidebar: sidebar,
        onTap: onDepartmentTap,
        value: department.isEmpty
            ? const ZebuEmptyValue(label: 'None')
            : ZebuTextValue(text: department, tone: t.accent, linked: true),
      ),
      if (sidebar) const ZebuFieldGroupLabel('Task'),
      ZebuFieldRow(
        rowKey: statusRowKey,
        icon: Icons.flag_outlined,
        label: 'Status',
        sidebar: sidebar,
        onTap: onStatusTap,
        // The badge, not a tinted pill: status comes from a fixed vocabulary
        // with a designed fill weight per value. Overdue is deliberately not
        // passed — this panel has its own Due row reporting the breach, and
        // letting it repaint Status too said the same thing twice.
        value: Align(
          alignment: Alignment.centerLeft,
          child: StatusBadge(
            label: _titleCase(task.statusName),
            status: task.statusName,
            dense: true,
          ),
        ),
      ),
      ZebuFieldRow(
        rowKey: priorityRowKey,
        icon: Icons.priority_high,
        label: 'Priority',
        sidebar: sidebar,
        onTap: onPriorityTap,
        value: priorityName.isEmpty
            ? const ZebuEmptyValue(label: 'No priority')
            : Align(
                alignment: Alignment.centerLeft,
                child: PriorityBadge(
                  label: _titleCase(priorityName),
                  priority: priorityName,
                  dense: true,
                ),
              ),
      ),
      if (task.blocked)
        ZebuFieldRow(
          icon: Icons.block,
          label: 'Blocked',
          sidebar: sidebar,
          value: ZebuTextValue(text: 'Blocked by dependency', tone: t.danger),
        ),
      if (task.progress > 0)
        ZebuFieldRow(
          icon: Icons.donut_small_outlined,
          label: 'Progress',
          sidebar: sidebar,
          value: ZebuTextValue(text: '${task.progress}%'),
        ),
      if (sidebar) const ZebuFieldGroupLabel('Schedule'),
      if (task.duedate != null)
        ZebuFieldRow(
          icon: Icons.schedule,
          label: 'Due',
          sidebar: sidebar,
          value: ZebuTextValue(
            text: Fmt.dateTime(task.duedate),
            tone: task.overdue ? t.danger : null,
          ),
        ),
      ZebuFieldRow(
        icon: Icons.event_outlined,
        label: 'Created',
        sidebar: sidebar,
        value: ZebuTextValue(text: Fmt.dateTime(task.created)),
      ),
    ];

    // Sidebar mode: wrap the field rows in a single elevated card so every
    // row (clickable or not) sits on the same white ground against the
    // panel's warm-paper bg. The card's subtle shadow lifts the rail off
    // the page. [DefaultTextStyle] pins the ambient base to `bodyBase` so
    // descendant [ZebuTextValue] runs inherit the sidebar's 14 px size —
    // fields rail reads one size-step above the messages column, matching
    // TicketDetailPanel.
    if (sidebar) {
      // No card in the sidebar: the pane's own left border already separates
      // it from the thread, so a bordered box inside a bordered pane was two
      // frames around one list.
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          ZebuSpacing.s4,
          0,
          ZebuSpacing.s4,
          ZebuSpacing.s3,
        ),
        child: DefaultTextStyle.merge(
          style: ZebuTextStyles.body(context).copyWith(color: t.textPrimary),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: ZebuSpacing.s2,
                  bottom: ZebuSpacing.s3,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Task Details',
                        style: ZebuTextStyles.sectionTitle(
                          context,
                          color: t.textSlate,
                        ),
                      ),
                    ),
                    if (onCollapse != null)
                      ZebuRailToggle(
                        icon: Icons.keyboard_double_arrow_right_rounded,
                        tooltip: 'Hide details',
                        onTap: onCollapse!,
                      ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: t.dividerSlate),
              const SizedBox(height: ZebuSpacing.s4),
              ...cells,
            ],
          ),
        ),
      );
    }
    // Narrow single-column: wraps the fields in an email-style card so the
    // metadata block reads as one contained module (rounded hairline border
    // + `bgElevated` fill). Without the fill the card blended into the page
    // bg in dark mode — the border alone wasn't enough separation. The
    // `DefaultTextStyle.merge` pins the ambient base to `bodySm` so the row
    // value text matches the tighter single-column rhythm.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(ZebuRadius.rMd),
          border: Border.all(color: t.borderSubtle, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s3,
            vertical: ZebuSpacing.s2,
          ),
          child: DefaultTextStyle.merge(
            style: ZebuTextStyles.small(context).copyWith(color: t.textPrimary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: cells,
            ),
          ),
        ),
      ),
    );
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}

// ---------------------------------------------------------------------------
// Activity subheader
// ---------------------------------------------------------------------------

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader();

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s4,
        vertical: ZebuSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(top: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: Text(
        'Activity',
        style: ZebuTextStyles.smallStrong(
          context,
        ).copyWith(color: t.textPrimary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thread row — Asana-style comment stream entry: actor avatar + name + muted
// timestamp on one line, body below, a hairline between entries. Internal
// notes keep a subtle warning tint + "Internal note" label so staff-only
// entries stay distinct from public replies (no boxed cards, no MESSAGE/REPLY
// tags).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Attachment chip
// ---------------------------------------------------------------------------
