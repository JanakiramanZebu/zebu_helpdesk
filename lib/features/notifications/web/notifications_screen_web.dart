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
import '../../../widgets/web/list_table_shell.dart';
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
/// Leading fixed-width select column. Holds the per-row checkbox that
/// drives the bulk mark-read / delete actions.
const double _kColSelectWidth = 44;
const double _kColTypeWidth = 90;
const int _kColTitleFlex = 5;
const int _kColActorFlex = 2;
const double _kColRefWidth = 100;
const double _kColStatusWidth = 100;
const double _kColReceivedWidth = 110;
const double _kColActionWidth = 44;

/// Minimum table width — accounts for the fixed-width columns
/// (44 + 90 + 100 + 100 + 110 + 44 = 488), the 3 px leading accent-stripe
/// rail, and a readable minimum for each flex column. Below this the
/// table horizontally scrolls instead of squeezing columns.
const double _kTableMinWidth = 1084;

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

  /// Client-side read override — `_open()` posts to `/notifications/{id}/read`
  /// and the backend marks the row as read, but the local list state doesn't
  /// re-fetch (that would blow away scroll position). This set records ids
  /// we've already read so the row can flip its Unread pill and bold weight
  /// immediately, without waiting for the next full refresh.
  final Set<int> _locallyRead = {};

  /// Reverse of [_locallyRead] — ids the user just flipped back to unread
  /// via the header "Mark unread" action. Same in-place update strategy so
  /// the pill/weight reflects the change without a full refetch.
  final Set<int> _locallyUnread = {};

  /// Ids the user just deleted (single or bulk). Filtered out of the visible
  /// list by [_matches] so the rows disappear immediately without triggering
  /// a full page refetch — preserves scroll position and avoids the loading
  /// skeleton flashing back in.
  final Set<int> _locallyDeleted = {};

  /// Rows the user has ticked via the leading checkbox column. Maps the
  /// notification id to its **effective read state at click time** — the
  /// header uses this to decide whether the bulk button reads "Mark read"
  /// or "Mark unread" *without* depending on state populated later during
  /// the same frame (which caused the earlier off-by-one label bug).
  final Map<int, bool> _selectedReadState = {};

  /// The ids currently rendered in the list (after filter/search). Cleared
  /// inside [_matches] on a filter-signature change rather than at the top
  /// of build, so the header's select-all checkbox sees the previous frame's
  /// set and reflects it correctly on the NEXT frame after a user click
  /// (the "select-all didn't tick the rows" bug).
  final Set<int> _visibleIds = {};
  /// Effective read state per visible id. Kept in step with [_visibleIds]
  /// and used only by [_toggleSelectAll] to seed [_selectedReadState] with
  /// each row's current read value when the user select-alls.
  final Map<int, bool> _visibleReadState = {};

  /// Signature of the filter inputs that produced the last [_visibleIds]
  /// snapshot. When [_matches] sees a new signature it wipes the set and
  /// starts fresh, so cross-tab / cross-search state doesn't leak.
  String _visibleFilterSig = '';

  Set<int> get _selectedIds => _selectedReadState.keys.toSet();
  bool get _allSelectedRead =>
      _selectedReadState.isNotEmpty &&
      _selectedReadState.values.every((r) => r);

  /// Mutates the notification with any client-side read overrides applied.
  /// Local unread wins over local read so a user who reads then unreads a
  /// row ends up looking unread; the earlier read call already hit the
  /// backend so we don't fight the server state — the local override lands
  /// on top of whichever server value comes back next.
  AppNotification _withReadOverride(AppNotification n) {
    if (_locallyUnread.contains(n.id) && n.read) {
      return n.copyWith(read: false);
    }
    if (_locallyRead.contains(n.id) && !n.read) {
      return n.copyWith(read: true);
    }
    return n;
  }

  /// Toggle a single row's selection. Captures the row's effective read
  /// state at click time so the header's "Mark read" ↔ "Mark unread" label
  /// can be computed synchronously.
  void _toggleSelected(int id, bool isRead) {
    setState(() {
      if (_selectedReadState.containsKey(id)) {
        _selectedReadState.remove(id);
      } else {
        _selectedReadState[id] = isRead;
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final selectedIds = _selectedReadState.keys.toSet();
      final allSelected =
          _visibleIds.isNotEmpty && selectedIds.containsAll(_visibleIds);
      if (allSelected) {
        for (final id in _visibleIds) {
          _selectedReadState.remove(id);
        }
      } else {
        // Seed each newly-selected row with its current read state so the
        // header's Mark read/unread decision stays consistent.
        for (final id in _visibleIds) {
          _selectedReadState[id] = _visibleReadState[id] ?? false;
        }
      }
    });
  }


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
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete this notification?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ref.read(notificationsRepositoryProvider).deleteOne(n.id);
      if (!mounted) return;
      // Optimistic — flag the id as locally deleted and setState so the
      // row disappears from the visible list immediately. `_matches`
      // filters it out. No `_refresh()` (bumping refreshKey) so the scroll
      // position + loaded pages stay intact.
      setState(() {
        _locallyDeleted.add(n.id);
        _selectedReadState.remove(n.id);
        _locallyRead.remove(n.id);
        _locallyUnread.remove(n.id);
      });
      ref.invalidate(unreadCountProvider);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    }
  }

  /// Mark every selected row read via the per-id endpoint (there's no bulk
  /// read endpoint in the repo). Records each id in [_locallyRead] so the
  /// pill/weight flips right away without waiting for the next refetch.
  Future<void> _markSelectedRead() async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();
    final repo = ref.read(notificationsRepositoryProvider);
    var failed = 0;
    for (final id in ids) {
      try {
        await repo.read(id);
      } on ApiException {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _locallyRead.addAll(ids);
      _selectedReadState.clear();
    });
    ref.invalidate(unreadCountProvider);
    if (failed > 0) {
      _toast(
        'Marked ${ids.length - failed}/${ids.length} — $failed failed',
        type: ToastType.error,
      );
    } else {
      _toast('Marked ${ids.length} as read', type: ToastType.success);
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete ${ids.length} notifications?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete ${ids.length}',
      destructive: true,
    );
    if (ok != true) return;
    final repo = ref.read(notificationsRepositoryProvider);
    final deletedIds = <int>[];
    var failed = 0;
    for (final id in ids) {
      try {
        await repo.deleteOne(id);
        deletedIds.add(id);
      } on ApiException {
        failed++;
      }
    }
    if (!mounted) return;
    // Optimistic — flag every successful id as locally deleted and clear
    // the selection. Rows disappear from the visible list on the next
    // build without triggering a full refetch.
    setState(() {
      _locallyDeleted.addAll(deletedIds);
      _selectedReadState.clear();
      _locallyRead.removeAll(deletedIds);
      _locallyUnread.removeAll(deletedIds);
    });
    ref.invalidate(unreadCountProvider);
    if (failed > 0) {
      _toast(
        'Deleted ${ids.length - failed}/${ids.length} — $failed failed',
        type: ToastType.error,
      );
    }
  }

  /// Reverse of [_markSelectedRead] — calls `POST /notifications/{id}/unread`
  /// per id and records each in [_locallyUnread] so the row's pill flips
  /// back to Unread instantly without a refetch.
  Future<void> _markSelectedUnread() async {
    if (_selectedIds.isEmpty) return;
    final ids = _selectedIds.toList();
    final repo = ref.read(notificationsRepositoryProvider);
    var failed = 0;
    for (final id in ids) {
      try {
        await repo.unread(id);
      } on ApiException {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _locallyUnread.addAll(ids);
      _locallyRead.removeAll(ids);
      _selectedReadState.clear();
    });
    ref.invalidate(unreadCountProvider);
    if (failed > 0) {
      _toast(
        'Marked ${ids.length - failed}/${ids.length} — $failed failed',
        type: ToastType.error,
      );
    } else {
      _toast('Marked ${ids.length} as unread', type: ToastType.success);
    }
  }

  Future<void> _open(AppNotification n) async {
    try {
      // Match osTicket's inbox flow: selecting a ticket/task marks ALL of the
      // agent's notifications for that object read (POST /notifications/
      // read-object), not just the tapped row — mirrors
      // NotificationsV2Controller::readObject.
      await ref
          .read(notificationsRepositoryProvider)
          .readObject(n.type, n.objectId);
      // Flip the local override so the tapped row visually flips to Read
      // immediately — the backend is now in sync but we don't re-fetch
      // (see [_locallyRead] docs for why). Sibling rows for the same object
      // reconcile on the next fetch/filter change.
      if (mounted && !n.read) {
        setState(() => _locallyRead.add(n.id));
      }
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
    // Clear the visible ledger only when the filter inputs actually
    // change — NOT at the top of build. If we cleared per-build, the
    // `_TableHeader` (which builds before PagedListView runs `_matches`)
    // would see an empty set every frame and render "select-all" as
    // unchecked even when every row is selected. Detecting a signature
    // change here means the previous frame's set stays valid for the
    // header, and only gets replaced when a real filter transition
    // happens.
    final sig = '$_view|$_search|${_typeFlags.join(',')}|$_refreshKey';
    if (sig != _visibleFilterSig) {
      _visibleIds.clear();
      _visibleReadState.clear();
      _visibleFilterSig = sig;
    }
    // Optimistic-delete filter — rows the user just deleted disappear
    // immediately without waiting for a refetch.
    if (_locallyDeleted.contains(n.id)) return false;
    // Apply the read-override so `Unread` / `Read` tabs reflect
    // client-side reads immediately (see [_locallyRead] / [_locallyUnread]).
    final effective = _withReadOverride(n);
    final viewOk = switch (_view) {
      'unread' => !effective.read,
      'read' => effective.read,
      _ => true,
    };
    if (!viewOk) return false;
    if (_typeFlags.isNotEmpty && !_typeFlags.contains(n.type)) return false;
    final q = _search.trim();
    final ok = q.isEmpty
        ? true
        : (_norm(n.displayLabel).contains(_norm(q)) ||
            _norm(Fmt.stripHtml(n.body)).contains(_norm(q)) ||
            _norm(n.actor ?? '').contains(_norm(q)) ||
            _norm('${n.type}${n.objectId}').contains(_norm(q)));
    // Record every row that passes the filter so the header select-all
    // checkbox knows the visible-row universe. Also record its effective
    // read state so the trailing button label can flip between "Mark read"
    // and "Mark unread" based on the current selection. Both are cleared
    // at the top of each build so they stay in step with the rendered list.
    if (ok) {
      _visibleIds.add(n.id);
      _visibleReadState[n.id] = effective.read;
    }
    return ok;
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

    // NOTE: `_visibleIds` / `_visibleReadState` are NOT cleared here.
    // Clearing per-build wiped the set before `_TableHeader` could read
    // it (header builds before `PagedListView` runs `_matches`), which
    // made select-all appear unchecked even when every row was
    // selected. The clear now lives inside [_matches], guarded by a
    // filter-signature check so the sets only reset on real filter
    // transitions.

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
                    // When the trailing slot is narrow (list column
                    // squeezed by an open detail panel, or a small
                    // viewport), the two ghost actions collapse to
                    // icon-only tooltip buttons — the labelled variants
                    // together take ~260 px and would otherwise overflow
                    // and force the title into a one-letter-per-line
                    // column. Threshold `640` matches the [PageHeader]
                    // stack breakpoint so the switch happens exactly when
                    // the header stops fitting side-by-side.
                    final compact = c.hasBoundedWidth && c.maxWidth < 640;
                    // Labelled ghosts (~260) + filter (~48) + gaps → 360;
                    // icon-only ghosts (~40 each) + filter (~48) → 140.
                    final actionsAllowance = compact ? 140.0 : 360.0;
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
                        // When one or more rows are selected the two ghost
                        // buttons switch to *bulk-on-selection* mode:
                        // "Mark all read" → "Mark read (N)" or "Mark
                        // unread (N)" depending on whether every selected
                        // row is currently read (captured at click time
                        // in `_selectedReadState`), and "Delete all" →
                        // "Delete (N)". No selection → they behave as
                        // "act on the entire list" (original behaviour).
                        Builder(builder: (_) {
                          final selCount = _selectedReadState.length;
                          if (selCount == 0) {
                            return _GhostAction(
                              icon: Icons.done_all_rounded,
                              label: 'Mark all read',
                              compact: compact,
                              onTap: _markAllRead,
                            );
                          }
                          final allRead = _allSelectedRead;
                          return _GhostAction(
                            icon: allRead
                                ? Icons.mark_email_unread_outlined
                                : Icons.done_all_rounded,
                            label: allRead
                                ? 'Mark unread ($selCount)'
                                : 'Mark read ($selCount)',
                            compact: compact,
                            onTap: allRead
                                ? _markSelectedUnread
                                : _markSelectedRead,
                          );
                        }),
                        const SizedBox(width: WebTokens.s2),
                        _GhostAction(
                          icon: Icons.delete_outline_rounded,
                          label: _selectedReadState.isEmpty
                              ? 'Delete all'
                              : 'Delete (${_selectedReadState.length})',
                          compact: compact,
                          tone: t.danger,
                          onTap: _selectedReadState.isEmpty
                              ? _deleteAll
                              : _deleteSelected,
                        ),
                      ],
                    );
                  },
                ),
              ),
              SegmentedTabBar<String>(
                items: tabItems,
                selected: _view,
                // Switching tabs clears any bulk selection — the rows the
                // user ticked are typically no longer visible in the new
                // view (e.g. selecting Unread items then jumping to Read),
                // so leaving the selection in place would make the header
                // "Mark read (N)" / "Delete (N)" act on ghosts.
                onSelect: (k) => setState(() {
                  _view = k;
                  _selectedReadState.clear();
                }),
              ),
              Expanded(
                child: ListTableShell(
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
                              _TableHeader(
                                scrollGutter: horizontalScroll,
                                allChecked: _visibleIds.isNotEmpty &&
                                    _selectedReadState.keys
                                        .toSet()
                                        .containsAll(_visibleIds),
                                someChecked:
                                    _selectedReadState.isNotEmpty &&
                                        !_selectedReadState.keys
                                            .toSet()
                                            .containsAll(_visibleIds),
                                onToggleAll: _toggleSelectAll,
                              ),
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
                                    itemBuilder: (context, n) {
                                      final effective = _withReadOverride(n);
                                      return _NotificationRow(
                                        notification: effective,
                                        selected: _selectedReadState
                                            .containsKey(n.id),
                                        onToggleSelected: () =>
                                            _toggleSelected(
                                                n.id, effective.read),
                                        onTap: () => _open(n),
                                        onDelete: () => _deleteOne(n),
                                      );
                                    },
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
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tone;

  /// When true, hides the label and shows only the icon (with a Tooltip
  /// carrying the label). Toggled by the header's LayoutBuilder when the
  /// trailing slot is too narrow to fit the labelled variants without
  /// overflow.
  final bool compact;

  @override
  State<_GhostAction> createState() => _GhostActionState();
}

class _GhostActionState extends State<_GhostAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final fg = widget.tone ?? t.textPrimary;
    final iconOnly = widget.compact;
    final child = iconOnly
        ? Tooltip(
            message: widget.label,
            child: Icon(widget.icon, size: 16, color: fg),
          )
        : Row(
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
          );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 40,
          // Square-ish icon button in compact mode; roomier padding when
          // the label is visible.
          padding: EdgeInsets.symmetric(horizontal: iconOnly ? 10 : 12),
          decoration: BoxDecoration(
            color: _hover
                ? (widget.tone == t.danger
                    ? t.dangerLight
                    : t.bgHover)
                : t.bgElevated,
            border: Border.all(
              color: _hover && widget.tone == t.danger
                  ? t.danger.withValues(alpha: 0.35)
                  : t.borderSubtle,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(WebTokens.rSm),
          ),
          child: child,
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
  const _TableHeader({
    this.scrollGutter = false,
    required this.allChecked,
    required this.someChecked,
    required this.onToggleAll,
  });

  /// When true, reserves 10 px of trailing space at the right edge of
  /// the header to line up with the horizontal scrollbar sitting under
  /// the body.
  final bool scrollGutter;

  /// True when every visible row is currently selected. Drives the
  /// select-all checkbox's checked state and its "Deselect all" tooltip.
  final bool allChecked;

  /// True when at least one — but not all — visible rows are selected.
  /// Renders the select-all checkbox in the tri-state / indeterminate look.
  final bool someChecked;

  /// Fired when the select-all checkbox is toggled. Fully-checked → clears
  /// visible selection; anything else → selects all visible rows.
  final VoidCallback onToggleAll;

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
            _HeaderCell(
              width: _kColSelectWidth,
              // Header select-all — tri-state: none / some / all selected.
              child: Center(
                child: _SelectCheckbox(
                  value: allChecked
                      ? true
                      : someChecked
                          ? null
                          : false,
                  onChanged: (_) => onToggleAll(),
                  tooltip: allChecked ? 'Deselect all' : 'Select all',
                ),
              ),
            ),
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
///
/// Pass either [label] (renders as a `tableHeader`-styled Text) OR [child]
/// (an arbitrary widget, e.g. the select-all checkbox in the leading
/// column). Exactly one of them must be non-null.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    this.label,
    this.child,
    this.flex,
    this.width,
    this.last = false,
    this.alignRight = false,
  }) : assert(label != null || child != null,
            'Pass either label or child to _HeaderCell.');
  final String? label;
  final Widget? child;
  final int? flex;
  final double? width;
  final bool last;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final inner = child ??
        Text(
          label!,
          style: t.tableHeader,
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
        );
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
      child: inner,
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
// Select checkbox — tri-state square used by both the header (select-all)
// and each row. `value` semantics:
//   • true  → filled with the accent, white check glyph
//   • false → empty box with a hairline border
//   • null  → filled with the accent, minus glyph (indeterminate)
// ---------------------------------------------------------------------------

class _SelectCheckbox extends StatelessWidget {
  const _SelectCheckbox({
    required this.value,
    required this.onChanged,
    this.tooltip,
  });

  final bool? value;
  final ValueChanged<bool?> onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final checked = value == true;
    final indeterminate = value == null;
    final filled = checked || indeterminate;
    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: filled ? t.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: filled ? t.accent : t.borderStrong,
          width: 1.4,
        ),
      ),
      alignment: Alignment.center,
      child: filled
          ? Icon(
              indeterminate ? Icons.remove : Icons.check,
              size: 12,
              color: Colors.white,
            )
          : null,
    );
    final target = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!checked),
        child: box,
      ),
    );
    if (tooltip == null) return target;
    return Tooltip(message: tooltip!, child: target);
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
    required this.selected,
    required this.onToggleSelected,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// True when the row's leading checkbox is ticked. Drives the bulk-action
  /// selection set on the parent screen.
  final bool selected;

  /// Fired when the row's leading checkbox is toggled.
  final VoidCallback onToggleSelected;

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  bool _hover = false;

  // Cleaner, cohesive icon set for the Type column pill — every glyph is
  // rounded so the row rhythm reads as one family. Event keys are the raw
  // osTicket notification events (see inbox.inc.php $LABELS).
  //   assigned       → person + checkmark ("assigned to me")
  //   message        → speech-bubble outline ("reply/thread")
  //   note           → pencil-on-note ("internal comment")
  //   transfer       → circular refresh ("ownership moved")
  //   status         → change ("status changed")
  //   mention        → @ ("you were mentioned")
  //   overdue        → clock ("past due")
  //   new_unassigned → inbox ("new unassigned ticket")
  //   default        → bell with a badge (generic notification)
  IconData get _eventIcon => switch (widget.notification.event) {
        'assigned' => Icons.how_to_reg_rounded,
        'message' => Icons.chat_bubble_outline_rounded,
        'note' => Icons.edit_note_rounded,
        'transfer' => Icons.sync_alt_rounded,
        'status' => Icons.change_circle_outlined,
        'mention' => Icons.alternate_email_rounded,
        'overdue' => Icons.schedule_rounded,
        'new_unassigned' => Icons.move_to_inbox_rounded,
        _ => Icons.notifications_active_rounded,
      };

  /// Tone the Type-column icon + label by the notification's **object
  /// type**, not by the event. The eye can then scan a column of green
  /// (Task) versus blue (Ticket) and separate them at a glance — the
  /// icon glyph still tells you what event happened.
  Color _typeTone(WebTokens t) =>
      widget.notification.type == 'task' ? WebTokens.success : t.accent;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final n = widget.notification;
    final typeTone = _typeTone(t);
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
      stripeColor = t.accent;
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
                        width: _kColSelectWidth,
                        // Wrapped in a nested GestureDetector that swallows
                        // the tap so it doesn't bubble up to the row's own
                        // `onTap` (which would open the detail panel).
                        child: Center(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onToggleSelected,
                            child: _SelectCheckbox(
                              value: widget.selected,
                              onChanged: (_) => widget.onToggleSelected(),
                            ),
                          ),
                        ),
                      ),
                      _BodyCell(
                        width: _kColTypeWidth,
                        child: StatusPill(
                          label: isTask ? 'Task' : 'Ticket',
                          // Colour is by object type (Task = success green,
                          // Ticket = accent blue) so the whole column can
                          // be scanned as two colour bands. The glyph
                          // itself still carries the event meaning.
                          color: typeTone,
                          icon: _eventIcon,
                          // Bolder label so "Task"/"Ticket" reads as the
                          // row's identity, not a soft tag.
                          fontWeight: FontWeight.w600,
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
                                color: t.accent,
                              )
                              .withTabularNums(),
                        ),
                      ),
                      _BodyCell(
                        width: _kColStatusWidth,
                        child: StatusPill(
                          label: unread ? 'Unread' : 'Read',
                          color: unread ? t.accent : t.textSecondary,
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
              color: _hover ? t.danger : t.textSecondary,
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
              width: _kColSelectWidth,
              child: const SizedBox.shrink(),
            ),
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
