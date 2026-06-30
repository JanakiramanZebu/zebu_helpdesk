import 'package:flutter/material.dart';

/// Day-range picker (7 / 30 / 90 days) rendered as a dropdown. Used by the
/// dashboard and the full reports screen.
class ReportRangeSelector extends StatelessWidget {
  const ReportRangeSelector({
    super.key,
    required this.days,
    required this.onSelected,
  });

  final int days;
  final ValueChanged<int> onSelected;

  static const _options = [7, 30, 90];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: days,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: scheme.onSurfaceVariant,
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          items: [
            for (final d in _options)
              DropdownMenuItem(value: d, child: Text('Last $d days')),
          ],
          onChanged: (v) {
            if (v != null) onSelected(v);
          },
        ),
      ),
    );
  }
}
