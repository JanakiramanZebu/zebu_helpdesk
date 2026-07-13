import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_text.dart';

/// One tappable metric inside a [FocusStrip].
class FocusMetric {
  const FocusMetric({
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });
  final String label;
  final int value;
  final Color color;
  final VoidCallback? onTap;
}

/// A single flat card holding a small row of headline metrics separated by
/// hairline dividers — the "what needs me now" summary at the top of the
/// dashboard. Each cell is tappable and drills into the matching filtered list.
///
/// Deliberately restrained: surface fill, one hairline border, a slim colored
/// top-accent per cell for status legibility, animated counts. No gradients or
/// shadows — it sits inside the existing flat Mynt system.
class FocusStrip extends StatelessWidget {
  const FocusStrip({super.key, required this.metrics});

  final List<FocusMetric> metrics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < metrics.length; i++) ...[
              if (i > 0)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: scheme.outlineVariant,
                ),
              Expanded(child: _Cell(metric: metrics[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.metric});
  final FocusMetric metric;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: metric.onTap,
        splashColor: metric.color.withValues(alpha: 0.10),
        highlightColor: metric.color.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Slim status dot for legibility without shouting.
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: metric.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(height: 10),
              AppText.custmText(
                context,
                Fmt.count(metric.value),
                fs: 26,
                fw: 2,
                color: scheme.onSurface,
                height: 1.05,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              AppText.paraText(
                context,
                metric.label,
                color: scheme.onSurfaceVariant,
                fw: 0,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                align: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
