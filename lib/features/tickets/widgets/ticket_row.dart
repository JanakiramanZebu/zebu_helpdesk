import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ticket.dart';
import '../../../widgets/entity_list_row.dart';

/// A ticket list row. Thin adapter over the shared [EntityListRow] — maps a
/// [Ticket] to an [EntityRowData] so tickets and tasks share one row design.
class TicketRow extends StatelessWidget {
  const TicketRow({
    super.key,
    required this.ticket,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.onToggle,
    this.compact = false,
  });

  final Ticket ticket;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggle;

  /// When true, renders a dense single-line row (more items per screen).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final requester = ticket.requester ?? 'Unknown';

    return EntityListRow(
      onTap: onTap,
      selectionMode: selectionMode,
      selected: selected,
      onToggle: onToggle,
      compact: compact,
      data: EntityRowData(
        number: ticket.number,
        title: ticket.subject,
        statusName: ticket.statusName,
        personName: requester,
        createdAgo: Fmt.ago(ticket.created),
        createdTooltip: 'Created ${Fmt.dateTime(ticket.created)}',
        priorityLabel: ticket.priority,
        accentColor: AppTheme.priorityAccent(ticket.priority, scheme),
        danger: ticket.isOverdue,
        dangerLabel: 'Overdue',
        subtitleParts: [
          if ((ticket.departmentName ?? '').isNotEmpty) ticket.departmentName!,
        ],
        metaChips: [
          if ((ticket.departmentName ?? '').isNotEmpty)
            EntityMetaChip(icon: Icons.apartment, label: ticket.departmentName!),
          if (ticket.due != null)
            EntityMetaChip(
              icon: Icons.event_outlined,
              label: Fmt.date(ticket.due),
              danger: ticket.isOverdue,
            ),
        ],
      ),
    );
  }
}
