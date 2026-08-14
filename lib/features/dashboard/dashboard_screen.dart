import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../data/tickets_repository.dart';
import '../../models/reports.dart';
import '../../models/ticket.dart';
import '../../providers.dart';
import '../../widgets/glass.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import '../reports/widgets/activity_chart_card.dart';
import '../reports/widgets/report_summary_card.dart';
import 'widgets/attention_row.dart';
import 'widgets/count_chip_row.dart';
import 'widgets/focus_strip.dart';
import 'widgets/mini_bar_chart.dart';

/// Height of the custom greeting app bar (excludes the status-bar inset).
const double _kDashToolbar = 72;

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with SingleTickerProviderStateMixin {
  int _days = 30;
  ReportSummary? _summary;
  VolumeReport? _volume;
  Object? _error;
  bool _loading = true;
  bool _volumeLoading = false;

  /// One-time fade-and-rise reveal for the content once it first loads, echoing
  /// the sign-in screen's entrance. Created eagerly in [initState] (not lazily)
  /// so that if the screen is disposed before it's ever built — e.g. navigating
  /// away right after login while still loading — [dispose] tears down an
  /// existing controller instead of creating one against a deactivated element.
  late final AnimationController _entrance;
  late final Animation<double> _fadeIn = CurvedAnimation(
    parent: _entrance,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _riseIn =
      Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(
        CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic),
      );

  // The short "needs attention" triage list (overdue tickets, oldest first).
  // Null while loading; an empty list means "all caught up".
  List<Ticket>? _attention;

  // Task counts (derived from /tasks list totals — there is no task report
  // endpoint). Null until loaded; the Tasks section is hidden until then.
  int? _tasksOpen;
  int? _tasksOverdue;
  int? _tasksAll;
  int? _tasksClosed;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _load();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
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
      _entrance.forward(); // reveal the content (no-op once already shown)
      _loadTaskCounts();
      _loadAttention();
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

  /// Switch to the Tickets tab pre-filtered to [view].
  void _openTickets(String view) {
    ref.read(ticketsViewRequestProvider.notifier).set(view);
    context.go(Routes.tickets);
  }

  /// Switch to the Tasks tab pre-filtered to [view].
  void _openTasks(String view) {
    ref.read(tasksViewRequestProvider.notifier).set(view);
    context.go(Routes.tasks);
  }

  /// Fetch task counts in parallel (cheap list-total queries).
  Future<void> _loadTaskCounts() async {
    try {
      final repo = ref.read(tasksRepositoryProvider);
      // Only the views shown as dashboard tiles (web Tasks queue tabs).
      final totals = await Future.wait([
        repo.count(view: 'open'),
        repo.count(view: 'all'),
        repo.count(view: 'overdue'),
        repo.count(view: 'closed'),
      ]);
      if (!mounted) return;
      setState(() {
        _tasksOpen = totals[0];
        _tasksAll = totals[1];
        _tasksOverdue = totals[2];
        _tasksClosed = totals[3];
      });
    } catch (_) {
      // Leave counts null — the Tasks section simply stays hidden.
    }
  }

  /// Fetch the top few overdue tickets for the triage list. Independently
  /// fault-tolerant: on failure the list stays empty ("all caught up").
  Future<void> _loadAttention() async {
    try {
      final page = await ref
          .read(ticketsRepositoryProvider)
          .list(
            const TicketQuery(
              view: 'overdue',
              sort: 'created',
              order: 'asc',
              limit: 5,
            ),
          );
      if (!mounted) return;
      setState(() => _attention = page.items);
    } catch (_) {
      if (mounted) setState(() => _attention = const []);
    }
  }

  Widget _sectionLabel(
    String title, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => Padding(
    padding: const EdgeInsets.only(left: 4, top: 4, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: AppText.titleText(
            context,
            title,
            fw: 2,
            color: Glass.textPrimary(context),
          ),
        ),
        if (actionLabel != null && onAction != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppText.paraText(
                    context,
                    actionLabel,
                    color: Glass.link(context),
                    fw: 1,
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Glass.link(context),
                  ),
                ],
              ),
            ),
          ),
      ],
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

    final greeting = me.when(
      data: (m) {
        final first = m.name.trim().split(RegExp(r'\s+')).first;
        return first.isEmpty ? 'Hi there' : 'Hi, $first';
      },
      loading: () => 'Hi there',
      error: (_, _) => 'Hi there',
    );

    // The dark aurora canvas + glass tint are provided app-wide (see app.dart);
    // this screen floats a solid app bar and its content over the canvas.
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        toolbarHeight: _kDashToolbar,
        titleSpacing: 16,
        backgroundColor: Glass.overlayFill(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: Glass.border(context, 0.08))),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText.headText(context, greeting, fw: 2,
                color: Glass.textPrimary(context)),
            const SizedBox(height: 2),
            AppText.paraText(context, "Here's your helpdesk overview",
                color: Glass.textMuted(context)),
          ],
        ),
        // Profile avatar → the 'More' menu, now that the bottom bar's fifth
        // slot was replaced by the center create button.
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Semantics(
              button: true,
              label: 'Profile and menu',
              child: InkResponse(
                onTap: () => context.go(Routes.more),
                radius: 26,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Glass.border(context, 0.18)),
                  ),
                  child: me.maybeWhen(
                    data: (m) => UserAvatar(name: m.name, radius: 18),
                    orElse: () => CircleAvatar(
                      radius: 18,
                      backgroundColor: Glass.accent.withValues(alpha: 0.14),
                      child: Icon(Icons.person_outline,
                          size: 20, color: Glass.textMuted(context)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return _buildSkeleton(context);
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final summary = _summary;
    if (summary == null) return ErrorView(error: 'No data', onRetry: _load);

    final t = summary.totals;

    final sections = <Widget>[
      // --- Tickets focus: the three numbers that need action ----------------
      _sectionLabel(
        'Tickets',
        actionLabel: 'View all',
        onAction: () => _openTickets('open'),
      ),
      // Tiles mirror the web Tickets queue tabs exactly, in web order:
      // Open · All Tickets · My Tickets · Closed. Each tile drills into its
      // matching tab.
      FocusStrip(
        metrics: [
          FocusMetric(
            label: 'Open',
            value: t.open,
            color: AppTheme.open,
            onTap: () => _openTickets('open'),
          ),
          FocusMetric(
            label: 'All Tickets',
            value: t.total,
            color: Glass.accent,
            onTap: () => _openTickets('all'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      CountChipRow(
        chips: [
          CountChip(
            label: 'My Tickets',
            value: t.mineOpen,
            color: Glass.indigo,
            onTap: () => _openTickets('mine'),
          ),
          CountChip(
            label: 'Closed',
            value: t.closed,
            color: AppTheme.closed,
            onTap: () => _openTickets('closed'),
          ),
        ],
      ),

      // --- Needs attention: the actual actionable list ----------------------
      const SizedBox(height: 22),
      _sectionLabel(
        'Needs attention',
        actionLabel: (_attention?.isNotEmpty ?? false) ? 'View all' : null,
        onAction: (_attention?.isNotEmpty ?? false)
            ? () => _openTickets('open')
            : null,
      ),
      _attentionPanel(),

      // --- Overview: volume + activity --------------------------------------
      if (_volume != null) ...[
        const SizedBox(height: 22),
        _sectionLabel('Overview'),
        ReportSummaryCard(
          report: _volume!,
          days: _days,
          onDaysSelected: _selectDays,
          loading: _volumeLoading,
        ),
        const SizedBox(height: 12),
        ActivityChartCard(report: _volume!),
      ],

      // --- Tasks: compact chip row (differentiated from tickets focus) ------
      _tasksSection(),

      // --- Breakdown charts, grouped under one header -----------------------
      if (summary.byPriority.isNotEmpty ||
          summary.byDepartment.isNotEmpty ||
          summary.byAgent.isNotEmpty) ...[
        const SizedBox(height: 22),
        _sectionLabel('Breakdown'),
        if (summary.byPriority.isNotEmpty)
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
        if (summary.byDepartment.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Section(
            title: 'By department',
            child: MiniBarChart(
              data: [
                for (final d in summary.byDepartment)
                  (label: d.dept, value: d.open, color: Glass.indigo),
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
                  (label: a.name, value: a.open, color: Glass.accent),
              ],
            ),
          ),
        ],
      ],
    ];

    return FadeTransition(
      opacity: _fadeIn,
      child: SlideTransition(
        position: _riseIn,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            12,
            12,
            12,
            12 + MediaQuery.of(context).padding.bottom,
          ),
          children: sections,
        ),
      ),
    );
  }

  /// The bordered card holding the overdue triage rows, a loading shimmer, or
  /// the positive "all caught up" state.
  Widget _attentionPanel() {
    Widget card(Widget child) => DecoratedBox(
      decoration: BoxDecoration(
        color: Glass.surfaceFill(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Glass.border(context)),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
    );

    final list = _attention;
    if (list == null) {
      return card(
        Column(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) Divider(height: 1, color: Glass.border(context)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    SkeletonBox(width: 3, height: 34, radius: 2),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonBox(width: 90, height: 11),
                          SizedBox(height: 8),
                          SkeletonBox(height: 13),
                        ],
                      ),
                    ),
                    SizedBox(width: 10),
                    SkeletonBox(width: 52, height: 22, radius: 7),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    if (list.isEmpty) return card(const AttentionEmpty());

    return card(
      Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0) Divider(height: 1, color: Glass.border(context)),
            AttentionRow(
              ticket: list[i],
              onTap: () => context.push(Routes.ticket(list[i].id)),
            ),
          ],
        ],
      ),
    );
  }

  /// Tasks as a single compact chip row, revealed once counts load. Kept
  /// visually distinct from the tickets focus strip to avoid the old
  /// "two identical grids" repetition.
  Widget _tasksSection() {
    if (_tasksOpen == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        _sectionLabel(
          'Tasks',
          actionLabel: 'View all',
          onAction: () => _openTasks('all'),
        ),
        // Tiles mirror the web Tasks queue tabs exactly, in web order:
        // Open · All · Overdue · Completed. Each tile drills into its matching
        // tab ("Completed" is the tasks `closed` view).
        FocusStrip(
          metrics: [
            FocusMetric(
              label: 'Open',
              value: _tasksOpen ?? 0,
              color: AppTheme.open,
              onTap: () => _openTasks('open'),
            ),
            FocusMetric(
              label: 'All',
              value: _tasksAll ?? 0,
              color: Glass.accent,
              onTap: () => _openTasks('all'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        CountChipRow(
          chips: [
            CountChip(
              label: 'Overdue',
              value: _tasksOverdue ?? 0,
              color: AppTheme.overdue,
              onTap: () => _openTasks('overdue'),
            ),
            CountChip(
              label: 'Completed',
              value: _tasksClosed ?? 0,
              color: AppTheme.closed,
              onTap: () => _openTasks('closed'),
            ),
          ],
        ),
      ],
    );
  }

  /// Dashboard-shaped shimmer shown during the initial load, mirroring the new
  /// layout (focus strip → chips → attention list) so nothing jumps when data
  /// arrives.
  Widget _buildSkeleton(BuildContext context) {
    Widget bordered(Widget child, {double h = 0}) => Container(
      height: h == 0 ? null : h,
      decoration: BoxDecoration(
        color: Glass.surfaceFill(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Glass.border(context)),
      ),
      child: child,
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, top: 4, bottom: 10),
          child: SkeletonBox(width: 90, height: 16),
        ),
        bordered(const SizedBox.shrink(), h: 92),
        const SizedBox(height: 10),
        Row(
          children: const [
            SkeletonBox(width: 92, height: 34, radius: 10),
            SizedBox(width: 8),
            SkeletonBox(width: 110, height: 34, radius: 10),
            SizedBox(width: 8),
            SkeletonBox(width: 92, height: 34, radius: 10),
          ],
        ),
        const SizedBox(height: 22),
        const Padding(
          padding: EdgeInsets.only(left: 4, top: 4, bottom: 10),
          child: SkeletonBox(width: 130, height: 16),
        ),
        bordered(
          Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) Divider(height: 1, color: Glass.border(context)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      SkeletonBox(width: 3, height: 34, radius: 2),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 90, height: 11),
                            SizedBox(height: 8),
                            SkeletonBox(height: 13),
                          ],
                        ),
                      ),
                      SizedBox(width: 10),
                      SkeletonBox(width: 52, height: 22, radius: 7),
                    ],
                  ),
                ),
              ],
            ],
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
            AppText.subText(context, title, fw: 1),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
