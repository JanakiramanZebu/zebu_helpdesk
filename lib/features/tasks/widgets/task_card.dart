import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../models/task.dart';
import '../../../widgets/status_chip.dart';
import '../../../widgets/user_avatar.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, required this.onTap});
  final Task task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assignee = task.assignee ?? 'Unassigned';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${task.number}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (task.blocked)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: Color(0xFFD32F2F),
                      ),
                    ),
                  StatusChip.status(task.statusName, dense: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  UserAvatar(name: assignee, radius: 12),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      assignee,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (task.priority != null) ...[
                    StatusChip.priority(task.priority!.name, dense: true),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    Fmt.ago(task.created),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (task.departmentName != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.apartment,
                      size: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        task.departmentName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              if (task.progress > 0) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (task.progress / 100).clamp(0, 1),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${task.progress}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
