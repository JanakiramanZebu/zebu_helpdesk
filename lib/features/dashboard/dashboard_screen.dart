import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../models/reports.dart';
import '../../providers.dart';
import '../../widgets/states.dart';
import 'widgets/mini_bar_chart.dart';
import 'widgets/stat_tile.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  ReportSummary? _summary;
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
      final summary = await ref.read(reportsRepositoryProvider).summary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
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

  /// Priority bar color, mirroring StatusChip.priority semantics.
  Color _priorityColor(String priority) {
    final p = priority.toLowerCase();
    if (p.contains('emergency') || p.contains('high')) return AppTheme.overdue;
    if (p.contains('low')) return AppTheme.closed;
    return AppTheme.warning;
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final unread = ref.watch(unreadCountProvider);

    final greeting = me.when(
      data: (m) {
        final first = m.name.trim().split(RegExp(r'\s+')).first;
        return first.isEmpty ? 'Hi' : 'Hi, $first';
      },
      loading: () => 'Dashboard',
      error: (_, _) => 'Dashboard',
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dashboard'),
            Text(greeting, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          _NotificationBell(
            count: unread.maybeWhen(data: (c) => c, orElse: () => 0),
            onTap: () => context.push(Routes.notifications),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final summary = _summary;
    if (summary == null) return ErrorView(error: 'No data', onRetry: _load);

    final t = summary.totals;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.1,
          children: [
            StatTile(
              label: 'Open',
              value: '${t.open}',
              icon: Icons.inbox_outlined,
              color: AppTheme.open,
              onTap: () => context.push(Routes.tickets),
            ),
            StatTile(
              label: 'Unassigned',
              value: '${t.unassigned}',
              icon: Icons.person_off_outlined,
              color: AppTheme.warning,
              onTap: () => context.push(Routes.tickets),
            ),
            StatTile(
              label: 'Overdue',
              value: '${t.overdue}',
              icon: Icons.schedule_outlined,
              color: AppTheme.overdue,
              onTap: () => context.push(Routes.tickets),
            ),
            StatTile(
              label: 'Mine Open',
              value: '${t.mineOpen}',
              icon: Icons.assignment_ind_outlined,
              color: AppTheme.brand,
            ),
            StatTile(
              label: 'Answered',
              value: '${t.answered}',
              icon: Icons.mark_email_read_outlined,
              color: AppTheme.open,
            ),
            StatTile(
              label: 'Closed',
              value: '${t.closed}',
              icon: Icons.check_circle_outline,
              color: AppTheme.closed,
            ),
          ],
        ),
        if (summary.byPriority.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Section(
            title: 'By priority',
            child: MiniBarChart(
              data: [
                for (final p in summary.byPriority)
                  (
                    label: p.priority,
                    value: p.open,
                    color: _priorityColor(p.priority),
                  ),
              ],
            ),
          ),
        ],
        if (summary.byDepartment.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Section(
            title: 'By department',
            child: MiniBarChart(
              data: [
                for (final d in summary.byDepartment)
                  (label: d.dept, value: d.open, color: AppTheme.brand),
              ],
            ),
          ),
        ],
        if (summary.byAgent.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Section(
            title: 'By agent',
            child: MiniBarChart(
              data: [
                for (final a in summary.byAgent.take(8))
                  (label: a.name, value: a.open, color: AppTheme.brandDark),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: const Text('View full reports'),
            subtitle: const Text('Daily opened vs closed volume'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.reports),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: onTap,
        ),
        if (count > 0)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: AppTheme.overdue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
