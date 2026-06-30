import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../models/ticket.dart';
import '../../../widgets/status_chip.dart';
import '../../../widgets/user_avatar.dart';

class TicketCard extends StatelessWidget {
  const TicketCard({super.key, required this.ticket, required this.onTap});
  final Ticket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final requester = ticket.requester ?? 'Unknown';
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
                    '#${ticket.number}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
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
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (ticket.departmentName != null || ticket.assignee != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (ticket.departmentName != null) ...[
                      Icon(
                        Icons.apartment,
                        size: 13,
                        color: theme.colorScheme.onSurfaceVariant,
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
                        color: theme.colorScheme.onSurfaceVariant,
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
      ),
    );
  }
}
