import 'package:flutter/material.dart';

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
          Text(
            label,
            style: TextStyle(
              color: c,
              fontSize: dense ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
