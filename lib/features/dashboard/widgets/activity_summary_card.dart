import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/reports.dart';
import 'activity_range_selector.dart';

/// Headline volume totals for the dashboard's Overview section: opened /
/// closed / net over the selected window, with per-day averages.
///
/// The header carries the day-range dropdown, so the window can be changed
/// from within the card; [loading] dims it while the new range is in flight.
class ActivitySummaryCard extends StatelessWidget {
  const ActivitySummaryCard({
    super.key,
    required this.report,
    required this.days,
    required this.onDaysSelected,
    this.loading = false,
  });

  final VolumeReport report;
  final int days;
  final ValueChanged<int> onDaysSelected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final span = report.days == 0 ? 1 : report.days;
    final avgOpened = report.openedTotal / span;
    final avgClosed = report.closedTotal / span;
    final net = report.net;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: ActivityRangeSelector(
                    days: days,
                    onSelected: onDaysSelected,
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
            AppText.paraText(
              context,
              'Avg ${avgOpened.toStringAsFixed(1)} opened · '
              '${avgClosed.toStringAsFixed(1)} closed per day',
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
    return Expanded(
      child: Column(
        children: [
          AppText.custmText(context, value, fs: 24, fw: 2, color: color),
          const SizedBox(height: 2),
          AppText.paraText(context, label),
        ],
      ),
    );
  }
}
