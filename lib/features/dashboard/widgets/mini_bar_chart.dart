import 'package:flutter/material.dart';

import '../../../core/theme/app_text.dart';

/// A dependency-free horizontal bar list. Each row shows a label on the left,
/// a proportional filled track in the middle, and the value on the right.
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    super.key,
    required this.data,
    this.maxValue,
    this.labelWidth = 90,
  });

  final List<({String label, int value, Color color})> data;

  /// Override the denominator used to size bars. Defaults to the largest value.
  final int? maxValue;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (data.isEmpty) {
      return AppText.subText(context, 'No data', color: scheme.onSurfaceVariant);
    }
    final max =
        (maxValue ?? data.fold<int>(0, (m, e) => e.value > m ? e.value : m))
            .clamp(1, 1 << 31);

    return Column(
      children: [
        for (final row in data)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  child: AppText.paraText(
                    context,
                    row.label,
                    color: scheme.onSurface,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      height: 16,
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (row.value / max).clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: row.color,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 36,
                  child: AppText.paraText(
                    context,
                    '${row.value}',
                    color: scheme.onSurface,
                    fw: 1,
                    align: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
