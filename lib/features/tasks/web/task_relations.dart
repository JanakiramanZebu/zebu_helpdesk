import 'package:flutter/material.dart';

import '../../../models/task.dart';
import '../../../res/zebu_spacing.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../widgets/web/status_badge.dart';

/// Subtasks and dependencies for a task, as detail-panel sidebar sections.
///
/// These used to live only on the full-page `TaskDetailScreenWeb`, which was
/// routed at `/tasks/:id` but which nothing in the app ever navigated to —
/// the list opens the slide-over panel instead. So the two features backed by
/// `/tasks/{id}/subtasks` and `/tasks/{id}/dependencies` were reachable only
/// by typing a URL. Moving them here is what let that screen be deleted
/// rather than restyled.

/// Section heading with a count and an optional add affordance.
class _RelationHeader extends StatelessWidget {
  const _RelationHeader({required this.label, required this.count, this.onAdd});
  final String label;
  final int count;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: ZebuSpacing.s2,
        top: ZebuSpacing.s4,
        bottom: ZebuSpacing.s2,
      ),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: ZebuTextStyles.eyebrow(
              context,
              color: t.textSlateMuted,
            ).copyWith(letterSpacing: 0.6),
          ),
          if (count > 0) ...[
            const SizedBox(width: ZebuSpacing.s2),
            Text(
              '$count',
              style: ZebuTextStyles.eyebrow(
                context,
                color: t.textSlateMuted,
              ).withTabularNums(),
            ),
          ],
          const Spacer(),
          if (onAdd != null) _AddLink(onTap: onAdd!),
        ],
      ),
    );
  }
}

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
        _RelationHeader(
          label: 'Subtasks',
          count: subtasks.length,
          onAdd: onAdd,
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
        _RelationHeader(
          label: 'Blocked by',
          count: dependencies.length,
          onAdd: onAdd,
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

/// Asks for a new subtask's title and optional description.
class TaskSubtaskDialog extends StatefulWidget {
  const TaskSubtaskDialog({super.key});

  @override
  State<TaskSubtaskDialog> createState() => _TaskSubtaskDialogState();
}

class _TaskSubtaskDialogState extends State<TaskSubtaskDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add subtask'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final title = _title.text.trim();
            if (title.isEmpty) return;
            Navigator.pop(context, (
              title: title,
              description: _description.text.trim(),
            ));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// Asks for the id of the task that blocks this one.
class TaskDependencyDialog extends StatefulWidget {
  const TaskDependencyDialog({super.key});

  @override
  State<TaskDependencyDialog> createState() => _TaskDependencyDialogState();
}

class _TaskDependencyDialogState extends State<TaskDependencyDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final id = int.tryParse(_controller.text.trim());
    if (id == null) {
      setState(() => _error = 'Enter a numeric task ID');
      return;
    }
    Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add dependency'),
      content: SizedBox(
        width: 320,
        child: TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Blocker task ID',
            hintText: 'e.g. 123',
            errorText: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
