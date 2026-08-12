import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/task.dart';
import '../../../res/zebu_spacing.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../widgets/web/detail_fields.dart';
import '../../../widgets/web/status_badge.dart';
import '../../../widgets/web/zebu_dialog.dart';

/// Subtasks and dependencies for a task, as detail-panel sidebar sections.
///
/// These used to live only on the full-page `TaskDetailScreenWeb`, which was
/// routed at `/tasks/:id` but which nothing in the app ever navigated to —
/// the list opens the slide-over panel instead. So the two features backed by
/// `/tasks/{id}/subtasks` and `/tasks/{id}/dependencies` were reachable only
/// by typing a URL. Moving them here is what let that screen be deleted
/// rather than restyled.

class _AddLink extends StatefulWidget {
  const _AddLink({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_AddLink> createState() => _AddLinkState();
}

class _AddLinkState extends State<_AddLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            // Idle is the hover tone at zero alpha, never
            // `Colors.transparent` — that is transparent *black*, and a fill
            // lerping from it washes through grey on the way in.
            color: _hover ? t.accentSoft : t.accentSoft.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(Icons.add_rounded, size: 16, color: t.accent),
        ),
      ),
    );
  }
}

/// Subtask list. Each row opens that subtask in the panel.
class TaskSubtasksSection extends StatelessWidget {
  const TaskSubtasksSection({
    super.key,
    required this.subtasks,
    required this.onOpen,
    this.onAdd,
  });

  final List<Task> subtasks;
  final ValueChanged<Task> onOpen;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ZebuFieldGroupLabel(
          'Subtasks',
          count: subtasks.length,
          trailing: onAdd == null ? null : _AddLink(onTap: onAdd!),
        ),
        if (subtasks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: ZebuSpacing.s2,
              bottom: ZebuSpacing.s2,
            ),
            child: Text(
              'None',
              style: ZebuTextStyles.small(context, color: t.textSlateMuted),
            ),
          )
        else
          for (final task in subtasks)
            _RelationRow(
              number: task.number,
              title: task.title,
              trailing: StatusBadge(
                label: task.statusName,
                status: task.statusName,
                dense: true,
              ),
              onTap: () => onOpen(task),
            ),
      ],
    );
  }
}

/// Blocking tasks. Each row can be opened or detached.
class TaskDependenciesSection extends StatelessWidget {
  const TaskDependenciesSection({
    super.key,
    required this.dependencies,
    required this.onOpen,
    this.onAdd,
    this.onRemove,
  });

  final List<TaskDependency> dependencies;
  final ValueChanged<TaskDependency> onOpen;
  final VoidCallback? onAdd;
  final ValueChanged<TaskDependency>? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ZebuFieldGroupLabel(
          'Blocked by',
          count: dependencies.length,
          trailing: onAdd == null ? null : _AddLink(onTap: onAdd!),
        ),
        if (dependencies.isEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: ZebuSpacing.s2,
              bottom: ZebuSpacing.s2,
            ),
            child: Text(
              'Nothing',
              style: ZebuTextStyles.small(context, color: t.textSlateMuted),
            ),
          )
        else
          for (final dep in dependencies)
            _RelationRow(
              number: dep.blocker?.number ?? '${dep.id}',
              title: dep.blocker?.title ?? 'Dependency',
              // A blocker that is still open is the whole point of the row —
              // it is why this task can't close. A closed one is history, so
              // it gets the quiet check rather than the padlock.
              leading: Icon(
                (dep.blocker?.open ?? true)
                    ? Icons.lock_outline
                    : Icons.check_circle_outline,
                size: 15,
                color: (dep.blocker?.open ?? true)
                    ? t.danger
                    : ZebuTheme.success,
              ),
              trailing: dep.required
                  ? null
                  : Text(
                      'Optional',
                      style: ZebuTextStyles.caption(
                        context,
                        color: t.textSlateMuted,
                      ),
                    ),
              onTap: () => onOpen(dep),
              onRemove: onRemove == null ? null : () => onRemove!(dep),
            ),
      ],
    );
  }
}

/// One relation row — id, title, and an optional trailing badge or detach.
class _RelationRow extends StatefulWidget {
  const _RelationRow({
    required this.number,
    required this.title,
    required this.onTap,
    this.leading,
    this.trailing,
    this.onRemove,
  });

  final String number;
  final String title;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onRemove;

  @override
  State<_RelationRow> createState() => _RelationRowState();
}

class _RelationRowState extends State<_RelationRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s2,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgHover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: ZebuSpacing.s2),
              ],
              Text(
                '#${widget.number}',
                style: ZebuTextStyles.small(
                  context,
                  color: t.linkSlate,
                  fontWeight: ZebuFonts.semiBold,
                ).withTabularNums(),
              ),
              const SizedBox(width: ZebuSpacing.s2),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZebuTextStyles.small(context, color: t.textSlate),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: ZebuSpacing.s2),
                widget.trailing!,
              ],
              // Detach only appears on hover — a permanent × on every row in a
              // 320 px column is a lot of chrome for a rare action, and an
              // always-visible remove next to a tappable row invites the
              // mis-click it causes.
              if (widget.onRemove != null) ...[
                const SizedBox(width: ZebuSpacing.s2),
                Opacity(
                  opacity: _hover ? 1 : 0,
                  child: GestureDetector(
                    onTap: widget.onRemove,
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: t.iconMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialogs
// ---------------------------------------------------------------------------

/// What [TaskSubtaskDialog] hands back to its creator.
typedef SubtaskDraft = ({String title, String? description});

/// Asks for a new subtask's title and optional description.
class TaskSubtaskDialog extends StatefulWidget {
  const TaskSubtaskDialog({
    super.key,
    required this.taskNumber,
    required this.taskTitle,
    required this.onCreate,
  });

  final String taskNumber;
  final String taskTitle;

  /// Performs the create. Throwing keeps the dialog open with an error rather
  /// than dismissing and losing what the agent typed.
  final Future<void> Function(SubtaskDraft draft) onCreate;

  @override
  State<TaskSubtaskDialog> createState() => _TaskSubtaskDialogState();
}

class _TaskSubtaskDialogState extends State<TaskSubtaskDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _titleFocus = FocusNode();

  bool _submitting = false;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _titleFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_submitting) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'A subtask needs a title');
      _titleFocus.requestFocus();
      return;
    }
    final desc = _description.text.trim();
    setState(() {
      _titleError = null;
      _submitting = true;
    });
    try {
      await widget.onCreate((
        title: title,
        description: desc.isEmpty ? null : desc,
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _titleError = 'Could not create the subtask. Try again.';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return ZebuDialogShell(
      title: 'Add subtask',
      // subtitle: dropped. The parent task is on the panel directly behind
      // this dialog, so naming it again was a line that told the agent
      // nothing they weren't already looking at.
      // ],
      // ),
      // ),
      onDismiss: _dismiss,
      onSubmit: _submit,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ZebuDialogField(
            label: 'Title',
            errorText: _titleError,
            child: ZebuDialogInput(
              controller: _title,
              focusNode: _titleFocus,
              // Instructive, not an invented example: the old hint described
              // a payout scenario on whatever task you happened to open.
              hint: 'What needs to be done',
              enabled: !_submitting,
              hasError: _titleError != null,
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: 16),
          ZebuDialogField(
            label: 'Description',
            child: ZebuDialogInput(
              controller: _description,
              hint: 'Anything the assignee needs to know',
              enabled: !_submitting,
              minLines: 3,
              maxLines: 6,
            ),
          ),
          const SizedBox(height: ZebuSpacing.s5),
          // In the body, full width — the same shape the confirm dialogs
          // use. A footer strip for a single button made two zones out of a
          // card that asks one thing.
          ZebuDialogPrimaryBtn(
            label: 'Add',
            busyLabel: 'Adding…',
            busy: _submitting,
            fullWidth: true,
            onTap: _submit,
          ),
        ],
      ),
      actions: const [],
    );
  }
}

/// Asks for the id of the task that blocks this one.
class TaskDependencyDialog extends StatefulWidget {
  const TaskDependencyDialog({
    super.key,
    required this.taskNumber,
    required this.taskTitle,
  });

  final String taskNumber;
  final String taskTitle;

  @override
  State<TaskDependencyDialog> createState() => _TaskDependencyDialogState();
}

class _TaskDependencyDialogState extends State<TaskDependencyDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final id = int.tryParse(_controller.text.trim());
    if (id == null) {
      setState(() => _error = 'Enter a numeric task ID');
      _focus.requestFocus();
      return;
    }
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    return ZebuDialogShell(
      title: 'Add dependency',
      maxWidth: 420,
      // subtitle: dropped, as on the subtask dialog.
      onDismiss: () => Navigator.of(context).maybePop(),
      onSubmit: _submit,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZebuDialogField(
            label: 'Blocker task ID',
            errorText: _error,
            child: ZebuDialogInput(
              controller: _controller,
              focusNode: _focus,
              hint: 'The task number that has to finish first',
              hasError: _error != null,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: ZebuSpacing.s5),
          ZebuDialogPrimaryBtn(label: 'Add', fullWidth: true, onTap: _submit),
        ],
      ),
      actions: const [],
    );
  }
}
