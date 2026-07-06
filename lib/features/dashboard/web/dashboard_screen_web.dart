import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/router/routes.dart';
import '../../../data/tickets_repository.dart';
import '../../../models/reports.dart';
import '../../../models/ticket.dart';
import '../../../providers.dart';
import '../../../widgets/slide_over_host.dart';
import '../../../widgets/states.dart';
import '../../../widgets/user_avatar.dart';
import '../../../widgets/web/kpi_tile.dart';
import '../../../widgets/web/premium_card.dart';
import '../../../widgets/web/status_pill.dart';
import '../../reports/widgets/activity_line_chart.dart';
import '../../tasks/web/task_detail_panel.dart';
import '../../tickets/web/ticket_detail_panel.dart';
import '_tokens.dart';

/// Web-only dashboard.
///
/// Data sources mirror the mobile `DashboardScreen`
/// ([reportsRepositoryProvider], [tasksRepositoryProvider]) — only the
/// visual language differs. The layout composes three reusable web
/// primitives:
///
///   * [KpiTile] — vertical stat cards for the top row;
///   * [PremiumCard] — flat, hairline-bordered surface for every card;
///   * an inline responsive KPI grid (4 / 2 / 1 columns) driven by
///     [LayoutBuilder] so the top row breathes correctly on any width.
class DashboardScreenWeb extends ConsumerStatefulWidget {
  const DashboardScreenWeb({super.key});

  @override
  ConsumerState<DashboardScreenWeb> createState() =>
      _DashboardScreenWebState();
}

class _DashboardScreenWebState extends ConsumerState<DashboardScreenWeb> {
  int _days = 30;
  ReportSummary? _summary;
  VolumeReport? _volume;
  Object? _error;
  bool _loading = true;
  bool _volumeLoading = false;

  int? _tasksOpen;
  int? _tasksMine;
  int? _tasksOverdue;
  int? _tasksCollaborator;
  int? _tasksAll;
  int? _tasksClosed;

  // Recent tickets shown in the "My Projects"-style table on the dashboard.
  // Fetched once per `_load`; independent from the sidebar counts.
  List<Ticket> _recentTickets = const [];

  // Slide-over panel state — dashboard rows open the same detail panels the
  // Tickets / Tasks / Inbox pages use, so the sidebar stays visible.
  int? _openTicketId;
  int? _openTaskId;

  void _openTicket(int id) => setState(() {
        _openTicketId = id;
        _openTaskId = null;
      });
  // Closing the panel is a pure state change — do NOT refetch the dashboard.
  // Pull-to-refresh (or opening the item again) will pick up any mutation.
  void _closeTicket() => setState(() => _openTicketId = null);
  void _closeTask() => setState(() => _openTaskId = null);

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
      final ticketsRepo = ref.read(ticketsRepositoryProvider);
      // Task counts fetched in parallel with the main dashboard payload so
      // the Tasks Overview card appears in sync with the rest — no post-
      // render "empty then fills in" gap. `_fetchTaskCounts` swallows its
      // own errors and returns null so a task-endpoint hiccup doesn't take
      // down the whole dashboard.
      final results = await Future.wait([
        repo.summary(),
        repo.volume(days: _days),
        ticketsRepo.list(
          // 6 rows so the Recent Tickets card lines up in height with the
          // sibling Tasks Overview card (which shows 6 view rows).
          const TicketQuery(
            view: 'open',
            sort: 'created',
            order: 'desc',
            limit: 6,
          ),
        ),
        _fetchTaskCounts(),
      ]);
      if (!mounted) return;
      final taskTotals = results[3] as List<int>?;
      setState(() {
        _summary = results[0] as ReportSummary;
        _volume = results[1] as VolumeReport;
        // ignore: avoid_dynamic_calls
        _recentTickets = (results[2] as dynamic).items as List<Ticket>;
        if (taskTotals != null && taskTotals.length == 6) {
          _tasksOpen = taskTotals[0];
          _tasksMine = taskTotals[1];
          _tasksOverdue = taskTotals[2];
          _tasksCollaborator = taskTotals[3];
          _tasksAll = taskTotals[4];
          _tasksClosed = taskTotals[5];
        }
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

  Future<List<int>?> _fetchTaskCounts() async {
    try {
      final repo = ref.read(tasksRepositoryProvider);
      return await Future.wait([
        repo.count(view: 'open'),
        repo.count(view: 'mine'),
        repo.count(view: 'overdue'),
        repo.count(view: 'collaborator'),
        repo.count(view: 'all'),
        repo.count(view: 'closed'),
      ]);
    } catch (_) {
      return null;
    }
  }

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

  void _openTickets(String view) {
    ref.read(ticketsViewRequestProvider.notifier).set(view);
    context.go(Routes.tickets);
  }

  void _openTasks(String view) {
    ref.read(tasksViewRequestProvider.notifier).set(view);
    context.go(Routes.tasks);
  }

  String _greetingText() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _dateLabel() {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    // Nested slide-over hosts (tickets outer, tasks inner) so opening either
    // detail keeps the dashboard content visible on the left. Only one is
    // open at a time — `_openTicket` clears `_openTaskId` and vice versa.
    return SlideOverHost(
      openId: _openTicketId,
      onClose: _closeTicket,
      panelBuilder: (context, id, close) =>
          TicketDetailPanel(ticketId: id, onClose: close),
      child: SlideOverHost(
        openId: _openTaskId,
        onClose: _closeTask,
        panelBuilder: (context, id, close) =>
            TaskDetailPanel(taskId: id, onClose: close),
        child: ColoredBox(color: t.bgPrimary, child: _buildBody(context, t)),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WebTokens t) {
    if (_loading) return const _DashboardSkeleton();
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final summary = _summary;
    if (summary == null) return ErrorView(error: 'No data', onRetry: _load);

    final me = ref.watch(meProvider);
    final firstName = me.maybeWhen(
      data: (m) {
        final n = m.name.trim().split(RegExp(r'\s+')).first;
        return n.isEmpty ? 'there' : n;
      },
      orElse: () => 'there',
    );

    final totals = summary.totals;

    // 4 KPI tiles across the top — the primary read for the dashboard.
    // Each tile carries a `denominator` so the tile can render its
    // "N of M" context strip at the bottom — surfaces real ratios from the
    // summary payload that were previously fetched but never displayed.
    final kpis = <_KpiData>[
      _KpiData(
        svg: _kSvgOpenTickets,
        value: totals.open,
        label: 'Open Tickets',
        tone: WebTokens.success,
        onTap: () => _openTickets('open'),
        denominator: totals.total,
        denominatorLabel: 'total',
      ),
      _KpiData(
        svg: _kSvgOverdueTickets,
        value: totals.overdue,
        label: 'Overdue Tickets',
        tone: WebTokens.danger,
        onTap: () => _openTickets('overdue'),
        denominator: totals.open,
        denominatorLabel: 'open',
      ),
      _KpiData(
        svg: _kSvgMyTasks,
        value: _tasksMine ?? 0,
        label: 'My Tasks',
        tone: WebTokens.accent,
        onTap: () => _openTasks('mine'),
        denominator: _tasksAll,
        denominatorLabel: 'all',
      ),
      _KpiData(
        svg: _kSvgOverdueTasks,
        value: _tasksOverdue ?? 0,
        label: 'Overdue Tasks',
        tone: WebTokens.warning,
        onTap: () => _openTasks('overdue'),
        denominator: _tasksAll,
        denominatorLabel: 'all',
      ),
    ];

    final taskRows = _tasksOpen == null
        ? <_OverviewRow>[]
        : <_OverviewRow>[
            (
              name: 'All',
              value: _tasksAll ?? 0,
              onTap: () => _openTasks('all'),
            ),
            (
              name: 'Open',
              value: _tasksOpen ?? 0,
              onTap: () => _openTasks('open'),
            ),
            (
              name: 'Mine',
              value: _tasksMine ?? 0,
              onTap: () => _openTasks('mine'),
            ),
            (
              name: 'Overdue',
              value: _tasksOverdue ?? 0,
              onTap: () => _openTasks('overdue'),
            ),
            (
              name: 'Collaborator',
              value: _tasksCollaborator ?? 0,
              onTap: () => _openTasks('collaborator'),
            ),
            (
              name: 'Closed',
              value: _tasksClosed ?? 0,
              onTap: () => _openTasks('closed'),
            ),
          ];

    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Two-column middle row above ~1100 px, stacked below it.
          final wide = constraints.maxWidth >= 1100;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: WebTokens.s10,
              vertical: WebTokens.s6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Hero(
                  dateLabel: _dateLabel(),
                  greeting: '${_greetingText()}, $firstName',
                  mineOpen: summary.totals.mineOpen,
                ),
                const SizedBox(height: WebTokens.s6),

                // --- KPI grid ---------------------------------------------
                _KpiGrid(items: kpis),
                const SizedBox(height: WebTokens.s6),

                // --- Workload row (surfaces summary.byPriority /
                //     .byDepartment — real data the app was already
                //     fetching but not showing anywhere else). Hidden
                //     entirely when both are empty so an empty account
                //     doesn't render a placeholder shell.
                if (summary.byPriority.isNotEmpty ||
                    summary.byDepartment.isNotEmpty) ...[
                  _WorkloadRow(
                    priorities: summary.byPriority,
                    departments: summary.byDepartment,
                    onSeeAll: () => _openTickets('open'),
                  ),
                  const SizedBox(height: WebTokens.s6),
                ],

                // --- Middle row: Recent Tickets (left) + Tasks (right) ----
                // IntrinsicHeight + stretch → both cards match the taller
                // card's intrinsic height. Recent Tickets carries a column
                // header, so it's usually the taller of the two; Tasks
                // Overview stretches to fill, giving a balanced pair
                // instead of a lopsided gap under one card.
                if (wide)
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 2,
                          child: _RecentTicketsCard(
                            tickets: _recentTickets,
                            onRowTap: _openTicket,
                            onSeeAll: () => _openTickets('open'),
                          ),
                        ),
                        const SizedBox(width: WebTokens.s5),
                        Expanded(
                          flex: 1,
                          child: taskRows.isEmpty
                              ? const SizedBox.shrink()
                              : _TasksListCard(
                                  rows: taskRows,
                                  onSeeAll: () => _openTasks('open'),
                                ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  _RecentTicketsCard(
                    tickets: _recentTickets,
                    onRowTap: _openTicket,
                    onSeeAll: () => _openTickets('open'),
                  ),
                  if (taskRows.isNotEmpty) ...[
                    const SizedBox(height: WebTokens.s5),
                    _TasksListCard(
                      rows: taskRows,
                      onSeeAll: () => _openTasks('open'),
                    ),
                  ],
                ],

                // --- Activity chart --------------------------------------
                if (_volume != null) ...[
                  const SizedBox(height: WebTokens.s5),
                  _ActivityCard(
                    report: _volume!,
                    days: _days,
                    onDaysSelected: _selectDays,
                    loading: _volumeLoading,
                  ),
                ],

                const SizedBox(height: WebTokens.s10),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero — time-based greeting + full weekday date
// ---------------------------------------------------------------------------

class _Hero extends ConsumerWidget {
  const _Hero({
    required this.dateLabel,
    required this.greeting,
    required this.mineOpen,
  });
  final String dateLabel;
  final String greeting;

  /// Tickets currently open + assigned to me. When > 0 the hero shows a
  /// small "N assigned to me" chip alongside the greeting.
  final int mineOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = WebTokens.of(context);
    final unread = ref.watch(unreadCountProvider).maybeWhen(
          data: (c) => c,
          orElse: () => 0,
        );
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 640;
        final heroBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(dateLabel, style: t.sectionCaps),
            const SizedBox(height: 8),
            // Bumped hero size: 30 px / w700 / tighter tracking so the
            // greeting owns the top of the dashboard.
            Text(
              greeting,
              style: t.hero.copyWith(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                height: 1.15,
              ),
            ),
          ],
        );
        final chips = <Widget>[
          if (mineOpen > 0)
            _HeroChip(
              icon: Icons.person_outline_rounded,
              count: mineOpen,
              label: 'assigned to you',
              tone: WebTokens.accent,
            ),
          if (unread > 0)
            _HeroChip(
              icon: Icons.notifications_none_rounded,
              count: unread,
              label: 'unread',
              tone: WebTokens.info,
            ),
        ];
        if (chips.isEmpty) return heroBlock;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heroBlock,
              const SizedBox(height: WebTokens.s3),
              Wrap(
                spacing: WebTokens.s2,
                runSpacing: WebTokens.s2,
                children: chips,
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: heroBlock),
            Wrap(
              spacing: WebTokens.s2,
              runSpacing: WebTokens.s2,
              alignment: WrapAlignment.end,
              children: chips,
            ),
          ],
        );
      },
    );
  }
}

/// Premium hero pill — used in the top-right of the greeting to surface
/// live "N assigned to you" / "N unread" counts.
///
/// Structure: white surface with a hairline border and a whisper shadow
/// (matches [PremiumCard]'s lift), a **tone-tinted circular icon badge** on
/// the left, a **bold count in the tone color**, and a **muted-secondary
/// label** trailing. Reads as one composed unit rather than the earlier
/// flat "colored word on a colored tint" chip.
class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.count,
    required this.label,
    required this.tone,
  });
  final IconData icon;
  final int count;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
      decoration: BoxDecoration(
        color: t.bgElevated,
        borderRadius: BorderRadius.circular(WebTokens.rFull),
        border: Border.all(color: t.borderSubtle, width: 1),
        boxShadow: WebTokens.shadowXs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(
                color: tone.withValues(alpha: 0.22),
                width: 1,
              ),
            ),
            child: Icon(icon, size: 13, color: tone),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: tone,
              height: 1.2,
              letterSpacing: -0.2,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: t.textSecondary,
              height: 1.2,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KPI grid — 4 / 2 / 1 columns depending on available width. Uses fixed
// column-count math (LayoutBuilder + evenly split widths) so the tiles line
// up in a proper grid instead of drifting on a `Wrap`.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// KPI icon SVGs — inline strings rendered by [KpiTile] via [SvgPicture.string]
// with a tone-tinted [ColorFilter.mode], so the source fill/stroke color is
// ignored (any monochrome SVG paints correctly in the tile's tone).
//
// TODO(svg): swap these placeholders for the final Zebu KPI icons. Keep the
// `viewBox="0 0 24 24"` frame and monochrome paths — the tile paints them at
// 16×16 tinted to the tile's tone.
// ---------------------------------------------------------------------------

const String _kSvgOpenTickets = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
     stroke="currentColor" stroke-width="1.75" stroke-linecap="round"
     stroke-linejoin="round">
  <path d="M4 8a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v2a2 2 0 0 0 0 4v2a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-2a2 2 0 0 0 0-4z"/>
  <path d="M12 8v8" stroke-dasharray="1.5 2.5"/>
</svg>
''';

const String _kSvgOverdueTickets = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
     stroke="currentColor" stroke-width="1.75" stroke-linecap="round"
     stroke-linejoin="round">
  <path d="M10.3 3.7 1.8 18.3A2 2 0 0 0 3.5 21.3h17A2 2 0 0 0 22.2 18.3L13.7 3.7a2 2 0 0 0-3.4 0z"/>
  <path d="M12 9v5"/>
  <path d="M12 17.5h.01"/>
</svg>
''';

const String _kSvgMyTasks = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
     stroke="currentColor" stroke-width="1.75" stroke-linecap="round"
     stroke-linejoin="round">
  <path d="M22 11.1V12a10 10 0 1 1-5.9-9.1"/>
  <path d="m9 11 3 3L22 4"/>
</svg>
''';

const String _kSvgOverdueTasks = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"
     stroke="currentColor" stroke-width="1.75" stroke-linecap="round"
     stroke-linejoin="round">
  <circle cx="12" cy="12" r="9"/>
  <path d="M12 7v5l3 2"/>
</svg>
''';

class _KpiData {
  const _KpiData({
    required this.svg,
    required this.value,
    required this.label,
    required this.tone,
    required this.onTap,
    this.denominator,
    this.denominatorLabel,
  });
  final String svg;
  final int value;
  final String label;
  final Color tone;
  final VoidCallback onTap;

  /// Parent-group total the tile renders its ratio strip against
  /// (e.g. `totals.total` for the Open Tickets tile). Null hides the strip.
  final int? denominator;

  /// Short suffix on the ratio caption (`'total'`, `'open'`, `'all'`).
  final String? denominatorLabel;
}

// ---------------------------------------------------------------------------
// Workload row — two side-by-side cards surfacing the `byPriority` and
// `byDepartment` slices of `ReportSummary`. These come back on every
// dashboard load and were previously ignored; showing them here gives the
// user a real "where is the workload sitting?" view without a second API
// call. Empty slices collapse gracefully so a low-volume account never
// sees a stub card.
// ---------------------------------------------------------------------------

class _WorkloadRow extends StatelessWidget {
  const _WorkloadRow({
    required this.priorities,
    required this.departments,
    required this.onSeeAll,
  });
  final List<PriorityBucket> priorities;
  final List<DepartmentBucket> departments;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final priorityCard = priorities.isEmpty
        ? const SizedBox.shrink()
        : _PriorityWorkloadCard(
            priorities: priorities,
            onSeeAll: onSeeAll,
          );
    final deptCard = departments.isEmpty
        ? const SizedBox.shrink()
        : _DepartmentLoadCard(
            departments: departments,
            onSeeAll: onSeeAll,
          );

    // Only one card present → render full-width alone (no lopsided layout).
    if (priorities.isEmpty) return deptCard;
    if (departments.isEmpty) return priorityCard;

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        if (wide) {
          // IntrinsicHeight + stretch → both cards match the taller card's
          // intrinsic height so the workload row reads as a single balanced
          // pair. Shorter card gets extra whitespace at the bottom instead
          // of a lopsided gap in the layout.
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: priorityCard),
                const SizedBox(width: WebTokens.s5),
                Expanded(child: deptCard),
              ],
            ),
          );
        }
        return Column(
          children: [
            priorityCard,
            const SizedBox(height: WebTokens.s5),
            deptCard,
          ],
        );
      },
    );
  }
}

class _PriorityWorkloadCard extends StatelessWidget {
  const _PriorityWorkloadCard({
    required this.priorities,
    required this.onSeeAll,
  });
  final List<PriorityBucket> priorities;
  final VoidCallback onSeeAll;

  static Color _tone(String name) {
    final n = name.toLowerCase();
    if (n.contains('emergency') || n.contains('high')) return WebTokens.danger;
    if (n.contains('low')) return WebTokens.success;
    return WebTokens.warning;
  }

  @override
  Widget build(BuildContext context) {
    // Sort by descending open count so the largest bucket sits at top.
    final sorted = [...priorities]
      ..sort((a, b) => b.open.compareTo(a.open));
    final total = sorted.fold<int>(0, (acc, p) => acc + p.open);
    final peak = sorted.isEmpty ? 1 : sorted.first.open;

    return PremiumCard(
      title: 'Priority Workload',
      subtitle: '$total open tickets across ${sorted.length} priorities',
      trailing: _SeeAllLink(onTap: onSeeAll),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WebTokens.s5,
          vertical: WebTokens.s3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final bucket in sorted)
              _PriorityRow(
                bucket: bucket,
                tone: _tone(bucket.priority),
                fraction: peak == 0 ? 0 : bucket.open / peak,
              ),
          ],
        ),
      ),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({
    required this.bucket,
    required this.tone,
    required this.fraction,
  });
  final PriorityBucket bucket;
  final Color tone;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              bucket.priority.isEmpty ? '—' : bucket.priority,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodyBase.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: t.bgTertiary,
                borderRadius: BorderRadius.circular(WebTokens.rFull),
              ),
              child: FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: tone,
                    borderRadius: BorderRadius.circular(WebTokens.rFull),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 36,
            child: Text(
              Fmt.count(bucket.open),
              textAlign: TextAlign.right,
              style: t.bodyBase
                  .copyWith(
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  )
                  .withTabularNums(),
            ),
          ),
        ],
      ),
    );
  }
}

class _DepartmentLoadCard extends StatelessWidget {
  const _DepartmentLoadCard({
    required this.departments,
    required this.onSeeAll,
  });
  final List<DepartmentBucket> departments;
  final VoidCallback onSeeAll;

  static const int _maxRows = 6;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    // Sort by descending open count so the busiest team sits at top; cap at
    // 6 rows so a large helpdesk doesn't stretch the card to a wall of text.
    final sorted = [...departments]
      ..sort((a, b) => b.open.compareTo(a.open));
    final visible = sorted.take(_maxRows).toList();
    final overflow = sorted.length - visible.length;

    return PremiumCard(
      title: 'Department Load',
      subtitle: '${sorted.length} teams · open · overdue',
      trailing: _SeeAllLink(onTap: onSeeAll),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < visible.length; i++) ...[
            if (i > 0) Container(height: 1, color: t.borderSubtle),
            _DepartmentRow(bucket: visible[i]),
          ],
          if (overflow > 0)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WebTokens.s5,
                vertical: WebTokens.s3,
              ),
              child: Text(
                'and $overflow more…',
                style: t.bodySm.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}

class _DepartmentRow extends StatelessWidget {
  const _DepartmentRow({required this.bucket});
  final DepartmentBucket bucket;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s5,
        vertical: WebTokens.s4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              bucket.dept.isEmpty ? '—' : bucket.dept,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodyBase.copyWith(
                fontWeight: FontWeight.w500,
                color: t.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: WebTokens.s3),
          _CountPill(
            label: '${Fmt.count(bucket.open)} open',
            color: WebTokens.success,
          ),
          if (bucket.overdue > 0) ...[
            const SizedBox(width: 6),
            _CountPill(
              label: '${Fmt.count(bucket.overdue)} overdue',
              color: WebTokens.danger,
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact tinted count pill used in the Department Load rows.
/// Compact metric pill used in the Department Load rows ("13 open",
/// "2 overdue"). Same tint + hairline treatment as [StatusPill] for visual
/// coherence, but no leading dot — the label already carries a count so a
/// dot would over-mark it.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(WebTokens.s1),
        border: Border.all(
          color: color.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
          height: 1.3,
          letterSpacing: 0.1,
        ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.items});
  final List<_KpiData> items;

  static const double _gap = WebTokens.s4;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w >= 1000 ? 4 : (w >= 640 ? 2 : 1);
        final tileWidth = (w - _gap * (cols - 1)) / cols;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final item in items)
              SizedBox(
                width: tileWidth,
                child: KpiTile(
                  svg: item.svg,
                  value: Fmt.count(item.value),
                  label: item.label,
                  tone: item.tone,
                  onTap: item.onTap,
                  current: item.value,
                  denominator: item.denominator,
                  denominatorLabel: item.denominatorLabel,
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// "See all" link — small brand-blue text. Underlines on hover so the
// affordance is legible without a persistent underline in the resting state.
// ---------------------------------------------------------------------------

class _SeeAllLink extends StatefulWidget {
  const _SeeAllLink({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_SeeAllLink> createState() => _SeeAllLinkState();
}

class _SeeAllLinkState extends State<_SeeAllLink> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          'See all',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: WebTokens.accent,
            decoration:
                _hover ? TextDecoration.underline : TextDecoration.none,
            decorationColor: WebTokens.accent,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent Tickets card — a [PremiumCard] wrapping a compact 3-column table.
// ---------------------------------------------------------------------------

class _RecentTicketsCard extends StatelessWidget {
  const _RecentTicketsCard({
    required this.tickets,
    required this.onRowTap,
    required this.onSeeAll,
  });

  final List<Ticket> tickets;
  final ValueChanged<int> onRowTap;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return PremiumCard(
      title: 'Recent Tickets',
      trailing: _SeeAllLink(onTap: onSeeAll),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Column-header strip with vertical dividers between each cell.
          // Matches the ClickUp task-list header rhythm — thin hairlines
          // that carry down through the body rows via matching per-cell
          // borders on `_TicketRow`.
          Container(
            color: t.bgElevated,
            child: const IntrinsicHeight(
              child: Row(
                children: [
                  _HeaderCell(flex: 3, label: 'Name'),
                  _HeaderCell(flex: 1, label: 'Assignee'),
                  _HeaderCell(width: 140, label: 'Status'),
                  _HeaderCell(width: 130, label: 'Priority', last: true),
                ],
              ),
            ),
          ),
          Container(height: 1, color: t.borderSubtle),

          // Body — intrinsic height so 6 tighter rows sit naturally under
          // the header. The parent `IntrinsicHeight` on the middle row of
          // `_buildBody` syncs the total card height to the sibling Tasks
          // Overview card.
          if (tickets.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: WebTokens.s8),
              child: Center(
                child: Text('No recent tickets', style: t.bodySm),
              ),
            )
          else
            for (int i = 0; i < tickets.length; i++) ...[
              if (i > 0) Container(height: 1, color: t.borderSubtle),
              _TicketRow(
                ticket: tickets[i],
                onTap: () => onRowTap(tickets[i].id),
              ),
            ],
        ],
      ),
    );
  }
}

/// Column-header cell — small caps label sat in the tinted header strip,
/// with an optional right divider so all header cells match the vertical
/// hairlines drawn by the body rows.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    this.flex,
    this.width,
    this.last = false,
  });
  final String label;
  final int? flex;
  final double? width;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s3,
        vertical: WebTokens.s3,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                right: BorderSide(color: t.borderSubtle, width: 1),
              ),
      ),
      alignment: Alignment.centerLeft,
      child: Text(label, style: t.tableHeader),
    );
    if (flex != null) return Expanded(flex: flex!, child: content);
    if (width != null) return SizedBox(width: width!, child: content);
    return content;
  }
}

class _TicketRow extends StatefulWidget {
  const _TicketRow({required this.ticket, required this.onTap});
  final Ticket ticket;
  final VoidCallback onTap;

  @override
  State<_TicketRow> createState() => _TicketRowState();
}

class _TicketRowState extends State<_TicketRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final overdue = widget.ticket.isOverdue;
    // Since the Due column is gone, overdue tickets need a visual cue that
    // reads at a glance across the whole card. A 3 px accent stripe on the
    // left edge does the job without adding chrome: red on overdue rows,
    // accent-blue on hover, transparent otherwise (kept in the layout so
    // row content never shifts horizontally).
    final Color stripeColor;
    if (overdue) {
      stripeColor = WebTokens.danger;
    } else if (_hover) {
      stripeColor = WebTokens.accent;
    } else {
      stripeColor = Colors.transparent;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgElevated,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  width: 3,
                  color: stripeColor,
                ),
                _BodyCell(
                  flex: 3,
                  child: Row(
                    children: [
                      Text(
                        '#${widget.ticket.number}',
                        style: t.bodySm
                            .copyWith(
                              fontWeight: FontWeight.w600,
                              color: WebTokens.accent,
                            )
                            .withTabularNums(),
                      ),
                      const SizedBox(width: WebTokens.s2),
                      Flexible(
                        child: Text(
                          widget.ticket.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyBase
                              .copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                _BodyCell(
                  flex: 1,
                  child: _AssigneeCell(assignee: widget.ticket.assignee),
                ),
                _BodyCell(
                  width: 140,
                  child: _StatusTag(ticket: widget.ticket),
                ),
                _BodyCell(
                  width: 130,
                  last: true,
                  child: _PriorityCell(priority: widget.ticket.priority),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Body cell — tighter vertical rhythm (10 px) than the previous 16 px
/// padded row, with a right hairline that matches the header divider so
/// the ticket table reads as a proper grid instead of a wall of flowing
/// text. Set [last] true for the trailing cell so the row doesn't grow a
/// stray edge divider.
class _BodyCell extends StatelessWidget {
  const _BodyCell({
    required this.child,
    this.flex,
    this.width,
    this.last = false,
  });
  final Widget child;
  final int? flex;
  final double? width;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s3,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                right: BorderSide(color: t.borderSubtle, width: 1),
              ),
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
    if (flex != null) return Expanded(flex: flex!, child: content);
    if (width != null) return SizedBox(width: width!, child: content);
    return content;
  }
}


/// Priority cell — wears the same [StatusPill] treatment as the status
/// column so priority + status read as one visual family. The flag glyph
/// replaces the leading dot to keep the "priority ≠ status" affordance.
class _PriorityCell extends StatelessWidget {
  const _PriorityCell({required this.priority});
  final String? priority;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final name = (priority ?? '').trim();
    if (name.isEmpty) {
      return Text('—', style: t.bodySm);
    }
    return StatusPill(
      label: _titleCase(name),
      color: _tone(name),
      icon: Icons.flag_rounded,
    );
  }

  static Color _tone(String name) {
    final n = name.toLowerCase();
    if (n.contains('emergency') || n.contains('urgent')) return WebTokens.danger;
    if (n.contains('high')) return WebTokens.warning;
    if (n.contains('low')) return WebTokens.success;
    if (n.contains('normal')) return WebTokens.info;
    return WebTokens.info;
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}

/// Assignee cell in the Recent Tickets table — a [UserAvatar]-style
/// initial circle (deterministic color per name, same palette as elsewhere
/// in the app) followed by the assignee's name. Renders a compact
/// "Unassigned" placeholder with a dashed neutral circle when no one owns
/// the ticket yet.
///
/// Mirrors the "avatar + name" pattern the reference dashboards
/// (Asana / ClickUp) use in their assignee columns.
class _AssigneeCell extends StatelessWidget {
  const _AssigneeCell({required this.assignee});
  final String? assignee;

  static const double _avatarSize = 22.0;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final name = (assignee ?? '').trim();
    if (name.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _avatarSize,
            height: _avatarSize,
            decoration: BoxDecoration(
              color: t.bgTertiary,
              shape: BoxShape.circle,
              border: Border.all(color: t.borderDefault, width: 1),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.person_outline_rounded,
              size: 12,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Unassigned',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySm.copyWith(
                color: t.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        UserAvatar(name: name, radius: _avatarSize / 2),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySm.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Premium status pill — resolves the ticket's semantic tone (open /
/// closed / unassigned / overdue) and renders via [StatusPill] so the tag
/// gets the shared dot-indicator treatment.
class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final label =
        ticket.isOverdue ? 'Overdue' : _titleCase(ticket.statusName);
    return StatusPill(label: label, color: _fg(t));
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  Color _fg(WebTokens t) {
    if (ticket.isOverdue) return WebTokens.danger;
    final s = ticket.statusName.toLowerCase();
    if (s.contains('closed') || s.contains('resolved')) return t.textSecondary;
    // "Unassigned" is a passive waiting state — read it as calm info-blue,
    // not alarming amber. Amber is reserved for genuinely warning states
    // (overdue-soon, at-risk) so it retains its "attention needed" meaning.
    if (s.contains('unassigned')) return WebTokens.info;
    if (s.contains('open')) return WebTokens.success;
    return WebTokens.info;
  }
}

// ---------------------------------------------------------------------------
// Tasks Overview card — a [PremiumCard] listing task views with counts.
// ---------------------------------------------------------------------------

typedef _OverviewRow = ({String name, int value, VoidCallback onTap});

class _TasksListCard extends StatelessWidget {
  const _TasksListCard({required this.rows, required this.onSeeAll});
  final List<_OverviewRow> rows;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return PremiumCard(
      title: 'Tasks Overview',
      trailing: _SeeAllLink(onTap: onSeeAll),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) Container(height: 1, color: t.borderSubtle),
            _OverviewListRow(row: rows[i]),
          ],
        ],
      ),
    );
  }
}

class _OverviewListRow extends StatefulWidget {
  const _OverviewListRow({required this.row});
  final _OverviewRow row;

  @override
  State<_OverviewListRow> createState() => _OverviewListRowState();
}

class _OverviewListRowState extends State<_OverviewListRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.row.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgElevated,
          ),
          // Vertical padding matches the tighter Recent Tickets `_BodyCell`
          // (10 px) so the two cards share the same row rhythm at 6 rows.
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s5,
            vertical: 10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  widget.row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyBase.copyWith(
                    fontWeight: FontWeight.w500,
                    color: t.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: WebTokens.s2),
              Text(
                Fmt.count(widget.row.value),
                style: t.bodyBase
                    .copyWith(
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    )
                    .withTabularNums(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity card — combined metric strip + chart + range picker
// ---------------------------------------------------------------------------

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.report,
    required this.days,
    required this.onDaysSelected,
    required this.loading,
  });

  final VolumeReport report;
  final int days;
  final ValueChanged<int> onDaysSelected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final span = report.days == 0 ? 1 : report.days;
    final avgOpened = report.openedTotal / span;
    final avgClosed = report.closedTotal / span;
    final net = report.net;

    return PremiumCard(
      title: 'Ticket Activity',
      dividerAfterHeader: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: t.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
          ],
          _RangeToggle(days: days, onSelected: onDaysSelected),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WebTokens.s5,
          WebTokens.s3,
          WebTokens.s5,
          WebTokens.s5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Metric(
                  value: Fmt.count(report.openedTotal),
                  label: 'OPENED',
                  tone: WebTokens.success,
                ),
                _VDivider(color: t.borderSubtle),
                _Metric(
                  value: Fmt.count(report.closedTotal),
                  label: 'CLOSED',
                  tone: t.textSecondary,
                ),
                _VDivider(color: t.borderSubtle),
                _Metric(
                  value: net > 0 ? '+${Fmt.count(net)}' : Fmt.count(net),
                  label: 'NET',
                  tone: net > 0 ? WebTokens.danger : WebTokens.success,
                ),
              ],
            ),
            const SizedBox(height: WebTokens.s3),
            Text(
              'Avg ${avgOpened.toStringAsFixed(1)} opened · '
              '${avgClosed.toStringAsFixed(1)} closed per day',
              style: t.bodySm,
            ),
            const SizedBox(height: WebTokens.s5),
            if (report.series.isEmpty)
              SizedBox(
                height: 180,
                child: Center(
                  child:
                      Text('No activity in this range', style: t.bodySm),
                ),
              )
            else
              ActivityLineChart(
                height: 220,
                dates: [
                  for (final p in report.series) DateTime.tryParse(p.date),
                ],
                series: [
                  ChartSeries(
                    label: 'Opened',
                    color: WebTokens.success,
                    values: [
                      for (final p in report.series) p.opened.toDouble(),
                    ],
                  ),
                  ChartSeries(
                    label: 'Closed',
                    color: t.textSecondary,
                    values: [
                      for (final p in report.series) p.closed.toDouble(),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.tone,
  });
  final String value;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: t.valueLarge(tone)),
          const SizedBox(height: WebTokens.s1),
          Text(label, style: t.tinyLabel),
        ],
      ),
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: WebTokens.s5),
      color: color,
    );
  }
}

// ---------------------------------------------------------------------------
// Range toggle — segmented pill group (single tinted bg, one segment lifted).
// Feels less like three separate buttons and more like a real segmented
// control, matching the ClickUp reference's inline widgets.
// ---------------------------------------------------------------------------

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.days, required this.onSelected});
  final int days;
  final ValueChanged<int> onSelected;

  static const _options = [7, 30, 90];

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.bgTertiary,
        borderRadius: BorderRadius.circular(WebTokens.rSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final opt in _options)
            _RangeSegment(
              label: '${opt}D',
              active: opt == days,
              onTap: () => onSelected(opt),
            ),
        ],
      ),
    );
  }
}

class _RangeSegment extends StatelessWidget {
  const _RangeSegment({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: active ? t.bgElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(WebTokens.rXs),
            boxShadow: active ? WebTokens.shadowSm : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? t.textPrimary : t.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard skeleton — placeholder layout shown while the initial data fetch
// is in flight. Mirrors the real screen's rhythm (hero → KPI grid → recent
// tickets + tasks overview → activity chart) so the swap to real content is
// visually calm.
// ---------------------------------------------------------------------------

const _kSkelRadius = WebTokens.rLg;

BoxDecoration _skelCard(WebTokens t) => BoxDecoration(
      color: t.bgElevated,
      borderRadius: BorderRadius.circular(_kSkelRadius),
      border: Border.all(color: t.borderSubtle, width: 1),
    );

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return ColoredBox(
      color: t.bgPrimary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1100;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: WebTokens.s10,
              vertical: WebTokens.s6,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero
                const _SkelBar(width: 140, height: 12),
                const SizedBox(height: 6),
                const _SkelBar(width: 320, height: 26),
                const SizedBox(height: WebTokens.s6),

                // 4 KPI tiles
                LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final cols = w >= 1000 ? 4 : (w >= 640 ? 2 : 1);
                    const gap = WebTokens.s4;
                    final tileWidth = (w - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: List.generate(
                        4,
                        (_) => SizedBox(
                          width: tileWidth,
                          child: const _SkelKpiTile(),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: WebTokens.s6),

                // Middle row
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Expanded(flex: 2, child: _SkelRecentTicketsCard()),
                      SizedBox(width: WebTokens.s5),
                      Expanded(flex: 1, child: _SkelTasksCard()),
                    ],
                  )
                else ...const [
                  _SkelRecentTicketsCard(),
                  SizedBox(height: WebTokens.s5),
                  _SkelTasksCard(),
                ],

                const SizedBox(height: WebTokens.s5),
                const _SkelActivityCard(),
                const SizedBox(height: WebTokens.s10),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Shimmering rectangle — the single primitive every skeleton block is built
/// from. Uses a repeating linear-gradient sweep synced across instances by
/// each instance's own controller.
class _SkelBar extends StatefulWidget {
  const _SkelBar({required this.width, required this.height, this.radius = 4});
  final double width;
  final double height;
  final double radius;

  @override
  State<_SkelBar> createState() => _SkelBarState();
}

class _SkelBarState extends State<_SkelBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Sweep from left (-1) to right (+1) as the value moves 0 → 1.
        final dx = (_c.value * 2) - 1;
        return Container(
          width: widget.width == double.infinity ? null : widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(dx - 0.8, 0),
              end: Alignment(dx + 0.8, 0),
              colors: [t.bgTertiary, t.borderSubtle, t.bgTertiary],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );
  }
}

class _SkelKpiTile extends StatelessWidget {
  const _SkelKpiTile();

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      decoration: _skelCard(t),
      padding: const EdgeInsets.all(WebTokens.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: const [
          _SkelBar(width: 34, height: 34, radius: WebTokens.rSm),
          SizedBox(height: WebTokens.s3),
          _SkelBar(width: 60, height: 22),
          SizedBox(height: 6),
          _SkelBar(width: 100, height: 12),
        ],
      ),
    );
  }
}

class _SkelCardHeader extends StatelessWidget {
  const _SkelCardHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTokens.s5,
        WebTokens.s4,
        WebTokens.s5,
        WebTokens.s3,
      ),
      child: Row(
        children: const [
          _SkelBar(width: 26, height: 26, radius: WebTokens.rSm),
          SizedBox(width: 10),
          _SkelBar(width: 130, height: 14),
          Spacer(),
          _SkelBar(width: 56, height: 12),
        ],
      ),
    );
  }
}

class _SkelRecentTicketsCard extends StatelessWidget {
  const _SkelRecentTicketsCard();

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      decoration: _skelCard(t),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SkelCardHeader(),
          Container(height: 1, color: t.borderSubtle),

          // Column headers strip
          Container(
            padding: const EdgeInsets.fromLTRB(
              WebTokens.s5,
              WebTokens.s3,
              WebTokens.s5,
              WebTokens.s3,
            ),
            color: t.bgTertiary,
            child: Row(
              children: const [
                Expanded(flex: 3, child: _SkelBar(width: 60, height: 11)),
                Expanded(flex: 1, child: _SkelBar(width: 60, height: 11)),
                SizedBox(width: 130, child: _SkelBar(width: 56, height: 11)),
                SizedBox(width: 78, child: _SkelBar(width: 40, height: 11)),
                SizedBox(width: 92, child: _SkelBar(width: 60, height: 11)),
              ],
            ),
          ),
          Container(height: 1, color: t.borderSubtle),

          for (int i = 0; i < 5; i++) ...[
            if (i > 0) Container(height: 1, color: t.borderSubtle),
            const _SkelTicketRow(),
          ],
        ],
      ),
    );
  }
}

class _SkelTicketRow extends StatelessWidget {
  const _SkelTicketRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s5,
        vertical: WebTokens.s4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: const [
                _SkelBar(width: 52, height: 13),
                SizedBox(width: WebTokens.s2),
                Expanded(child: _SkelBar(width: double.infinity, height: 13)),
              ],
            ),
          ),
          const Expanded(
            flex: 1,
            child: Row(
              children: [
                _SkelBar(width: 22, height: 22, radius: 11),
                SizedBox(width: 8),
                Expanded(child: _SkelBar(width: double.infinity, height: 13)),
              ],
            ),
          ),
          const SizedBox(
            width: 130,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _SkelBar(width: 90, height: 18, radius: WebTokens.rXs),
            ),
          ),
          const SizedBox(
            width: 78,
            child: _SkelBar(width: 60, height: 13),
          ),
          const SizedBox(
            width: 92,
            child: Row(
              children: [
                _SkelBar(width: 13, height: 13),
                SizedBox(width: 5),
                Expanded(child: _SkelBar(width: double.infinity, height: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkelTasksCard extends StatelessWidget {
  const _SkelTasksCard();

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      decoration: _skelCard(t),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SkelCardHeader(),
          Container(height: 1, color: t.borderSubtle),
          for (int i = 0; i < 6; i++) ...[
            if (i > 0) Container(height: 1, color: t.borderSubtle),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WebTokens.s5,
                vertical: WebTokens.s4,
              ),
              child: Row(
                children: const [
                  Expanded(child: _SkelBar(width: 120, height: 13)),
                  SizedBox(width: WebTokens.s2),
                  _SkelBar(width: 24, height: 13),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkelActivityCard extends StatelessWidget {
  const _SkelActivityCard();

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      decoration: _skelCard(t),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SkelCardHeader(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTokens.s5,
              WebTokens.s3,
              WebTokens.s5,
              WebTokens.s5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SkelBar(width: 80, height: 24),
                          SizedBox(height: 6),
                          _SkelBar(width: 60, height: 11),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SkelBar(width: 80, height: 24),
                          SizedBox(height: 6),
                          _SkelBar(width: 60, height: 11),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SkelBar(width: 80, height: 24),
                          SizedBox(height: 6),
                          _SkelBar(width: 60, height: 11),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: WebTokens.s3),
                const _SkelBar(width: 260, height: 12),
                const SizedBox(height: WebTokens.s5),
                const _SkelBar(width: double.infinity, height: 220),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
