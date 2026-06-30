import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/reports.dart';
import '../../../widgets/states.dart';
import 'activity_line_chart.dart';

/// A card showing the "Ticket activity" line chart (opened vs closed over the
/// report window) with a title and legend. Shared by the dashboard and the
/// full reports screen.
class ActivityChartCard extends StatelessWidget {
  const ActivityChartCard({
    super.key,
    required this.report,
    this.title = 'Ticket activity',
  });

  final VolumeReport report;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = report.series;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  _Legend(color: AppTheme.open, label: 'Opened'),
                  const SizedBox(width: 14),
                  _Legend(color: AppTheme.closed, label: 'Closed'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (series.isEmpty)
              const SizedBox(
                height: 140,
                child: EmptyView(message: 'No activity in this range'),
              )
            else
              ActivityLineChart(
                height: 210,
                dates: [for (final p in series) DateTime.tryParse(p.date)],
                series: [
                  ChartSeries(
                    label: 'Opened',
                    color: AppTheme.open,
                    values: [for (final p in series) p.opened.toDouble()],
                  ),
                  ChartSeries(
                    label: 'Closed',
                    color: AppTheme.closed,
                    values: [for (final p in series) p.closed.toDouble()],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
