import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_text.dart';
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
                  AppText.paraText(
                    context,
                    '#${ticket.number}',
                    color: theme.colorScheme.primary,
                    fw: 2,
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
              AppText.subText(
                context,
                ticket.subject,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                fw: 1,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  UserAvatar(name: requester, radius: 12),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AppText.paraText(
                      context,
                      requester,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (ticket.priority != null) ...[
                    StatusChip.priority(ticket.priority!, dense: true),
                    const SizedBox(width: 6),
                  ],
                  AppText.paraText(
                    context,
                    Fmt.ago(ticket.created),
                    color: theme.colorScheme.onSurfaceVariant,
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
                      AppText.paraText(
                        context,
                        ticket.departmentName!,
                        color: theme.colorScheme.onSurface,
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
                        child: AppText.paraText(
                          context,
                          ticket.assignee!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          color: theme.colorScheme.onSurface,
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
