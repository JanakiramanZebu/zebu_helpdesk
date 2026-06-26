import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../models/reports.dart';
import '../../providers.dart';
import '../../widgets/states.dart';
import '../dashboard/widgets/stat_tile.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _days = 30;
  VolumeReport? _report;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report =
          await ref.read(reportsRepositoryProvider).volume(days: _days);
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _selectDays(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 days')),
            ButtonSegment(value: 30, label: Text('30 days')),
            ButtonSegment(value: 90, label: Text('90 days')),
          ],
          selected: {_days},
          onSelectionChanged: (s) => _selectDays(s.first),
        ),
        const SizedBox(height: 16),
        ..._content(context),
      ],
    );
  }

  List<Widget> _content(BuildContext context) {
    if (_loading) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 80),
          child: LoadingView(),
        ),
      ];
    }
    if (_error != null) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: ErrorView(error: _error!, onRetry: _load),
        ),
      ];
    }
    final report = _report;
    if (report == null) {
      return [ErrorView(error: 'No data', onRetry: _load)];
    }

    return [
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.1,
        children: [
          StatTile(
            label: 'Opened',
            value: '${report.openedTotal}',
            icon: Icons.add_circle_outline,
            color: AppTheme.open,
          ),
          StatTile(
            label: 'Closed',
            value: '${report.closedTotal}',
            icon: Icons.check_circle_outline,
            color: AppTheme.closed,
          ),
          StatTile(
            label: 'Net',
            value: report.net > 0 ? '+${report.net}' : '${report.net}',
            icon: Icons.trending_up_outlined,
            color: report.net > 0 ? AppTheme.overdue : AppTheme.open,
          ),
        ],
      ),
      const SizedBox(height: 12),
      _DailyVolume(series: report.series),
    ];
  }
}

/// A per-day list: each row shows the date with two stacked proportional bars
/// (opened vs closed) and the numbers.
class _DailyVolume extends StatelessWidget {
  const _DailyVolume({required this.series});
  final List<VolumePoint> series;

  DateTime? _parse(String date) => DateTime.tryParse(date);

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: EmptyView(message: 'No volume data'),
        ),
      );
    }

    final max = series
        .fold<int>(
          1,
          (m, p) => [m, p.opened, p.closed].reduce((a, b) => a > b ? a : b),
        )
        .clamp(1, 1 << 31);

    // Most recent first.
    final ordered = series.reversed.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily volume',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _Legend(color: AppTheme.open, label: 'Opened'),
                const SizedBox(width: 16),
                _Legend(color: AppTheme.closed, label: 'Closed'),
              ],
            ),
            const SizedBox(height: 12),
            for (final p in ordered)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        Fmt.date(_parse(p.date)),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        children: [
                          _Bar(
                            value: p.opened,
                            max: max,
                            color: AppTheme.open,
                          ),
                          const SizedBox(height: 3),
                          _Bar(
                            value: p.closed,
                            max: max,
                            color: AppTheme.closed,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${p.opened} / ${p.closed}',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.max, required this.color});
  final int value;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 10,
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: (value / max).clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
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
