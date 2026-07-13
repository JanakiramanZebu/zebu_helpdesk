import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/ticket.dart';

/// A slim, single-line-priority row for the dashboard's "Needs attention"
/// list: a colored priority rail, the ticket number + subject, and a compact
/// age/overdue tag on the right. Denser than the full [TicketCard] because the
/// dashboard shows a short triage list, not the browsable ticket list.
class AttentionRow extends StatelessWidget {
  const AttentionRow({super.key, required this.ticket, required this.onTap});

  final Ticket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rail = AppTheme.priorityAccent(ticket.priority, scheme);
    final overdue = ticket.isOverdue;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(
                  color: rail,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        AppText.paraText(
                          context,
                          '#${ticket.number}',
                          color: scheme.primary,
                          fw: 2,
                        ),
                        if (ticket.requester != null) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: AppText.paraText(
                              context,
                              ticket.requester!,
                              color: scheme.onSurfaceVariant,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else
                          const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 2),
                    AppText.subText(
                      context,
                      ticket.subject,
                      fw: 1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _AgeTag(
                label: overdue ? 'Overdue' : Fmt.ago(ticket.created),
                danger: overdue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgeTag extends StatelessWidget {
  const _AgeTag({required this.label, required this.danger});
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = danger ? AppTheme.overdue : scheme.onSurfaceVariant;
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: danger ? c.withValues(alpha: 0.10) : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(7),
      ),
      child: AppText.custmText(
        context,
        label,
        fs: 11,
        fw: 1,
        color: c,
        maxLines: 1,
      ),
    );
  }
}

/// The positive empty state shown in place of the attention list when there is
/// nothing overdue/unassigned — a calm "you're caught up" panel rather than a
/// blank gap.
class AttentionEmpty extends StatelessWidget {
  const AttentionEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.open.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppTheme.open,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText.subText(context, 'All caught up', fw: 1),
                const SizedBox(height: 2),
                AppText.paraText(
                  context,
                  'Nothing overdue right now — nice work.',
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
