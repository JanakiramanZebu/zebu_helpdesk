import 'package:flutter/material.dart';

import '../../../core/theme/app_text.dart';

/// Day-range picker (7 / 30 / 90 days) rendered as a dropdown, driving the
/// dashboard's Overview window.
class ActivityRangeSelector extends StatelessWidget {
  const ActivityRangeSelector({
    super.key,
    required this.days,
    required this.onSelected,
  });

  final int days;
  final ValueChanged<int> onSelected;

  static const _options = [7, 30, 90];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
          style: AppText.style(
            context,
            fontSize: 14,
            color: scheme.onSurface,
            fw: 1,
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
