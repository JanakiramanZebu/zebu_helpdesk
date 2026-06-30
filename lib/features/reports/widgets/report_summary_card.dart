import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/reports.dart';
import 'report_range_selector.dart';

/// Headline volume totals for the selected window: opened / closed / net, with
/// per-day averages. Shared by the dashboard and the full reports screen.
///
/// When [onDaysSelected] is provided, the header shows a day-range dropdown
/// (driven by [days]) so the range can be changed from within the card;
/// otherwise it shows a static "Last N days" title.
class ReportSummaryCard extends StatelessWidget {
  const ReportSummaryCard({
    super.key,
    required this.report,
    this.days,
    this.onDaysSelected,
    this.loading = false,
  });

  final VolumeReport report;
  final int? days;
  final ValueChanged<int>? onDaysSelected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final span = report.days == 0 ? 1 : report.days;
    final avgOpened = report.openedTotal / span;
    final avgClosed = report.closedTotal / span;
    final net = report.net;
    final hasPicker = onDaysSelected != null && days != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPicker)
              Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: ReportRangeSelector(
                      days: days!,
                      onSelected: onDaysSelected!,
                    ),
                  ),
                  const Spacer(),
                  if (loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                ],
              )
            else
              Text(
                'Last ${report.days} days',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 14),
            Row(
              children: [
                _Metric(
                  label: 'Opened',
                  value: Fmt.count(report.openedTotal),
                  color: AppTheme.open,
                ),
                _divider(theme),
                _Metric(
                  label: 'Closed',
                  value: Fmt.count(report.closedTotal),
                  color: AppTheme.closed,
                ),
                _divider(theme),
                _Metric(
                  label: 'Net',
                  value: net > 0 ? '+${Fmt.count(net)}' : Fmt.count(net),
                  color: net > 0 ? AppTheme.overdue : AppTheme.open,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Avg ${avgOpened.toStringAsFixed(1)} opened · '
              '${avgClosed.toStringAsFixed(1)} closed per day',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(ThemeData theme) =>
      Container(width: 1, height: 36, color: theme.colorScheme.outlineVariant);
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
