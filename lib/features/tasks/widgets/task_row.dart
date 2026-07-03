import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/task.dart';
import '../../../widgets/entity_list_row.dart';

/// A task list row. Thin adapter over the shared [EntityListRow] — maps a
/// [Task] to an [EntityRowData] so tasks and tickets share one row design.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.onToggle,
    this.compact = false,
  });

  final Task task;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggle;

  /// When true, renders a dense single-line row (more items per screen).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final assignee = task.assignee ?? 'Unassigned';

    return EntityListRow(
      onTap: onTap,
      selectionMode: selectionMode,
      selected: selected,
      onToggle: onToggle,
      compact: compact,
      data: EntityRowData(
        number: task.number,
        title: task.title,
        statusName: task.statusName,
        personName: assignee,
        createdAgo: Fmt.ago(task.created),
        createdTooltip: 'Created ${Fmt.dateTime(task.created)}',
        priorityLabel: task.priority?.name,
        accentColor: AppTheme.priorityAccent(task.priority?.name, scheme),
        danger: task.blocked,
        dangerLabel: 'Blocked',
        dangerIcon: Icons.lock_outline,
        progress: task.progress,
        subtitleParts: [
          if (task.progress > 0) '${task.progress}%',
        ],
        metaChips: [
          if ((task.departmentName ?? '').isNotEmpty)
            EntityMetaChip(icon: Icons.apartment, label: task.departmentName!),
          if (task.duedate != null)
            EntityMetaChip(
              icon: Icons.event_outlined,
              label: Fmt.date(task.duedate),
              danger: task.overdue,
            ),
        ],
      ),
    );
  }
}
