import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/assets.dart';
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
import '../../../widgets/web/status_badge.dart';
import '../../../widgets/web/status_pill.dart';
import '../../reports/widgets/activity_line_chart.dart';
import '../../tasks/web/create_task_screen_web.dart';
import '../../tasks/web/task_detail_panel.dart';
import '../../tickets/web/create_ticket_screen_web.dart';
import '../../tickets/web/ticket_detail_panel.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';
import '../../../res/zebu_text_styles.dart';

/// Web-only dashboard.
///
/// Data sources mirror the mobile `DashboardScreen`
/// ([reportsRepositoryProvider], [tasksRepositoryProvider]) — only the
/// visual language differs. The layout is a max-width, single-column
/// composition (Linear / ClickUp reference) built from reusable web
/// primitives:
///
///   * [KpiTile] — premium stat cards for the top row;
///   * [PremiumCard] — hairline-bordered surface for every card;
///   * responsive grids driven by [LayoutBuilder] so every band breathes
///     correctly from 1280 px up to ultra-wide.
class DashboardScreenWeb extends ConsumerStatefulWidget {
  const DashboardScreenWeb({super.key});

  @override
  ConsumerState<DashboardScreenWeb> createState() => _DashboardScreenWebState();
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
    final t = ZebuTheme.of(context);
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

  Widget _buildBody(BuildContext context, ZebuTheme t) {
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
        svgAsset: Assets.navTickets,
        value: totals.open,
        label: 'Open Tickets',
        tone: ZebuTheme.success,
        onTap: () => _openTickets('open'),
        denominator: totals.total,
        denominatorLabel: 'total',
      ),
      _KpiData(
        svg: _kSvgOverdueTickets,
        value: totals.overdue,
        label: 'Overdue Tickets',
        tone: t.danger,
        onTap: () => _openTickets('overdue'),
        denominator: totals.open,
        denominatorLabel: 'open',
      ),
      _KpiData(
        svg: _kSvgMyTasks,
        svgAsset: Assets.navTasks,
        value: _tasksMine ?? 0,
        label: 'My Tasks',
        tone: t.accent,
        onTap: () => _openTasks('mine'),
        denominator: _tasksAll,
        denominatorLabel: 'all',
      ),
      _KpiData(
        svg: _kSvgOverdueTasks,
        value: _tasksOverdue ?? 0,
        label: 'Overdue Tasks',
        tone: ZebuTheme.warning,
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
              tone: t.accent,
              onTap: () => _openTasks('all'),
            ),
            (
              name: 'Open',
              value: _tasksOpen ?? 0,
              tone: ZebuTheme.success,
              onTap: () => _openTasks('open'),
            ),
            (
              name: 'Mine',
              value: _tasksMine ?? 0,
              tone: ZebuTheme.indigo,
              onTap: () => _openTasks('mine'),
            ),
            (
              name: 'Overdue',
              value: _tasksOverdue ?? 0,
              tone: t.danger,
              onTap: () => _openTasks('overdue'),
            ),
            (
              name: 'Collaborator',
              value: _tasksCollaborator ?? 0,
              tone: ZebuTheme.warning,
              onTap: () => _openTasks('collaborator'),
            ),
            (
              name: 'Closed',
              value: _tasksClosed ?? 0,
              tone: const Color(0xFF737373),
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
              horizontal: ZebuSpacing.s6,
              vertical: ZebuSpacing.s5,
            ),
            // Content fills the workspace on standard desktops (up to ~1900);
            // the 1800 cap only engages on ultra-wide (2000 px+) monitors so
            // the single-column page never sprawls to an unreadable width.
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Hero(
                      dateLabel: _dateLabel(),
                      greeting: '${_greetingText()}, $firstName',
                      mineOpen: summary.totals.mineOpen,
                      onNewTicket: () => showCreateTicketDialog(context),
                      onNewTask: () => showCreateTaskDialog(context),
                    ),
                    const SizedBox(height: ZebuSpacing.s4),

                    // --- KPI grid -----------------------------------------
                    _KpiGrid(items: kpis),
                    const SizedBox(height: ZebuSpacing.s4),

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
                      const SizedBox(height: ZebuSpacing.s4),
                    ],

                    // --- Middle row: Recent Tickets (left) + Tasks (right) -
                    // IntrinsicHeight + stretch → both cards match the taller
                    // card's intrinsic height for a balanced pair.
                    if (wide)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 5,
                              child: _RecentTicketsCard(
                                tickets: _recentTickets,
                                onRowTap: _openTicket,
                                onSeeAll: () => _openTickets('open'),
                              ),
                            ),
                            const SizedBox(width: ZebuSpacing.s4),
                            Expanded(
                              flex: 3,
                              child: taskRows.isEmpty
                                  ? const SizedBox.shrink()
                                  : _TasksOverviewCard(
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
                        const SizedBox(height: ZebuSpacing.s4),
                        _TasksOverviewCard(
                          rows: taskRows,
                          onSeeAll: () => _openTasks('open'),
                        ),
                      ],
                    ],

                    // --- Activity chart -----------------------------------
                    if (_volume != null) ...[
                      const SizedBox(height: ZebuSpacing.s4),
                      _ActivityCard(
                        report: _volume!,
                        days: _days,
                        onDaysSelected: _selectDays,
                        loading: _volumeLoading,
                      ),
                    ],

                    const SizedBox(height: ZebuSpacing.s10),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero — time-based greeting, full weekday date, a live "what needs you"
// subline, and real quick-action buttons (New task / New ticket). We do NOT
// surface a global search box or workspace switcher here: the backend has no
// search endpoint and the app has no workspace concept, so those would be
// non-functional chrome. Notifications live in the shell top bar; the hero
// instead pulls the two counts that matter (assigned to you / unread) into
// one honest sentence.
// ---------------------------------------------------------------------------

class _Hero extends ConsumerWidget {
  const _Hero({
    required this.dateLabel,
    required this.greeting,
    required this.mineOpen,
    required this.onNewTicket,
    required this.onNewTask,
  });
  final String dateLabel;
  final String greeting;

  /// Tickets currently open + assigned to me. Feeds the hero subline.
  final int mineOpen;

  final VoidCallback onNewTicket;
  final VoidCallback onNewTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ZebuTheme.of(context);
    final unread = ref
        .watch(unreadCountProvider)
        .maybeWhen(data: (c) => c, orElse: () => 0);

    final subline = _subline(mineOpen, unread);

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 720;
        final heroBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: t.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  dateLabel.toUpperCase(),
                  style: ZebuTextStyles.eyebrow(context),
                ),
              ],
            ),
            const SizedBox(height: ZebuSpacing.s3),
            // Page title — 32 px, semibold (not bold) per the design system's
            // "medium & semibold over bold" rule.
            Text(
              greeting,
              style: ZebuTextStyles.hero(context).copyWith(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.8,
                height: 1.1,
              ),
            ),
            const SizedBox(height: ZebuSpacing.s3),
            _Subline(spans: subline),
          ],
        );

        // final actions = _HeroActions(
        //   onNewTicket: onNewTicket,
        //   onNewTask: onNewTask,
        // );

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heroBlock,
              // const SizedBox(height: ZebuSpacing.s4),
              // actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: heroBlock),
            // const SizedBox(width: ZebuSpacing.s4),
            // actions,
          ],
        );
      },
    );
  }

  /// Builds the "N assigned to you · M unread" segments as tone-tagged spans
  /// so the counts can render bold/accented inside a muted sentence.
  List<_SublineSpan> _subline(int mine, int unread) {
    final out = <_SublineSpan>[];
    if (mine > 0) {
      out.add(_SublineSpan(count: mine, label: 'assigned to you'));
    }
    if (unread > 0) {
      out.add(_SublineSpan(count: unread, label: 'unread updates'));
    }
    return out;
  }
}

class _SublineSpan {
  const _SublineSpan({required this.count, required this.label});
  final int count;
  final String label;
}

class _Subline extends StatelessWidget {
  const _Subline({required this.spans});
  final List<_SublineSpan> spans;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    if (spans.isEmpty) {
      return Text(
        "You're all caught up. Nothing needs you right now.",
        style: ZebuTextStyles.body(context).copyWith(color: t.textSecondary),
      );
    }
    final children = <InlineSpan>[
      TextSpan(
        text: 'You have ',
        style: ZebuTextStyles.body(context).copyWith(color: t.textSecondary),
      ),
    ];
    for (var i = 0; i < spans.length; i++) {
      final s = spans[i];
      children.add(
        TextSpan(
          text: Fmt.count(s.count),
          style: ZebuTextStyles.body(
            context,
          ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w600),
        ),
      );
      children.add(
        TextSpan(
          text: ' ${s.label}',
          style: ZebuTextStyles.body(context).copyWith(color: t.textSecondary),
        ),
      );
      if (i < spans.length - 2) {
        children.add(
          TextSpan(
            text: ', ',
            style: ZebuTextStyles.body(
              context,
            ).copyWith(color: t.textSecondary),
          ),
        );
      } else if (i == spans.length - 2) {
        children.add(
          TextSpan(
            text: ' and ',
            style: ZebuTextStyles.body(
              context,
            ).copyWith(color: t.textSecondary),
          ),
        );
      }
    }
    children.add(
      TextSpan(
        text: '.',
        style: ZebuTextStyles.body(context).copyWith(color: t.textSecondary),
      ),
    );
    return Text.rich(TextSpan(children: children));
  }
}

/// Hero quick actions — a secondary "New task" and a primary accent-filled
/// "New ticket". Both reuse the existing create dialogs, so this adds no new
/// behaviour, just a faster on-ramp than reaching for the sidebar.
class _HeroActions extends StatelessWidget {
  const _HeroActions({required this.onNewTicket, required this.onNewTask});
  final VoidCallback onNewTicket;
  final VoidCallback onNewTask;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeroActionButton(
          label: 'New task',
          icon: Icons.check_circle_outline_rounded,
          onTap: onNewTask,
          primary: false,
        ),
        const SizedBox(width: ZebuSpacing.s2),
        _HeroActionButton(
          label: 'New ticket',
          icon: Icons.add_rounded,
          onTap: onNewTicket,
          primary: true,
        ),
      ],
    );
  }
}

class _HeroActionButton extends StatefulWidget {
  const _HeroActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.primary,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_HeroActionButton> createState() => _HeroActionButtonState();
}

class _HeroActionButtonState extends State<_HeroActionButton> {
  bool _hover = false;
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final primary = widget.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        // Pressed state — a subtle scale-in so the button acknowledges the
        // click, in addition to the hover elevation.
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s5),
            decoration: BoxDecoration(
              // Flat accent fill for the primary action — no gradient, matching
              // the app's flat-CTA language and the "avoid heavy gradients"
              // design goal. Hover deepens the fill in the same family so the
              // AnimatedContainer lerps color→color.
              color: primary
                  ? (_hover ? t.accentHover : t.accent)
                  : (_hover ? t.bgHover : t.bgElevated),
              borderRadius: BorderRadius.circular(ZebuRadius.rMd),
              border: primary
                  ? null
                  : Border.all(color: t.borderDefault, width: 1),
              boxShadow: primary
                  ? (_hover ? ZebuElevation.shadowMd : ZebuElevation.shadowSm)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: primary ? Colors.white : t.textSecondary,
                ),
                const SizedBox(width: ZebuSpacing.s2),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: primary ? Colors.white : t.textPrimary,
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KPI icon SVGs — inline strings rendered by [KpiTile] via [SvgPicture.string]
// with a tone-tinted [ColorFilter.mode], so the source fill/stroke color is
// ignored (any monochrome SVG paints correctly in the tile's tone).
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
    this.svgAsset,
    required this.value,
    required this.label,
    required this.tone,
    required this.onTap,
    this.denominator,
    this.denominatorLabel,
  });
  final String svg;

  /// Mobile icon-set asset; takes precedence over the inline [svg] literal.
  final String? svgAsset;
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
// KPI grid — 4 / 2 / 1 columns depending on available width.
// ---------------------------------------------------------------------------

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.items});
  final List<_KpiData> items;

  static const double _gap = ZebuSpacing.s3;

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
                  svgAsset: item.svgAsset,
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
// Workload row — two side-by-side cards surfacing the `byPriority` and
// `byDepartment` slices of `ReportSummary`.
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
        : _PriorityWorkloadCard(priorities: priorities, onSeeAll: onSeeAll);
    final deptCard = departments.isEmpty
        ? const SizedBox.shrink()
        : _DepartmentLoadCard(departments: departments, onSeeAll: onSeeAll);

    // Only one card present → render full-width alone (no lopsided layout).
    if (priorities.isEmpty) return deptCard;
    if (departments.isEmpty) return priorityCard;

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        if (wide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: priorityCard),
                const SizedBox(width: ZebuSpacing.s4),
                Expanded(child: deptCard),
              ],
            ),
          );
        }
        return Column(
          children: [
            priorityCard,
            const SizedBox(height: ZebuSpacing.s5),
            deptCard,
          ],
        );
      },
    );
  }
}

Color _priorityTone(String name, ZebuTheme t) {
  final n = name.toLowerCase();
  if (n.contains('emergency') || n.contains('urgent')) return t.danger;
  if (n.contains('high')) return ZebuTheme.warning;
  if (n.contains('low')) return ZebuTheme.success;
  if (n.contains('normal')) return t.accent;
  return t.accent;
}

class _PriorityWorkloadCard extends StatelessWidget {
  const _PriorityWorkloadCard({
    required this.priorities,
    required this.onSeeAll,
  });
  final List<PriorityBucket> priorities;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    // Sort by descending open count so the largest bucket sits at top.
    final sorted = [...priorities]..sort((a, b) => b.open.compareTo(a.open));
    final total = sorted.fold<int>(0, (acc, p) => acc + p.open);

    return PremiumCard(
      title: 'Priority Workload',
      subtitle: '$total open tickets across ${sorted.length} priorities',
      trailing: _SeeAllLink(onTap: onSeeAll),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ZebuSpacing.s5,
          ZebuSpacing.s4,
          ZebuSpacing.s5,
          ZebuSpacing.s5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Composition bar — a single stacked track showing how the open
            // workload splits by priority. The modern "horizontal viz" the
            // brief asked for: one glance = the whole distribution.
            _CompositionBar(
              segments: [
                for (final b in sorted)
                  if (b.open > 0)
                    _Segment(
                      value: b.open,
                      color: _priorityTone(b.priority, t),
                    ),
              ],
              total: total,
            ),
            const SizedBox(height: ZebuSpacing.s5),
            for (final bucket in sorted)
              _PriorityRow(
                bucket: bucket,
                tone: _priorityTone(bucket.priority, t),
                share: total == 0 ? 0 : bucket.open / total,
              ),
          ],
        ),
      ),
    );
  }
}

class _Segment {
  const _Segment({required this.value, required this.color});
  final int value;
  final Color color;
}

/// Stacked horizontal bar showing a set of tone-colored segments summing to
/// [total]. Rounded outer corners, hairline gaps between segments.
class _CompositionBar extends StatelessWidget {
  const _CompositionBar({required this.segments, required this.total});
  final List<_Segment> segments;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    if (segments.isEmpty || total == 0) {
      return Container(
        height: 10,
        decoration: BoxDecoration(
          color: t.bgTertiary,
          borderRadius: BorderRadius.circular(ZebuRadius.rFull),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(ZebuRadius.rFull),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: segments[i].value,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 400 + i * 90),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => Opacity(
                    opacity: v,
                    child: ColoredBox(color: segments[i].color),
                  ),
                ),
              ),
            ],
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
    required this.share,
  });
  final PriorityBucket bucket;
  final Color tone;
  final double share;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              bucket.priority.isEmpty ? '—' : bucket.priority,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZebuTextStyles.body(
                context,
              ).copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${(share * 100).round()}%',
            style: ZebuTextStyles.caption(
              context,
            ).copyWith(color: t.textSecondary),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 40,
            child: Text(
              Fmt.count(bucket.open),
              textAlign: TextAlign.right,
              style: ZebuTextStyles.body(context)
                  .copyWith(fontWeight: FontWeight.w600, color: t.textPrimary)
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
    // Sort by descending open count so the busiest team sits at top; cap at
    // 6 rows so a large helpdesk doesn't stretch the card to a wall of text.
    final sorted = [...departments]..sort((a, b) => b.open.compareTo(a.open));
    final visible = sorted.take(_maxRows).toList();
    final overflow = sorted.length - visible.length;
    final peak = visible.isEmpty ? 1 : visible.first.open;

    return PremiumCard(
      title: 'Department Load',
      subtitle: '${sorted.length} teams · open & overdue',
      trailing: _SeeAllLink(onTap: onSeeAll),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ZebuSpacing.s5,
          ZebuSpacing.s2,
          ZebuSpacing.s5,
          ZebuSpacing.s3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final bucket in visible)
              _DepartmentRow(
                bucket: bucket,
                fraction: peak == 0 ? 0 : bucket.open / peak,
              ),
            if (overflow > 0)
              Padding(
                padding: const EdgeInsets.only(top: ZebuSpacing.s2),
                child: Text(
                  'and $overflow more teams…',
                  style: ZebuTextStyles.small(
                    context,
                  ).copyWith(fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DepartmentRow extends StatelessWidget {
  const _DepartmentRow({required this.bucket, required this.fraction});
  final DepartmentBucket bucket;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final name = bucket.dept.isEmpty ? '—' : bucket.dept;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ZebuSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          UserAvatar(name: name, radius: 15),
          const SizedBox(width: ZebuSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ZebuTextStyles.body(context).copyWith(
                          fontWeight: FontWeight.w500,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: ZebuSpacing.s2),
                    _CountPill(
                      label: '${Fmt.count(bucket.open)} open',
                      color: ZebuTheme.success,
                    ),
                    if (bucket.overdue > 0) ...[
                      const SizedBox(width: 6),
                      _CountPill(
                        label: '${Fmt.count(bucket.overdue)} overdue',
                        color: t.danger,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                // Relative-load bar — this team's open volume against the
                // busiest team, so the row reads "how loaded" at a glance.
                ClipRRect(
                  borderRadius: BorderRadius.circular(ZebuRadius.rFull),
                  child: Container(
                    height: 5,
                    color: t.bgTertiary,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: fraction.clamp(0.0, 1.0) == 0
                            ? 0.0001
                            : fraction.clamp(0.0, 1.0),
                        child: Container(color: t.accent),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact tinted count pill used in the Department Load rows ("13 open",
/// "2 overdue"). Same tint + hairline treatment as [StatusPill] for visual
/// coherence, but no leading dot — the label already carries a count.
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
        borderRadius: BorderRadius.circular(ZebuRadius.rXs),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 1),
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

// ---------------------------------------------------------------------------
// "See all" link — small brand-blue text with a chevron. Underlines on hover.
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
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'See all',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: t.accent,
                decoration: _hover
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: t.accent,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 16, color: t.accent),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent Tickets card — a [PremiumCard] wrapping a clean, gridline-free table
// with sticky-feeling header, hover rows, colored status + priority pills,
// and a hover-revealed open affordance.
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
    final t = ZebuTheme.of(context);
    return PremiumCard(
      title: 'Recent Tickets',
      subtitle: 'Latest open tickets across your desk',
      trailing: _SeeAllLink(onTap: onSeeAll),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Column-header strip — no vertical gridlines (Asana-clean), just a
          // tinted background so it reads as a header band.
          Container(
            color: t.bgTertiary.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(
              horizontal: ZebuSpacing.s5,
              vertical: ZebuSpacing.s3,
            ),
            child: const Row(
              children: [
                _HeaderCell(flex: 5, label: 'Ticket'),
                _HeaderCell(flex: 2, label: 'Assignee'),
                _HeaderCell(width: 118, label: 'Status'),
                _HeaderCell(width: 110, label: 'Priority'),
                SizedBox(width: 24),
              ],
            ),
          ),
          Container(height: 1, color: t.borderSubtle),

          if (tickets.isEmpty)
            const _RecentTicketsEmpty()
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

/// Beautiful empty state for the Recent Tickets table.
class _RecentTicketsEmpty extends StatelessWidget {
  const _RecentTicketsEmpty();

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s5,
        vertical: ZebuSpacing.s10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ZebuTheme.success.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(ZebuRadius.rLg),
            ),
            child: const Icon(
              Icons.inbox_rounded,
              size: 24,
              color: ZebuTheme.success,
            ),
          ),
          const SizedBox(height: ZebuSpacing.s3),
          Text(
            'No open tickets',
            style: ZebuTextStyles.smallStrong(
              context,
            ).copyWith(color: t.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'New tickets will show up here as they arrive.',
            textAlign: TextAlign.center,
            style: ZebuTextStyles.small(context),
          ),
        ],
      ),
    );
  }
}

/// Column-header cell — small caps label; no dividers (clean table look).
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, this.flex, this.width});
  final String label;
  final int? flex;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final content = Align(
      alignment: Alignment.centerLeft,
      child: Text(label, style: ZebuTextStyles.tableHeader(context)),
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

  static const double _rowHeight = 46;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final overdue = widget.ticket.isOverdue;
    // Left edge accent: red on overdue, accent-blue on hover, transparent
    // otherwise (kept in the layout so content never shifts horizontally).
    final Color stripeColor;
    if (overdue) {
      stripeColor = t.danger;
    } else if (_hover) {
      stripeColor = t.accent;
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
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          height: _rowHeight,
          decoration: BoxDecoration(color: _hover ? t.bgHover : t.bgElevated),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: 3,
                height: _rowHeight,
                color: stripeColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ZebuSpacing.s5 - 3,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Row(
                          children: [
                            Text(
                              '#${widget.ticket.number}',
                              style: ZebuTextStyles.small(context)
                                  .copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: t.accent,
                                  )
                                  .withTabularNums(),
                            ),
                            const SizedBox(width: ZebuSpacing.s2),
                            Flexible(
                              child: Text(
                                widget.ticket.subject,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZebuTextStyles.body(
                                  context,
                                ).copyWith(fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: _AssigneeCell(assignee: widget.ticket.assignee),
                      ),
                      SizedBox(
                        width: 118,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _StatusTag(ticket: widget.ticket),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _PriorityCell(
                            priority: widget.ticket.priority,
                          ),
                        ),
                      ),
                      // Hover-revealed open affordance.
                      SizedBox(
                        width: 24,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 90),
                          opacity: _hover ? 1 : 0,
                          child: Icon(
                            Icons.arrow_outward_rounded,
                            size: 15,
                            color: t.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Priority cell — wears the same [StatusPill] treatment as the status
/// column so priority + status read as one visual family.
class _PriorityCell extends StatelessWidget {
  const _PriorityCell({required this.priority});
  final String? priority;

  @override
  Widget build(BuildContext context) {
    final name = (priority ?? '').trim();
    if (name.isEmpty) {
      return Text('—', style: ZebuTextStyles.small(context));
    }
    return PriorityBadge(label: _titleCase(name), priority: name, dense: true);
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}

/// Assignee cell — a [UserAvatar] initial circle followed by the name, or a
/// dashed placeholder when unassigned.
class _AssigneeCell extends StatelessWidget {
  const _AssigneeCell({required this.assignee});
  final String? assignee;

  static const double _avatarSize = 24.0;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
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
              size: 13,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Unassigned',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZebuTextStyles.small(
                context,
              ).copyWith(color: t.textSecondary, fontWeight: FontWeight.w500),
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
            style: ZebuTextStyles.small(
              context,
            ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// Status tag — delegates entirely to [StatusBadge] so the dashboard's
/// tickets read identically to the same rows in the Tickets table.
class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final label = ticket.isOverdue ? 'Overdue' : _titleCase(ticket.statusName);
    return StatusBadge(
      label: label,
      status: ticket.statusName,
      overdue: ticket.isOverdue,
      dense: true,
    );
  }

  String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}

// ---------------------------------------------------------------------------
// Tasks Overview card — a 2-column grid of tone-tinted mini stat tiles, one
// per task view. Replaces the old flat name/count list with scannable,
// clickable widgets (the brief's "attractive widgets" ask).
// ---------------------------------------------------------------------------

typedef _OverviewRow = ({
  String name,
  int value,
  Color tone,
  VoidCallback onTap,
});

class _TasksOverviewCard extends StatelessWidget {
  const _TasksOverviewCard({required this.rows, required this.onSeeAll});
  final List<_OverviewRow> rows;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      title: 'Tasks Overview',
      subtitle: 'Your task queues at a glance',
      trailing: _SeeAllLink(onTap: onSeeAll),
      // Built as a Column of paired Rows (not a LayoutBuilder/Wrap) so the
      // card can sit inside the middle row's `IntrinsicHeight` — a
      // LayoutBuilder descendant can't report intrinsic dimensions. `stretch`
      // keeps the two tiles in each pair equal height.
      child: Padding(
        padding: const EdgeInsets.all(ZebuSpacing.s4),
        child: Column(
          children: [
            for (int i = 0; i < rows.length; i += 2) ...[
              if (i > 0) const SizedBox(height: ZebuSpacing.s3),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _TaskStatTile(row: rows[i])),
                    const SizedBox(width: ZebuSpacing.s3),
                    Expanded(
                      child: i + 1 < rows.length
                          ? _TaskStatTile(row: rows[i + 1])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskStatTile extends StatefulWidget {
  const _TaskStatTile({required this.row});
  final _OverviewRow row;

  @override
  State<_TaskStatTile> createState() => _TaskStatTileState();
}

class _TaskStatTileState extends State<_TaskStatTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final tone = widget.row.tone;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.row.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(ZebuSpacing.s3),
          decoration: BoxDecoration(
            color: _hover ? tone.withValues(alpha: 0.06) : t.bgElevated,
            borderRadius: BorderRadius.circular(ZebuRadius.rLg),
            border: Border.all(
              color: _hover ? tone.withValues(alpha: 0.35) : t.borderSubtle,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: tone,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      widget.row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ZebuTextStyles.small(context).copyWith(
                        color: t.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZebuSpacing.s2),
              Text(
                Fmt.count(widget.row.value),
                style: ZebuTextStyles.hero(
                  context,
                ).withTabularNums().copyWith(fontSize: 24, letterSpacing: -0.6),
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
    final t = ZebuTheme.of(context);
    final span = report.days == 0 ? 1 : report.days;
    final avgOpened = report.openedTotal / span;
    final avgClosed = report.closedTotal / span;
    final net = report.net;

    return PremiumCard(
      title: 'Ticket Activity',
      subtitle: 'Opened vs. closed over the selected range',
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
          ZebuSpacing.s5,
          ZebuSpacing.s4,
          ZebuSpacing.s5,
          ZebuSpacing.s5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Metric(
                  value: Fmt.count(report.openedTotal),
                  label: 'OPENED',
                  tone: ZebuTheme.success,
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
                  tone: net > 0 ? t.danger : ZebuTheme.success,
                ),
              ],
            ),
            const SizedBox(height: ZebuSpacing.s3),
            Text(
              'Avg ${avgOpened.toStringAsFixed(1)} opened · '
              '${avgClosed.toStringAsFixed(1)} closed per day',
              style: ZebuTextStyles.small(context),
            ),
            const SizedBox(height: ZebuSpacing.s5),
            if (report.series.isEmpty)
              SizedBox(
                height: 180,
                child: Center(
                  child: Text(
                    'No activity in this range',
                    style: ZebuTextStyles.small(context),
                  ),
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
                    color: ZebuTheme.success,
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
  const _Metric({required this.value, required this.label, required this.tone});
  final String value;
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: ZebuTextStyles.hero(context, color: tone).withTabularNums(),
          ),
          const SizedBox(height: ZebuSpacing.s1),
          Text(label, style: ZebuTextStyles.label(context)),
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
      margin: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s5),
      color: color,
    );
  }
}

// ---------------------------------------------------------------------------
// Range toggle — segmented pill group (single tinted bg, one segment lifted).
// ---------------------------------------------------------------------------

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.days, required this.onSelected});
  final int days;
  final ValueChanged<int> onSelected;

  static const _options = [7, 30, 90];

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.bgTertiary,
        borderRadius: BorderRadius.circular(ZebuRadius.rSm),
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
    final t = ZebuTheme.of(context);
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
            borderRadius: BorderRadius.circular(ZebuRadius.rXs),
            boxShadow: active ? ZebuElevation.shadowSm : null,
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
// tickets + tasks overview → activity chart) so the swap is visually calm.
// ---------------------------------------------------------------------------

// Matches the unified card-surface radius (see [PremiumCard] / [KpiTile]) so
// the skeleton→content swap doesn't visibly change corner geometry.
const _kSkelRadius = ZebuRadius.r2xl;

BoxDecoration _skelCard(ZebuTheme t) => BoxDecoration(
  color: t.bgElevated,
  borderRadius: BorderRadius.circular(_kSkelRadius),
  border: Border.all(color: t.borderSubtle, width: 1),
);

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return ColoredBox(
      color: t.bgPrimary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1100;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: ZebuSpacing.s6,
              vertical: ZebuSpacing.s5,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1800),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero
                    const _SkelBar(width: 150, height: 12),
                    const SizedBox(height: ZebuSpacing.s3),
                    const _SkelBar(width: 340, height: 30),
                    const SizedBox(height: 10),
                    const _SkelBar(width: 220, height: 14),
                    const SizedBox(height: ZebuSpacing.s4),

                    // 4 KPI cards
                    LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth;
                        final cols = w >= 1000 ? 4 : (w >= 640 ? 2 : 1);
                        const gap = ZebuSpacing.s4;
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
                    const SizedBox(height: ZebuSpacing.s5),

                    // Workload row
                    if (wide)
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _SkelBlockCard(height: 220)),
                          SizedBox(width: ZebuSpacing.s5),
                          Expanded(child: _SkelBlockCard(height: 220)),
                        ],
                      )
                    else
                      const _SkelBlockCard(height: 220),
                    const SizedBox(height: ZebuSpacing.s5),

                    // Middle row
                    if (wide)
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: _SkelRecentTicketsCard()),
                          SizedBox(width: ZebuSpacing.s5),
                          Expanded(flex: 3, child: _SkelBlockCard(height: 300)),
                        ],
                      )
                    else ...const [
                      _SkelRecentTicketsCard(),
                      SizedBox(height: ZebuSpacing.s5),
                      _SkelBlockCard(height: 300),
                    ],

                    const SizedBox(height: ZebuSpacing.s5),
                    const _SkelBlockCard(height: 320),
                    const SizedBox(height: ZebuSpacing.s10),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shimmering rectangle — the single primitive every skeleton block is built
/// from. Uses a repeating linear-gradient sweep.
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
    final t = ZebuTheme.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
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
    final t = ZebuTheme.of(context);
    return Container(
      decoration: _skelCard(t),
      padding: const EdgeInsets.all(ZebuSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: const [
          _SkelBar(width: 40, height: 40, radius: ZebuRadius.rLg),
          SizedBox(height: ZebuSpacing.s4),
          _SkelBar(width: 72, height: 28),
          SizedBox(height: 8),
          _SkelBar(width: 100, height: 13),
          SizedBox(height: ZebuSpacing.s4),
          _SkelBar(width: double.infinity, height: 6, radius: ZebuRadius.rFull),
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
        ZebuSpacing.s5,
        ZebuSpacing.s4,
        ZebuSpacing.s5,
        ZebuSpacing.s3,
      ),
      child: Row(
        children: const [
          _SkelBar(width: 130, height: 15),
          Spacer(),
          _SkelBar(width: 56, height: 12),
        ],
      ),
    );
  }
}

/// Generic elevated skeleton card of a fixed height, with a header strip.
class _SkelBlockCard extends StatelessWidget {
  const _SkelBlockCard({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      decoration: _skelCard(t),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SkelCardHeader(),
          Container(height: 1, color: t.borderSubtle),
          Padding(
            padding: const EdgeInsets.all(ZebuSpacing.s5),
            child: _SkelBar(width: double.infinity, height: height - 90),
          ),
        ],
      ),
    );
  }
}

class _SkelRecentTicketsCard extends StatelessWidget {
  const _SkelRecentTicketsCard();

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
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
    return const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s5,
        vertical: ZebuSpacing.s4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _SkelBar(width: 52, height: 13),
                SizedBox(width: ZebuSpacing.s2),
                Expanded(child: _SkelBar(width: double.infinity, height: 13)),
              ],
            ),
          ),
          SizedBox(width: ZebuSpacing.s4),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                _SkelBar(width: 24, height: 24, radius: 12),
                SizedBox(width: 8),
                Expanded(child: _SkelBar(width: double.infinity, height: 13)),
              ],
            ),
          ),
          SizedBox(width: ZebuSpacing.s4),
          SizedBox(
            width: 118,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _SkelBar(width: 84, height: 18, radius: ZebuRadius.rSm),
            ),
          ),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _SkelBar(width: 76, height: 18, radius: ZebuRadius.rSm),
            ),
          ),
          SizedBox(width: 24),
        ],
      ),
    );
  }
}
