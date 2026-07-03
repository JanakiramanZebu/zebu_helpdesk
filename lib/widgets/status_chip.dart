import 'package:flutter/material.dart';

import '../core/theme/app_text.dart';
import '../core/theme/app_theme.dart';

/// A small colored pill for statuses, priorities, tags, etc.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.dense = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool dense;

  /// Derive a sensible color from a ticket/task status name.
  factory StatusChip.status(String status, {bool dense = false}) {
    final s = status.toLowerCase();
    final color =
        s.contains('closed') ||
            s.contains('completed') ||
            s.contains('resolved')
        ? AppTheme.closed
        : s.contains('overdue')
        ? AppTheme.overdue
        : AppTheme.open;
    return StatusChip(label: status, color: color, dense: dense);
  }

  /// Derive a color from a priority display name.
  factory StatusChip.priority(String priority, {bool dense = false}) {
    final p = priority.toLowerCase();
    final color = p.contains('emergency') || p.contains('high')
        ? AppTheme.overdue
        : p.contains('low')
        ? AppTheme.closed
        : AppTheme.warning;
    return StatusChip(
      label: priority,
      color: color,
      dense: dense,
      icon: Icons.flag_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: c),
            const SizedBox(width: 4),
          ],
          AppText.custmText(
            context,
            label,
            fs: dense ? 11 : 12,
            fw: 1,
            color: c,
          ),
        ],
      ),
    );
  }
}

/// A neutral, outlined metadata pill (icon + label) for list cards — e.g.
/// department, due date. Uses muted tones so it reads as secondary info next
/// to the colored [StatusChip]s. Turns red when [danger] (e.g. overdue).
class MetaChip extends StatelessWidget {
  const MetaChip({
    super.key,
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: danger
              ? scheme.error.withValues(alpha: 0.4)
              : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: AppText.custmText(
              context,
              label,
              fs: 11,
              fw: 0,
              color: fg,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
