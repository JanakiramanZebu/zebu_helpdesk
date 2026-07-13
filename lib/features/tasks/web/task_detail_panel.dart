import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format.dart';
import '../../../models/common.dart';
import '../../../models/meta.dart';
import '../../../models/task.dart';
import '../../../providers.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/comment_composer.dart';
import '../../../widgets/states.dart';
import '../../../widgets/web/status_pill.dart';
import '../../dashboard/web/_tokens.dart';

/// Web-only task-detail slide-over panel — visual parity with
/// [TicketDetailPanel]:
///   - single-row header carrying a `#{number}` chip + title on the left
///     and Actions + Fullscreen + Close on the right;
///   - fields expressed as a left-labeled table inside one rounded card;
///   - thread rows as individual cards with actor-avatar column.
///
/// Data comes from [tasksRepositoryProvider] — same source the mobile
/// detail screen uses.
const _kFlatRadius = 8.0;
const double _kFieldLabelWidth = 88;
const double _kFieldValueWidth = 280;
const double _kSidebarRowHeight = 40;
const double _kAvatarSize = 32;

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

class TaskDetailPanel extends ConsumerStatefulWidget {
  const TaskDetailPanel({
    super.key,
    required this.taskId,
    required this.onClose,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    this.onChanged,
  });
  final int taskId;
  final VoidCallback onClose;

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
  List<ThreadEntry> _thread = const [];
  Object? _error;
  bool _loading = true;
  bool _acting = false;

  final GlobalKey _statusRowKey = GlobalKey(debugLabel: 'task-status-row');
  final GlobalKey _priorityRowKey =
      GlobalKey(debugLabel: 'task-priority-row');
  final GlobalKey _assigneeRowKey =
      GlobalKey(debugLabel: 'task-assignee-row');
  final GlobalKey _departmentRowKey =
      GlobalKey(debugLabel: 'task-department-row');

  @override
  void initState() {
    super.initState();
    _load();
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
      if (!mounted) return;
      setState(() {
        _task = task;
        _thread = thread.items;
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
            selected: current != null &&
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
    final t = WebTokens.of(context);
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

  Widget _buildBody(WebTokens t) {
    if (_loading) {
      return Column(
        children: [
          _Header(
            task: null,
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
    return Column(
      children: [
        _Header(
          task: task,
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
              if (wide) return _buildWide(t, task);
              return _buildNarrow(t, task);
            },
          ),
        ),
        CommentComposer(onSend: _sendReply, disabled: _acting),
      ],
    );
  }

  /// Narrow single-column layout: fields card on top, activity feed below,
  /// composer at the bottom. Same layout the panel shipped with before the
  /// two-column split, kept for the sub-780 px slot the panel gets when the
  /// list underneath is still visible on smaller viewports.
  Widget _buildNarrow(WebTokens t, Task task) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: WebTokens.s3),
        _FieldsTable(
          task: task,
          sidebar: false,
          statusRowKey: _statusRowKey,
          priorityRowKey: _priorityRowKey,
          assigneeRowKey: _assigneeRowKey,
          departmentRowKey: _departmentRowKey,
          onStatusTap: _pickTaskStatus,
          onPriorityTap: _pickTaskPriority,
          onAssigneeTap: _pickTaskAssignee,
          onDepartmentTap: _pickTaskDepartment,
        ),
        const SizedBox(height: WebTokens.s2),
        const _ActivityHeader(),
        if (_thread.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WebTokens.s6),
            child: Center(
              child: Text('No messages yet', style: t.bodySm),
            ),
          )
        else ...[
          for (final e in _thread) _ThreadRow(entry: e),
          const SizedBox(height: WebTokens.s3),
        ],
      ],
    );
  }

  /// Two-column layout used at ≥ [_kTwoColumnBreakpoint] px: activity feed
  /// on the left (grows to fill), fields sidebar on the right at
  /// [_kFieldsSidebarWidth]. A hairline seam separates the two columns —
  /// matches the reference layout where the details block sits as a fixed
  /// rail alongside the message thread.
  Widget _buildWide(WebTokens t, Task task) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (_thread.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: WebTokens.s8),
                  child: Center(
                    child: Text('No messages yet', style: t.bodySm),
                  ),
                )
              else ...[
                const SizedBox(height: WebTokens.s3),
                for (final e in _thread) _ThreadRow(entry: e),
                const SizedBox(height: WebTokens.s3),
              ],
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: t.borderSubtle, width: 1),
            ),
          ),
          child: SizedBox(
            width: _kFieldsSidebarWidth,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: WebTokens.s4),
              children: [
                _FieldsTable(
                  task: task,
                  sidebar: true,
                  statusRowKey: _statusRowKey,
                  priorityRowKey: _priorityRowKey,
                  assigneeRowKey: _assigneeRowKey,
                  departmentRowKey: _departmentRowKey,
                  onStatusTap: _pickTaskStatus,
                  onPriorityTap: _pickTaskPriority,
                  onAssigneeTap: _pickTaskAssignee,
                  onDepartmentTap: _pickTaskDepartment,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.task,
    required this.onClose,
    required this.onMenu,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });
  final Task? task;
  final VoidCallback onClose;
  final Future<void> Function(String value)? onMenu;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        WebTokens.s4,
        WebTokens.s3,
        WebTokens.s4,
        WebTokens.s3,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(
          bottom: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (task == null)
            Expanded(child: Text('Loading…', style: t.cardName))
          else ...[
            _NumberChip(number: task!.number),
            const SizedBox(width: WebTokens.s3),
            Expanded(
              child: Text(
                task!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.pageTitle,
              ),
            ),
          ],
          const SizedBox(width: WebTokens.s3),
          if (task != null && onMenu != null) ...[
            _ActionsBtn(task: task!, onSelected: onMenu!),
            const SizedBox(width: WebTokens.s2),
          ],
          if (onToggleFullscreen != null) ...[
            _IconBtn(
              icon: isFullscreen
                  ? Icons.close_fullscreen
                  : Icons.open_in_full,
              tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
              onTap: onToggleFullscreen!,
            ),
            const SizedBox(width: WebTokens.s2),
          ],
          _IconBtn(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            destructive: true,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class _NumberChip extends StatelessWidget {
  const _NumberChip({required this.number});
  final String number;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.bgTertiary,
        borderRadius: BorderRadius.circular(WebTokens.s1),
      ),
      child: Text(
        '#$number',
        style: t.bodySm
            .copyWith(
              fontWeight: FontWeight.w600,
              color: t.textPrimary,
            )
            .withTabularNums(),
      ),
    );
  }
}

class _ActionsBtn extends StatefulWidget {
  const _ActionsBtn({required this.task, required this.onSelected});
  final Task task;
  final Future<void> Function(String value) onSelected;

  @override
  State<_ActionsBtn> createState() => _ActionsBtnState();
}

class _ActionsBtnState extends State<_ActionsBtn> {
  bool _hover = false;

  Future<void> _open() async {
    final task = widget.task;
    final chosen = await showAppDropdown<String>(
      context,
      entries: [
        const AppDropdownHeader<String>('Task actions'),
        if (task.isOpen)
          const AppDropdownItem(
            value: 'close',
            label: 'Close task',
            icon: Icons.check_circle_outline,
          )
        else
          const AppDropdownItem(
            value: 'reopen',
            label: 'Reopen task',
            icon: Icons.replay,
          ),
        const AppDropdownItem(
          value: 'priority',
          label: 'Set priority',
          icon: Icons.priority_high,
        ),
        const AppDropdownItem(
          value: 'assign',
          label: 'Assign',
          icon: Icons.person_add_alt_outlined,
        ),
        const AppDropdownItem(
          value: 'transfer',
          label: 'Transfer dept',
          icon: Icons.swap_horiz,
        ),
      ],
    );
    if (chosen != null) await widget.onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Tooltip(
      message: 'Actions',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _hover ? t.bgHover : t.bgElevated,
              border: Border.all(color: t.borderSubtle, width: 1),
              borderRadius: BorderRadius.circular(WebTokens.rSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Actions',
                  style: t.bodySm.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 16, color: t.textPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatefulWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.destructive = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool destructive;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final bg = _hover
        ? (widget.destructive ? t.dangerLight : t.bgHover)
        : t.bgElevated;
    final fg = _hover && widget.destructive
        ? t.danger
        : t.textPrimary;
    final child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: t.borderSubtle, width: 1),
            borderRadius: BorderRadius.circular(WebTokens.rSm),
          ),
          child: Icon(widget.icon, size: 16, color: fg),
        ),
      ),
    );
    return widget.tooltip == null
        ? child
        : Tooltip(message: widget.tooltip!, child: child);
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
  final ValueChanged<BuildContext> onStatusTap;
  final ValueChanged<BuildContext> onPriorityTap;
  final ValueChanged<BuildContext> onAssigneeTap;
  final ValueChanged<BuildContext> onDepartmentTap;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final priorityName = task.priority?.name.trim() ?? '';
    final assignee = (task.assignee ?? '').trim();
    final department = (task.departmentName ?? '').trim();

    final cells = <Widget>[
       _FieldRow(
        rowKey: assigneeRowKey,
        icon: Icons.person_outline,
        label: 'Assignee',
        sidebar: sidebar,
        onTap: onAssigneeTap,
        value: assignee.isEmpty
            ? const _EmptyValue(label: 'Unassigned')
            : _TextValue(
                text: assignee,
                tone: t.accent,
                linked: true,
              ),
      ),
       _FieldRow(
        rowKey: departmentRowKey,
        icon: Icons.business_outlined,
        label: 'Department',
        sidebar: sidebar,
        onTap: onDepartmentTap,
        value: department.isEmpty
            ? const _EmptyValue(label: 'None')
            : _TextValue(
                text: department,
                tone: t.accent,
                linked: true,
              ),
      ),
      _FieldRow(
        rowKey: statusRowKey,
        icon: Icons.flag_outlined,
        label: 'Status',
        sidebar: sidebar,
        onTap: onStatusTap,
        value: _StatusValuePill(
          label: task.statusName,
          color: _statusTone(task, t),
        ),
      ),
      _FieldRow(
        rowKey: priorityRowKey,
        icon: Icons.priority_high,
        label: 'Priority',
        sidebar: sidebar,
        onTap: onPriorityTap,
        value: priorityName.isEmpty
            ? const _EmptyValue(label: 'No priority')
            : _StatusValuePill(
                label: _titleCase(priorityName),
                color: _priorityTone(priorityName, t),
                icon: Icons.flag_rounded,
              ),
      ),
      if (task.duedate != null)
        _FieldRow(
          icon: Icons.schedule,
          label: 'Due',
          sidebar: sidebar,
          value: _TextValue(
            text: Fmt.dateTime(task.duedate),
            tone: task.overdue ? t.danger : null,
          ),
        ),
      if (task.blocked)
        _FieldRow(
          icon: Icons.block,
          label: 'Blocked',
          sidebar: sidebar,
          value: _TextValue(
            text: 'Blocked by dependency',
            tone: t.danger,
          ),
        ),
      if (task.progress > 0)
        _FieldRow(
          icon: Icons.donut_small_outlined,
          label: 'Progress',
          sidebar: sidebar,
          value: _TextValue(text: '${task.progress}%'),
        ),
      _FieldRow(
        icon: Icons.event_outlined,
        label: 'Created',
        sidebar: sidebar,
        value: _TextValue(text: Fmt.dateTime(task.created)),
      ),
    ];

    // Sidebar mode: wrap the field rows in a single elevated card so every
    // row (clickable or not) sits on the same white ground against the
    // panel's warm-paper bg. The card's subtle shadow lifts the rail off
    // the page. [DefaultTextStyle] pins the ambient base to `bodyBase` so
    // descendant [_TextValue] runs inherit the sidebar's 14 px size —
    // fields rail reads one size-step above the messages column, matching
    // TicketDetailPanel.
    if (sidebar) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          WebTokens.s3,
          0,
          WebTokens.s3,
          WebTokens.s3,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.bgElevated,
            borderRadius: BorderRadius.circular(WebTokens.rMd),
            border: Border.all(color: t.borderSubtle, width: 1),
            boxShadow: WebTokens.shadowXs,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WebTokens.s3,
              vertical: WebTokens.s2,
            ),
            child: DefaultTextStyle.merge(
              style: t.bodyBase.copyWith(color: t.textPrimary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: WebTokens.s4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(WebTokens.rMd),
          border: Border.all(color: t.borderSubtle, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s3,
            vertical: WebTokens.s2,
          ),
          child: DefaultTextStyle.merge(
            style: t.bodySm.copyWith(color: t.textPrimary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: cells,
            ),
          ),
        ),
      ),
    );
  }

  static Color _statusTone(Task task, WebTokens t) {
    if (task.overdue) return t.danger;
    if (!task.isOpen) return t.textSecondary;
    return WebTokens.success;
  }

  static Color _priorityTone(String name, WebTokens t) {
    final n = name.toLowerCase();
    if (n.contains('emergency') || n.contains('urgent')) return t.danger;
    if (n.contains('high')) return WebTokens.warning;
    if (n.contains('low')) return WebTokens.success;
    if (n.contains('normal')) return WebTokens.info;
    return WebTokens.info;
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}

class _FieldRow extends StatefulWidget {
  const _FieldRow({
    this.rowKey,
    required this.icon,
    required this.label,
    required this.value,
    required this.sidebar,
    this.onTap,
  });
  final GlobalKey? rowKey;
  final IconData icon;
  final String label;
  final Widget value;

  /// True when the row is rendered inside the wide-mode right rail. In
  /// sidebar mode the clickable value slot flexes to fill remaining space
  /// instead of using the fixed [_kFieldValueWidth] pill width — the
  /// sidebar itself is only ~320 px wide, so a 280 px value would clip.
  final bool sidebar;

  final ValueChanged<BuildContext>? onTap;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final clickable = widget.onTap != null;
    final Widget valueSlot;
    if (clickable) {
      // Key on the pill (not the row) — dropdown popups anchor here so
      // they land under the value, aligned with the trigger's left edge
      // and width.
      final Widget pill = KeyedSubtree(
        key: widget.rowKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: widget.value),
              Icon(
                Icons.expand_more,
                size: 16,
                color: _hover ? t.accent : t.textSecondary,
              ),
            ],
          ),
        ),
      );
      // In sidebar mode the pill flexes to fill remaining row width — the
      // 320 px rail is too narrow for the 280 px fixed pill used in the
      // wider single-column card layout.
      valueSlot = widget.sidebar
          ? Expanded(child: pill)
          : SizedBox(width: _kFieldValueWidth, child: pill);
    } else {
      valueSlot = Expanded(child: widget.value);
    }
    // Sidebar rows sit on a taller [_kSidebarRowHeight] rhythm and bump
    // the label to the 14 px `bodyBase` size so the fields rail reads as
    // its own scannable column, not a squeezed footnote. Matches the
    // TicketDetailPanel reference.
    final rowHeight = widget.sidebar ? _kSidebarRowHeight : 30.0;
    final labelStyle = widget.sidebar
        ? t.bodyBase.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w500,
          )
        : t.bodySm.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w500,
          );
    // Leading icons removed — labels alone carry the meaning and the row
    // reads cleaner without the credential glyphs (person / building /
    // flag / bang / calendar).
    final row = SizedBox(
      height: rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WebTokens.s1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _kFieldLabelWidth,
              child: Text(widget.label, style: labelStyle),
            ),
            const SizedBox(width: WebTokens.s3),
            valueSlot,
          ],
        ),
      ),
    );
    if (!clickable) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap!(
          widget.rowKey?.currentContext ?? context,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          color: t.bgElevated,
          child: row,
        ),
      ),
    );
  }
}

class _TextValue extends StatefulWidget {
  const _TextValue({required this.text, this.tone, this.linked = false});
  final String text;
  final Color? tone;
  final bool linked;

  @override
  State<_TextValue> createState() => _TextValueState();
}

class _TextValueState extends State<_TextValue> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final color = widget.tone ?? t.textPrimary;
    // Inherit the ambient DefaultTextStyle base so the sidebar's bumped
    // 14 px wrap propagates into value text — the surrounding column
    // wraps in a DefaultTextStyle.merge with `bodyBase` (sidebar) or
    // `bodySm` (narrow card), and this pulls that size out of the
    // ambient rather than hard-pinning to `bodyBase`.
    final base = DefaultTextStyle.of(context).style;
    final child = Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(
        color: color,
        fontWeight: FontWeight.w500,
        decoration: widget.linked && _hover
            ? TextDecoration.underline
            : TextDecoration.none,
        decorationColor: color,
      ),
    );
    if (!widget.linked) return child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: child,
    );
  }
}

class _StatusValuePill extends StatelessWidget {
  const _StatusValuePill({
    required this.label,
    required this.color,
    this.icon,
  });
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: StatusPill(label: label, color: color, icon: icon),
    );
  }
}

class _EmptyValue extends StatelessWidget {
  const _EmptyValue({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.bodyBase.copyWith(
        color: t.textSecondary,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity subheader
// ---------------------------------------------------------------------------

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader();

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s4,
        vertical: WebTokens.s3,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(
          top: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      child: Text(
        'Activity',
        style: t.cardName.copyWith(color: t.textPrimary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thread row — card per entry with actor avatar + floated timestamp.
// ---------------------------------------------------------------------------

class _ThreadRow extends StatefulWidget {
  const _ThreadRow({required this.entry});
  final ThreadEntry entry;

  @override
  State<_ThreadRow> createState() => _ThreadRowState();
}

class _ThreadRowState extends State<_ThreadRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final entry = widget.entry;
    final isNote = entry.isNote;
    final isResponse = entry.isResponse;
    final tone = isNote
        ? WebTokens.warning
        : (isResponse ? t.accent : t.textSecondary);
    final typeLabel = isNote
        ? 'NOTE'
        : (isResponse ? 'REPLY' : 'MESSAGE');
    final html = entry.bodyHtml ?? entry.body ?? '';
    final plain = Fmt.stripHtml(html);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTokens.s4,
        WebTokens.s3,
        WebTokens.s4,
        0,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: t.bgElevated,
            borderRadius: BorderRadius.circular(WebTokens.rMd),
            border: Border.all(
              color: _hover ? t.borderDefault : t.borderSubtle,
              width: 1,
            ),
            boxShadow: _hover ? WebTokens.shadowSm : WebTokens.shadowXs,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s4,
            vertical: WebTokens.s3,
          ),
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ActorAvatar(name: entry.poster),
                  const SizedBox(width: WebTokens.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.poster,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.cardName
                                    .copyWith(color: t.textPrimary),
                              ),
                            ),
                            const SizedBox(width: WebTokens.s2),
                            _TypeTag(label: typeLabel, tone: tone),
                            const SizedBox(width: 96),
                          ],
                        ),
                        const SizedBox(height: WebTokens.s2),
                        if (plain.trim().isEmpty)
                          Text('(no content)', style: t.bodySm)
                        else if (html.contains('<'))
                          _HtmlBody(html: html)
                        else
                          Text(
                            plain,
                            style: t.bodyBase.copyWith(height: 1.5),
                          ),
                        if (entry.attachments.isNotEmpty) ...[
                          const SizedBox(height: WebTokens.s3),
                          Wrap(
                            spacing: WebTokens.s2,
                            runSpacing: WebTokens.s2,
                            children: [
                              for (final a in entry.attachments)
                                _AttachmentChip(attachment: a),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (entry.created != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Text(Fmt.ago(entry.created), style: t.tinyLabel),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _kAvatarPalette = <Color>[
  Color(0xFFF6B93B),
  Color(0xFF5DADE2),
  Color(0xFF58D68D),
  Color(0xFFAF7AC5),
  Color(0xFFF5A623),
  Color(0xFF48C9B0),
  Color(0xFFEC7063),
  Color(0xFF5D6D7E),
];

class _ActorAvatar extends StatelessWidget {
  const _ActorAvatar({required this.name});
  final String name;

  static String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '·';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  static Color _color(String s) {
    if (s.isEmpty) return _kAvatarPalette[0];
    var hash = 0;
    for (final c in s.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return _kAvatarPalette[hash % _kAvatarPalette.length];
  }

  @override
  Widget build(BuildContext context) {
    final bg = _color(name);
    return Container(
      width: _kAvatarSize,
      height: _kAvatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        _initials(name),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          height: 1.0,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.label, required this.tone});
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Text(label, style: t.tinyLabel.copyWith(color: tone));
  }
}

// ---------------------------------------------------------------------------
// Attachment chip
// ---------------------------------------------------------------------------

class _AttachmentChip extends StatefulWidget {
  const _AttachmentChip({required this.attachment});
  final Attachment attachment;

  @override
  State<_AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends State<_AttachmentChip> {
  bool _hover = false;

  IconData get _icon {
    final t = widget.attachment.type ?? '';
    if (t.startsWith('image/')) return Icons.image_outlined;
    if (t.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (t.contains('sheet') || t.contains('excel')) {
      return Icons.table_chart_outlined;
    }
    if (t.contains('word') || t.contains('document')) {
      return Icons.description_outlined;
    }
    if (t.contains('zip') || t.contains('rar') || t.contains('compressed')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.attach_file;
  }

  Future<void> _open() async {
    final a = widget.attachment;
    final url = a.downloadUrl ?? a.streamUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final a = widget.attachment;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s3,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: _hover ? t.accentSoft : t.bgTertiary,
            border: Border.all(
              color: _hover ? t.accent : t.borderSubtle,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _icon,
                size: 14,
                color: _hover ? t.accent : t.textSecondary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySm.copyWith(
                    color: _hover ? t.accent : t.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (a.size != null) ...[
                const SizedBox(width: 6),
                Text(
                  Fmt.fileSize(a.size),
                  style: t.tinyLabel.withTabularNums(),
                ),
              ],
              const SizedBox(width: 6),
              Icon(
                Icons.open_in_new,
                size: 12,
                color: _hover ? t.accent : t.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HtmlBody extends StatelessWidget {
  const _HtmlBody({required this.html});
  final String html;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return ClipRect(
      child: HtmlWidget(
        html,
        textStyle: t.bodyBase.copyWith(height: 1.5),
        onTapUrl: (url) async {
          final uri = Uri.tryParse(url);
          if (uri == null) return false;
          return launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        customStylesBuilder: (element) {
          switch (element.localName) {
            case 'b':
            case 'strong':
              return {'font-weight': '600'};
            case 'small':
            case 'sub':
            case 'sup':
              return {'font-size': '13px'};
            case 'a':
              return {
                'color': '#0037B7',
                'text-decoration': 'underline',
              };
            default:
              return null;
          }
        },
      ),
    );
  }
}
