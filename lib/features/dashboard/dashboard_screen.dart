import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/assets.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../models/reports.dart';
import '../../providers.dart';
import '../../widgets/states.dart';
import '../../widgets/svg_icon.dart';
import '../reports/widgets/activity_chart_card.dart';
import '../reports/widgets/report_summary_card.dart';
import 'widgets/mini_bar_chart.dart';
import 'widgets/stat_tile.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _days = 30;
  ReportSummary? _summary;
  VolumeReport? _volume;
  Object? _error;
  bool _loading = true;
  bool _volumeLoading = false;

  // Task counts (derived from /tasks list totals — there is no task report
  // endpoint). Null until loaded; the Tasks section is hidden until then.
  int? _tasksOpen;
  int? _tasksMine;
  int? _tasksOverdue;
  int? _tasksCollaborator;
  int? _tasksAll;
  int? _tasksClosed;

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
      final repo = ref.read(reportsRepositoryProvider);
      final results = await Future.wait([
        repo.summary(),
        repo.volume(days: _days),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as ReportSummary;
        _volume = results[1] as VolumeReport;
        _loading = false;
      });
      _loadTaskCounts();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Reload only the volume report (the activity section) so changing the day
  /// range never flashes the whole-screen loader.
  Future<void> _reloadVolume() async {
    setState(() => _volumeLoading = true);
    try {
      final volume = await ref
          .read(reportsRepositoryProvider)
          .volume(days: _days);
      if (!mounted) return;
      setState(() {
        _volume = volume;
        _volumeLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _volumeLoading = false);
    }
  }

  void _selectDays(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _reloadVolume();
  }

  /// Switch to the Tickets tab pre-filtered to [view] (one of the ticket
  /// list's filter keys: open / unassigned / overdue / mine / answered /
  /// closed).
  void _openTickets(String view) {
    ref.read(ticketsViewRequestProvider.notifier).set(view);
    context.go(Routes.tickets);
  }

  /// Switch to the Tasks tab pre-filtered to [view] (open / mine / overdue /
  /// closed).
  void _openTasks(String view) {
    ref.read(tasksViewRequestProvider.notifier).set(view);
    context.go(Routes.tasks);
  }

  /// Fetch task counts in parallel (cheap list-total queries). Non-blocking and
  /// independently fault-tolerant, so a task failure never breaks the rest of
  /// the dashboard.
  Future<void> _loadTaskCounts() async {
    try {
      final repo = ref.read(tasksRepositoryProvider);
      final totals = await Future.wait([
        repo.count(view: 'open'),
        repo.count(view: 'mine'),
        repo.count(view: 'overdue'),
        repo.count(view: 'collaborator'),
        repo.count(view: 'all'),
        repo.count(view: 'closed'),
      ]);
      if (!mounted) return;
      setState(() {
        _tasksOpen = totals[0];
        _tasksMine = totals[1];
        _tasksOverdue = totals[2];
        _tasksCollaborator = totals[3];
        _tasksAll = totals[4];
        _tasksClosed = totals[5];
      });
    } catch (_) {
      // Leave counts null — the Tasks section simply stays hidden.
    }
  }

  Widget _sectionLabel(String title) => Padding(
    padding: const EdgeInsets.only(left: 4, top: 4, bottom: 10),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

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

    final theme = Theme.of(context);
    final greeting = me.when(
      data: (m) {
        final first = m.name.trim().split(RegExp(r'\s+')).first;
        return first.isEmpty ? 'Hi there' : 'Hi, $first';
      },
      loading: () => 'Hi there',
      error: (_, _) => 'Hi there',
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 16,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Here's your helpdesk overview",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          _NotificationBell(
            count: unread.maybeWhen(data: (c) => c, orElse: () => 0),
            onTap: () => context.push(Routes.notifications),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
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
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        _sectionLabel('Tickets'),
        SizedBox(
          height: 250,
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.5,
            children: [
              StatTile(
                label: 'Open',
                value: Fmt.count(t.open),
                icon: Icons.inbox_outlined,
                color: AppTheme.open,
                onTap: () => _openTickets('open'),
              ),
              StatTile(
                label: 'Unassigned',
                value: Fmt.count(t.unassigned),
                icon: Icons.person_off_outlined,
                color: AppTheme.warning,
                onTap: () => _openTickets('unassigned'),
              ),
              StatTile(
                label: 'Overdue',
                value: Fmt.count(t.overdue),
                icon: Icons.schedule_outlined,
                color: AppTheme.overdue,
                onTap: () => _openTickets('overdue'),
              ),
              StatTile(
                label: 'Mine Open',
                value: Fmt.count(t.mineOpen),
                icon: Icons.assignment_ind_outlined,
                color: AppTheme.brand,
                onTap: () => _openTickets('mine'),
              ),
              StatTile(
                label: 'Answered',
                value: Fmt.count(t.answered),
                icon: Icons.mark_email_read_outlined,
                color: AppTheme.open,
                onTap: () => _openTickets('answered'),
              ),
              StatTile(
                label: 'Closed',
                value: Fmt.count(t.closed),
                icon: Icons.check_circle_outline,
                color: AppTheme.closed,
                onTap: () => _openTickets('closed'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_volume != null) ...[
          ReportSummaryCard(
            report: _volume!,
            days: _days,
            onDaysSelected: _selectDays,
            loading: _volumeLoading,
          ),
          const SizedBox(height: 12),
          ActivityChartCard(report: _volume!),
        ],
        if (_tasksOpen != null) ...[
          const SizedBox(height: 20),
          _sectionLabel('Tasks'),
          SizedBox(
            height: 250,
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.5,
              children: [
                StatTile(
                  label: 'Open',
                  value: Fmt.count(_tasksOpen ?? 0),
                  icon: Icons.radio_button_unchecked,
                  color: AppTheme.open,
                  onTap: () => _openTasks('open'),
                ),
                StatTile(
                  label: 'Mine',
                  value: Fmt.count(_tasksMine ?? 0),
                  icon: Icons.assignment_ind_outlined,
                  color: AppTheme.brand,
                  onTap: () => _openTasks('mine'),
                ),
                StatTile(
                  label: 'Overdue',
                  value: Fmt.count(_tasksOverdue ?? 0),
                  icon: Icons.schedule_outlined,
                  color: AppTheme.overdue,
                  onTap: () => _openTasks('overdue'),
                ),
                StatTile(
                  label: 'Collaborator',
                  value: Fmt.count(_tasksCollaborator ?? 0),
                  icon: Icons.groups_outlined,
                  color: AppTheme.warning,
                  onTap: () => _openTasks('collaborator'),
                ),
                StatTile(
                  label: 'All',
                  value: Fmt.count(_tasksAll ?? 0),
                  icon: Icons.all_inbox_outlined,
                  color: AppTheme.brandDark,
                  onTap: () => _openTasks('all'),
                ),
                StatTile(
                  label: 'Closed',
                  value: Fmt.count(_tasksClosed ?? 0),
                  icon: Icons.task_alt,
                  color: AppTheme.closed,
                  onTap: () => _openTasks('closed'),
                ),
              ],
            ),
          ),
        ],
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
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
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
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onTap,
      tooltip: 'Notifications',
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          SvgIcon(Assets.bell, size: 22),
          if (count > 0)
            Positioned(
              top: -5,
              right: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 17),
                decoration: BoxDecoration(
                  color: AppTheme.overdue,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: scheme.surface, width: 1.5),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
