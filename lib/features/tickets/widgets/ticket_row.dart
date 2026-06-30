import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../models/ticket.dart';
import '../../../widgets/selection_check.dart';
import '../../../widgets/status_chip.dart';
import '../../../widgets/user_avatar.dart';

/// The original ticket card design, with optional multi-select chrome: a
/// leading checkbox and a highlighted border when [selected].
class TicketRow extends StatelessWidget {
  const TicketRow({
    super.key,
    required this.ticket,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.onToggle,
  });

  final Ticket ticket;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final requester = ticket.requester ?? 'Unknown';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: selected ? scheme.primary.withValues(alpha: 0.06) : null,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.primary, width: 1.4),
            )
          : null,
      child: InkWell(
        onTap: selectionMode ? onToggle : onTap,
        onLongPress: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              if (selectionMode) ...[
                SelectionCheck(selected: selected),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '#${ticket.number}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        if (ticket.isOverdue)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: Color(0xFFD32F2F),
                            ),
                          ),
                        StatusChip.status(ticket.statusName, dense: true),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ticket.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        UserAvatar(name: requester, radius: 12),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            requester,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (ticket.priority != null) ...[
                          StatusChip.priority(ticket.priority!, dense: true),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          Fmt.ago(ticket.created),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (ticket.departmentName != null ||
                        ticket.assignee != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (ticket.departmentName != null) ...[
                            Icon(
                              Icons.apartment,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              ticket.departmentName!,
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(width: 12),
                          ],
                          if (ticket.assignee != null) ...[
                            Icon(
                              Icons.person_pin_circle_outlined,
                              size: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                ticket.assignee!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
