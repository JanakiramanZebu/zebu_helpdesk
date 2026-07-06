import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format.dart';
import '../../../models/app_notification.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/paged_list_view.dart';
import '../../../widgets/slide_over_host.dart';
import '../../../widgets/web/list_search_input.dart';
import '../../../widgets/web/page_header.dart';
import '../../../widgets/web/segmented_tab_bar.dart';
import '../../../widgets/web/status_pill.dart';
import '../../../widgets/web_filter_button.dart';
import '../../dashboard/web/_tokens.dart';
import '../../tasks/web/task_detail_panel.dart';
import '../../tickets/web/ticket_detail_panel.dart';

// Column layout for the notifications table. Header and every row share these
// so the vertical grid lines up pixel-for-pixel — same treatment as the
// tickets and tasks lists.
const double _kColTypeWidth = 90;
const int _kColTitleFlex = 5;
const int _kColActorFlex = 2;
const double _kColRefWidth = 100;
const double _kColStatusWidth = 100;
const double _kColReceivedWidth = 110;
const double _kColActionWidth = 44;

/// Minimum table width — accounts for the fixed-width columns
/// (90 + 100 + 100 + 110 + 44 = 444), the 3 px leading accent-stripe rail,
/// and a readable minimum for each flex column. Below this the table
/// horizontally scrolls instead of squeezing columns.
const double _kTableMinWidth = 1040;

const _views = <({String key, String label})>[
  (key: 'all', label: 'All'),
  (key: 'unread', label: 'Unread'),
  (key: 'read', label: 'Read'),
];

/// Web-only notifications inbox.
///
/// Same data source as the mobile `NotificationsScreen`
/// ([notificationsRepositoryProvider]) — only the visual language differs:
/// [PageHeader] + [SegmentedTabBar] + a full-width table wrapped in a
/// hairline-bordered surface. Mirrors the tickets / tasks list treatment
/// so all three tables read as one product.
class NotificationsScreenWeb extends ConsumerStatefulWidget {
  const NotificationsScreenWeb({super.key});

  @override
  ConsumerState<NotificationsScreenWeb> createState() =>
      _NotificationsScreenWebState();
}

class _NotificationsScreenWebState
    extends ConsumerState<NotificationsScreenWeb> {
  int _refreshKey = 0;
  String _view = 'all';
  String _search = '';
  Timer? _debounce;
  int? _openTaskId;
  int? _openTicketId;

  /// Object-type quick-filter flags — restrict the list to `ticket` or `task`
  /// notifications when active.
  final Set<String> _typeFlags = {};

  // Shared horizontal scroll controller for the table (header + rows).
  // Keeps them in sync when the table overflows below `_kTableMinWidth`.
  final ScrollController _tableHScroll = ScrollController();

  void _closeTask() => setState(() => _openTaskId = null);
  void _closeTicket() => setState(() => _openTicketId = null);

  @override
  void dispose() {
    _debounce?.cancel();
    _tableHScroll.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() => _refreshKey++);
    ref.invalidate(unreadCountProvider);
  }

  void _toast(String msg, {ToastType type = ToastType.info}) =>
      AppToast.show(context, msg, type: type);

  Future<void> _markAllRead() async {
    try {
      await ref.read(notificationsRepositoryProvider).readAll();
      _refresh();
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    }
  }

  Future<void> _deleteAll() async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete all notifications?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete all',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ref.read(notificationsRepositoryProvider).deleteAll();
      _refresh();
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    }
  }

  Future<void> _deleteOne(AppNotification n) async {
    try {
      await ref.read(notificationsRepositoryProvider).deleteOne(n.id);
      ref.invalidate(unreadCountProvider);
      _refresh();
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    }
  }

  Future<void> _open(AppNotification n) async {
    try {
      await ref.read(notificationsRepositoryProvider).read(n.id);
    } on ApiException catch (_) {
      // Best-effort; open regardless.
    }
    ref.invalidate(unreadCountProvider);
    if (!mounted) return;
    if (n.type == 'task') {
      setState(() {
        _openTaskId = n.objectId;
        _openTicketId = null;
      });
    } else {
      setState(() {
        _openTicketId = n.objectId;
        _openTaskId = null;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final next = value.trim();
      if (next != _search && mounted) setState(() => _search = next);
    });
  }

  bool _matches(AppNotification n) {
    final viewOk = switch (_view) {
      'unread' => !n.read,
      'read' => n.read,
      _ => true,
    };
    if (!viewOk) return false;
    if (_typeFlags.isNotEmpty && !_typeFlags.contains(n.type)) return false;
    final q = _search.trim();
    if (q.isEmpty) return true;
    final needle = _norm(q);
    return _norm(n.displayLabel).contains(needle) ||
        _norm(Fmt.stripHtml(n.body)).contains(needle) ||
        _norm(n.actor ?? '').contains(needle) ||
        _norm('${n.type}${n.objectId}').contains(needle);
  }

  List<WebQuickFilter> _quickFilters() {
    WebQuickFilter chip(String key, String label) => WebQuickFilter(
          label: label,
          active: _typeFlags.contains(key),
          onToggle: () => setState(() {
            if (!_typeFlags.add(key)) _typeFlags.remove(key);
          }),
        );
    return [
      chip('ticket', 'Tickets only'),
      chip('task', 'Tasks only'),
    ];
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[#,\s₹]'), '');

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final repo = ref.watch(notificationsRepositoryProvider);

    final tabItems = [
      for (final v in _views)
        SegmentedTabItem<String>(value: v.key, label: v.label),
    ];

    // Two nested slide-over hosts. Only one panel is open at a time — the
    // `_open` handler mutually excludes _openTaskId and _openTicketId — so
    // this reads like a chained "if a ticket, show ticket panel; if a task,
    // show task panel; otherwise just the list" without any type gymnastics.
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
        child: ColoredBox(
          color: t.bgPrimary,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: 'Notifications',
                trailing: LayoutBuilder(
                  builder: (context, c) {
                    // Search width is responsive to the trailing slot
                    // itself. Filter button + two ghost actions ("Mark
                    // all read", "Delete all") eat ~360 px on the right;
                    // whatever remains goes to search, clamped 200–320.
                    final actionsAllowance = 360.0;
                    final available = c.hasBoundedWidth
                        ? c.maxWidth - actionsAllowance
                        : 320.0;
                    final searchWidth = available.clamp(200.0, 320.0);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        WebFilterButton(
                          filters: _quickFilters(),
                          // Always pass the reset callback — the popover
                          // decides visibility itself from its live local
                          // state.
                          onClear: () => setState(_typeFlags.clear),
                        ),
                        const SizedBox(width: WebTokens.s3),
                        SizedBox(
                          width: searchWidth,
                          child: ListSearchInput(
                            hintText: 'Search',
                            onChanged: _onSearchChanged,
                          ),
                        ),
                        const SizedBox(width: WebTokens.s3),
                        _GhostAction(
                          icon: Icons.done_all_rounded,
                          label: 'Mark all read',
                          onTap: _markAllRead,
                        ),
                        const SizedBox(width: WebTokens.s2),
                        _GhostAction(
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete all',
                          tone: WebTokens.danger,
                          onTap: _deleteAll,
                        ),
                      ],
                    );
                  },
                ),
              ),
              SegmentedTabBar<String>(
                items: tabItems,
                selected: _view,
                onSelect: (k) => setState(() => _view = k),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalScroll =
                        constraints.maxWidth <= _kTableMinWidth;
                    final tableWidth = horizontalScroll
                        ? _kTableMinWidth
                        : constraints.maxWidth;
                    return Scrollbar(
                      controller: _tableHScroll,
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      child: SingleChildScrollView(
                        controller: _tableHScroll,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: tableWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TableHeader(scrollGutter: horizontalScroll),
                              Expanded(
                                child: ColoredBox(
                                  color: t.bgElevated,
                                  child: PagedListView<AppNotification>(
                                    padding: EdgeInsets.zero,
                                    refreshKey:
                                        '$_refreshKey|$_view|$_search',
                                    itemFilter: _matches,
                                    emptyMessage: 'No notifications',
                                    emptyHint: 'You are all caught up.',
                                    emptyIcon: Icons.notifications_none,
                                    fetch: (page) => repo.list(page: page),
                                    loadingBuilder: (_) =>
                                        const _NotificationTableSkeleton(),
                                    itemBuilder: (context, n) =>
                                        _NotificationRow(
                                      notification: n,
                                      onTap: () => _open(n),
                                      onDelete: () => _deleteOne(n),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ghost action button — small outlined pill with icon + label. Shared with
// the notifications header only for now; if other list screens grow header
// actions, promote to lib/widgets/web/.
// ---------------------------------------------------------------------------

class _GhostAction extends StatefulWidget {
  const _GhostAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tone,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tone;

  @override
  State<_GhostAction> createState() => _GhostActionState();
}

class _GhostActionState extends State<_GhostAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final fg = widget.tone ?? t.textPrimary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hover
                ? (widget.tone == WebTokens.danger
                    ? t.dangerLight
                    : t.bgHover)
                : t.bgElevated,
            border: Border.all(
              color: _hover && widget.tone == WebTokens.danger
                  ? WebTokens.danger.withValues(alpha: 0.35)
                  : t.borderSubtle,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(WebTokens.rSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: t.bodySm.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Table header — column labels rendered on a `bgElevated` strip so the
// header reads separated from body rows without shadows or extra borders.
// Shares the exact column widths every row uses via the `_kCol*` constants
// so the grid aligns pixel-for-pixel.
// ---------------------------------------------------------------------------

class _TableHeader extends StatelessWidget {
  const _TableHeader({this.scrollGutter = false});

  /// When true, reserves 10 px of trailing space at the right edge of
  /// the header to line up with the horizontal scrollbar sitting under
  /// the body.
  final bool scrollGutter;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(
          top: BorderSide(color: t.borderSubtle, width: 1),
          bottom: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Leading 3 px offset matches the row's accent-stripe rail so
            // column starts line up with row content pixel-for-pixel.
            const SizedBox(width: 3),
            const _HeaderCell(width: _kColTypeWidth, label: 'Type'),
            const _HeaderCell(flex: _kColTitleFlex, label: 'Notification'),
            const _HeaderCell(flex: _kColActorFlex, label: 'Actor'),
            const _HeaderCell(width: _kColRefWidth, label: 'Reference'),
            const _HeaderCell(width: _kColStatusWidth, label: 'Status'),
            const _HeaderCell(
              width: _kColReceivedWidth,
              label: 'Received',
              alignRight: true,
            ),
            const _HeaderCell(
              width: _kColActionWidth,
              label: '',
              last: true,
            ),
            if (scrollGutter) const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

/// Column header cell — hairline right border (except on the last cell),
/// `s3` horizontal padding, `tableHeader` typography. Mirrors the tickets
/// and tasks list treatments so all three tables read as one grid.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    this.flex,
    this.width,
    this.last = false,
    this.alignRight = false,
  });
  final String label;
  final int? flex;
  final double? width;
  final bool last;
  final bool alignRight;

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
            : Border(right: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        label,
        style: t.tableHeader,
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
      ),
    );
    if (flex != null) return Expanded(flex: flex!, child: content);
    if (width != null) return SizedBox(width: width!, child: content);
    return content;
  }
}

/// Body cell — right-border creates the vertical grid line; 8 px vertical
/// padding gives a tighter table rhythm than the header's `s3`.
class _BodyCell extends StatelessWidget {
  const _BodyCell({
    required this.child,
    this.flex,
    this.width,
    this.last = false,
    this.alignRight = false,
  });
  final Widget child;
  final int? flex;
  final double? width;
  final bool last;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s3,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(right: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
    if (flex != null) return Expanded(flex: flex!, child: content);
    if (width != null) return SizedBox(width: width!, child: content);
    return content;
  }
}

// ---------------------------------------------------------------------------
// Notification row — one single-line row per notification, columns aligned
// with `_TableHeader`. Unread rows carry a permanent accent stripe on the
// left (same treatment tickets uses for overdue rows) so the inbox is
// scannable at a glance without needing to tint the entire row.
// ---------------------------------------------------------------------------

class _NotificationRow extends StatefulWidget {
  const _NotificationRow({
    required this.notification,
    required this.onTap,
    required this.onDelete,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  bool _hover = false;

  (Color, IconData) _style() => switch (widget.notification.event) {
        'assigned' => (WebTokens.accent, Icons.person_add_alt),
        'message' => (WebTokens.info, Icons.mail_outline),
        'note' => (WebTokens.warning, Icons.sticky_note_2_outlined),
        'transferred' => (WebTokens.accent, Icons.swap_horiz),
        'overdue' => (WebTokens.danger, Icons.warning_amber_rounded),
        _ => (WebTokens.accent, Icons.notifications_outlined),
      };

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final n = widget.notification;
    final (tone, icon) = _style();
    final unread = !n.read;
    final snippet = (n.body != null && n.body!.isNotEmpty)
        ? Fmt.stripHtml(n.body)
        : null;
    final isTask = n.type == 'task';

    // Left accent stripe — brand-blue on unread rows (permanent) or hover,
    // transparent otherwise. Kept in the layout on every row so content
    // never shifts.
    final Color stripeColor;
    if (unread) {
      stripeColor = WebTokens.accent;
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
          decoration: BoxDecoration(
            color: _hover
                ? t.bgHover
                : (unread ? t.accentSoft : t.bgElevated),
            border: Border(
              bottom: BorderSide(color: t.borderSubtle, width: 1),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // AnimatedContainer(
                //   duration: const Duration(milliseconds: 120),
                //   curve: Curves.easeOut,
                //   width: 3,
                //   color: stripeColor,
                // ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BodyCell(
                        width: _kColTypeWidth,
                        child: StatusPill(
                          label: isTask ? 'Task' : 'Ticket',
                          color: tone,
                          icon: icon,
                        ),
                      ),
                      _BodyCell(
                        flex: _kColTitleFlex,
                        child: Text(
                          snippet == null || snippet.isEmpty
                              ? n.displayLabel
                              : '${n.displayLabel} — $snippet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySm.copyWith(
                            color: t.textPrimary,
                            fontWeight: unread
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      _BodyCell(
                        flex: _kColActorFlex,
                        child: _TextCell(text: n.actor ?? ''),
                      ),
                      _BodyCell(
                        width: _kColRefWidth,
                        child: Text(
                          '#${n.objectId}',
                          style: t.bodySm
                              .copyWith(
                                fontWeight: FontWeight.w600,
                                color: WebTokens.accent,
                              )
                              .withTabularNums(),
                        ),
                      ),
                      _BodyCell(
                        width: _kColStatusWidth,
                        child: StatusPill(
                          label: unread ? 'Unread' : 'Read',
                          color: unread ? WebTokens.accent : t.textSecondary,
                        ),
                      ),
                      _BodyCell(
                        width: _kColReceivedWidth,
                        alignRight: true,
                        child: Text(
                          n.created != null ? Fmt.ago(n.created) : '—',
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          textAlign: TextAlign.right,
                          style: t.bodySm
                              .copyWith(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w500,
                              )
                              .withTabularNums(),
                        ),
                      ),
                      _BodyCell(
                        width: _kColActionWidth,
                        last: true,
                        child: _DeleteButton(
                          visible: _hover,
                          onTap: widget.onDelete,
                        ),
                      ),
                    ],
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
// Cell primitives
// ---------------------------------------------------------------------------

class _TextCell extends StatelessWidget {
  const _TextCell({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final empty = text.trim().isEmpty;
    return Text(
      empty ? '—' : text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.bodySm.copyWith(
        color: empty ? t.textSecondary : t.textPrimary,
        fontWeight: empty ? FontWeight.w400 : FontWeight.w500,
      ),
    );
  }
}

class _DeleteButton extends StatefulWidget {
  const _DeleteButton({required this.visible, required this.onTap});
  final bool visible;
  final VoidCallback onTap;

  @override
  State<_DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends State<_DeleteButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return AnimatedOpacity(
      opacity: widget.visible ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.visible ? widget.onTap : null,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hover ? t.dangerLight : Colors.transparent,
              borderRadius: BorderRadius.circular(WebTokens.rSm),
            ),
            child: Icon(
              Icons.delete_outline,
              size: 18,
              color: _hover ? WebTokens.danger : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton loader — rendered by [PagedListView.loadingBuilder] on the first
// paint before notification rows arrive. Mirrors the real row's column grid
// so the transition to live data is a swap-in-place rather than a layout
// jump. A single shared pulse controller drives the greyscale opacity across
// every placeholder block for a synchronised "one heartbeat" feel.
// ---------------------------------------------------------------------------

class _NotificationTableSkeleton extends StatefulWidget {
  const _NotificationTableSkeleton();

  @override
  State<_NotificationTableSkeleton> createState() =>
      _NotificationTableSkeletonState();
}

class _NotificationTableSkeletonState extends State<_NotificationTableSkeleton>
    with SingleTickerProviderStateMixin {
  static const double _kApproxRowHeight = 32;

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final rowCount = constraints.maxHeight.isFinite
            ? (constraints.maxHeight / _kApproxRowHeight).ceil().clamp(6, 40)
            : 12;
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final color = Color.lerp(t.bgTertiary, t.bgHover, _pulse.value)!;
            return ColoredBox(
              color: t.bgElevated,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < rowCount; i++)
                    _SkeletonRow(shade: color),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({required this.shade});
  final Color shade;

  Widget _block(double width) => _SkeletonBlock(width: width, color: shade);

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Leading spacer that matches the real row's accent-stripe
            // width — keeps content columns pixel-aligned with the live
            // table so nothing shifts when data arrives.
            const SizedBox(width: 3),
            _BodyCell(
              width: _kColTypeWidth,
              child: _block(60),
            ),
            _BodyCell(
              flex: _kColTitleFlex,
              child: _block(320),
            ),
            _BodyCell(
              flex: _kColActorFlex,
              child: _block(110),
            ),
            _BodyCell(
              width: _kColRefWidth,
              child: _block(50),
            ),
            _BodyCell(
              width: _kColStatusWidth,
              child: _block(60),
            ),
            _BodyCell(
              width: _kColReceivedWidth,
              alignRight: true,
              child: _block(56),
            ),
            _BodyCell(
              width: _kColActionWidth,
              last: true,
              child: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.width, required this.color});
  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
