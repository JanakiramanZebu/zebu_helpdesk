import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format.dart';
import '../../../models/app_notification.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/slide_over_host.dart';
import '../../../widgets/states.dart';
import '../../../widgets/web/bulk_action_bar.dart';
import '../../../widgets/web/dots_loader.dart';
import '../../../widgets/web/list_search_input.dart';
import '../../../widgets/web/list_table_shell.dart';
import '../../../widgets/web/page_header.dart';
import '../../../widgets/web/segmented_tab_bar.dart';
import '../../../widgets/web/select_checkbox.dart';
import '../../../widgets/web/status_pill.dart';
import '../../../widgets/web/zebu_data_grid.dart';
import '../../../widgets/web_filter_button.dart';
import '../../tasks/web/task_detail_panel.dart';
import '../../tickets/web/ticket_detail_panel.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

// Column layout for the notifications table. Header and every row share these
// so the vertical grid lines up pixel-for-pixel — same treatment as the
// tickets and tasks lists.
/// Leading fixed-width select column. Holds the per-row checkbox that
/// drives the bulk mark-read / delete actions.
const double _kColSelectWidth = 44;
const double _kColTypeWidth = 108;
const int _kColTitleFlex = 5;
const int _kColActorFlex = 2;
const double _kColRefWidth = 100;
const double _kColReceivedWidth = 110;

/// Fixed table row height — uniform, Asana-style rows matching the tickets &
/// tasks lists. Replaces `IntrinsicHeight` so every row is the same height and
/// the layout skips an extra measure pass.
const double _kRowHeight = 48;

/// Minimum table width — accounts for the fixed-width columns
/// (44 + 90 + 100 + 100 + 110 + 44 = 488), the 3 px leading accent-stripe
/// rail, and a readable minimum for each flex column. Below this the
/// table horizontally scrolls instead of squeezing columns.
const double _kTableMinWidth = 984;

const _views = <({String key, String label, IconData icon})>[
  (key: 'all', label: 'All', icon: Icons.all_inbox_outlined),
  (key: 'unread', label: 'Unread', icon: Icons.mark_email_unread_outlined),
  (key: 'read', label: 'Read', icon: Icons.drafts_outlined),
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

  /// Objects (ticket/task) the user has ticked via the leading checkbox —
  /// selection is per OBJECT now that each row is one collapsed object. Maps a
  /// group key ("type:objectId") to whether EVERY notification in that object
  /// was read at click time, so the header can label the bulk button "Mark
  /// read" vs "Mark unread" synchronously.
  final Map<String, bool> _selectedReadState = {};

  /// Group keys currently rendered (after filter/search) and their aggregate
  /// read state — the select-all checkbox's universe. Rebuilt each frame from
  /// the grouped, filtered list; safe because grouping now happens up-front in
  /// build(), before both the header and the list body are constructed.
  final Set<String> _visibleKeys = {};
  final Map<String, bool> _visibleReadState = {};

  /// Currently-visible groups by key — resolves a selected key to its
  /// notification ids for the bulk read/unread/delete actions.
  final Map<String, NotificationGroup> _groupsByKey = {};

  Set<String> get _selectedKeys => _selectedReadState.keys.toSet();
  bool get _allSelectedRead =>
      _selectedReadState.isNotEmpty &&
      _selectedReadState.values.every((r) => r);

  /// Notification ids across all currently-selected (and still-visible) groups.
  List<int> _selectedNotificationIds() {
    final ids = <int>[];
    for (final key in _selectedReadState.keys) {
      final g = _groupsByKey[key];
      if (g != null) ids.addAll(g.ids);
    }
    return ids;
  }

  /// Accumulated notification pages. Grouping is done client-side over EVERY
  /// loaded page (not per page), so an object whose events straddle a page
  /// boundary still collapses into one row once both pages are loaded.
  final List<AppNotification> _all = [];

  // Memoized output of [_computeVisibleGroups]. Grouping + HTML-strip + filter
  // over every loaded page is expensive, so it's recomputed only when its
  // inputs actually change — not on every setState (checkbox ticks, select-all,
  // panel open/close all rebuild but leave the visible group list untouched).
  List<NotificationGroup>? _cachedGroups;
  Object? _cachedGroupsSig;
  int _page = 1;
  bool _loadingPage = false;
  bool _hasMore = true;
  bool _initialLoad = true;
  Object? _pageError;
  final ScrollController _vScroll = ScrollController();

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

  /// Toggle one object's selection. Captures its aggregate read state at click
  /// time so the header's "Mark read" ↔ "Mark unread" label stays consistent.
  void _toggleSelected(String key, bool allRead) {
    setState(() {
      if (_selectedReadState.containsKey(key)) {
        _selectedReadState.remove(key);
      } else {
        _selectedReadState[key] = allRead;
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      final allSelected =
          _visibleKeys.isNotEmpty &&
          _selectedReadState.keys.toSet().containsAll(_visibleKeys);
      if (allSelected) {
        for (final key in _visibleKeys) {
          _selectedReadState.remove(key);
        }
      } else {
        // Seed each newly-selected object with its current aggregate read
        // state so the header's Mark read/unread decision stays consistent.
        for (final key in _visibleKeys) {
          _selectedReadState[key] = _visibleReadState[key] ?? false;
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
  void initState() {
    super.initState();
    _vScroll.addListener(_onVScroll);
    _loadPage(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tableHScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  /// Pulls the next page while the list is too short to scroll.
  ///
  /// Infinite scroll assumes a full viewport; grouping breaks that assumption
  /// because one page of notifications can collapse to three rows. Without
  /// this the list stops at whatever the first page happened to group into,
  /// and no amount of scrolling asks for more — there is nothing to scroll.
  void _fillViewport() {
    if (!_hasMore || _loadingPage) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vScroll.hasClients) return;
      if (_vScroll.position.maxScrollExtent <= 0) _loadPage();
    });
  }

  void _onVScroll() {
    if (_vScroll.position.pixels >= _vScroll.position.maxScrollExtent - 320) {
      _loadPage();
    }
  }

  /// Fetch the next flat page of notifications and accumulate it; [reset] starts
  /// over (used on refresh + after bulk mutations). Local read/delete overrides
  /// are cleared on reset since a fresh fetch supersedes them.
  Future<void> _loadPage({bool reset = false}) async {
    if (_loadingPage) return;
    if (!reset && !_hasMore) return;
    setState(() {
      _loadingPage = true;
      if (reset) {
        _initialLoad = true;
        _pageError = null;
        _page = 1;
        _hasMore = true;
        _all.clear();
        _locallyRead.clear();
        _locallyUnread.clear();
        _locallyDeleted.clear();
      }
    });
    try {
      final result = await ref
          .read(notificationsRepositoryProvider)
          .list(page: _page, limit: 50);
      if (!mounted) return;
      setState(() {
        _all.addAll(result.items);
        _hasMore = result.hasMore && result.items.isNotEmpty;
        _page += 1;
        _initialLoad = false;
      });
      _fillViewport();
    } catch (e) {
      if (!mounted) return;
      setState(() => _pageError = e);
    } finally {
      if (mounted) setState(() => _loadingPage = false);
    }
  }

  void _refresh() {
    _loadPage(reset: true);
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
      title: 'Delete all',
      message:
          'Are you sure you want to delete every notification? '
          'This cannot be undone.',
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

  /// Delete every notification for one collapsed object (a row). No
  /// delete-by-object endpoint exists, so clear each id. Optimistic: the ids go
  /// to [_locallyDeleted] so the row vanishes without a full refetch.
  Future<void> _deleteGroup(NotificationGroup g) async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete',
      message:
          'Are you sure you want to delete the notifications for this '
          '${g.type}? This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    final repo = ref.read(notificationsRepositoryProvider);
    final ids = g.ids.toList();
    final deleted = <int>[];
    var failed = 0;
    for (final id in ids) {
      try {
        await repo.deleteOne(id);
        deleted.add(id);
      } on ApiException {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _locallyDeleted.addAll(deleted);
      _selectedReadState.remove(g.key);
      _locallyRead.removeAll(deleted);
      _locallyUnread.removeAll(deleted);
    });
    ref.invalidate(unreadCountProvider);
    if (failed > 0) {
      _toast(
        'Deleted ${deleted.length}/${ids.length} — $failed failed',
        type: ToastType.error,
      );
    }
  }

  /// Mark every selected object read — one `read-object` call per object marks
  /// all of that object's notifications read (mirrors readObject). Records the
  /// ids in [_locallyRead] so rows flip right away without a refetch.
  Future<void> _markSelectedRead() async {
    final keys = _selectedKeys;
    if (keys.isEmpty) return;
    final repo = ref.read(notificationsRepositoryProvider);
    final readIds = <int>[];
    var failed = 0;
    for (final key in keys) {
      final g = _groupsByKey[key];
      if (g == null) continue;
      try {
        await repo.readObject(g.type, g.objectId);
        readIds.addAll(g.ids);
      } on ApiException {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _locallyRead.addAll(readIds);
      _locallyUnread.removeAll(readIds);
      _selectedReadState.clear();
    });
    ref.invalidate(unreadCountProvider);
    if (failed > 0) {
      _toast(
        'Marked ${keys.length - failed}/${keys.length} — $failed failed',
        type: ToastType.error,
      );
    } else {
      _toast('Marked ${keys.length} as read', type: ToastType.success);
    }
  }

  Future<void> _deleteSelected() async {
    final keys = _selectedKeys;
    if (keys.isEmpty) return;
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete',
      message:
          'Are you sure you want to delete the notifications for '
          '${keys.length} ${keys.length == 1 ? 'item' : 'items'}? '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    final repo = ref.read(notificationsRepositoryProvider);
    final ids = _selectedNotificationIds();
    final deleted = <int>[];
    var failed = 0;
    for (final id in ids) {
      try {
        await repo.deleteOne(id);
        deleted.add(id);
      } on ApiException {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _locallyDeleted.addAll(deleted);
      _selectedReadState.clear();
      _locallyRead.removeAll(deleted);
      _locallyUnread.removeAll(deleted);
    });
    ref.invalidate(unreadCountProvider);
    if (failed > 0) {
      _toast(
        'Deleted ${deleted.length}/${ids.length} — $failed failed',
        type: ToastType.error,
      );
    }
  }

  /// Reverse of [_markSelectedRead] — calls `POST /notifications/{id}/unread`
  /// per id across the selected objects and records each in [_locallyUnread].
  Future<void> _markSelectedUnread() async {
    final keys = _selectedKeys;
    if (keys.isEmpty) return;
    final repo = ref.read(notificationsRepositoryProvider);
    final ids = _selectedNotificationIds();
    final done = <int>[];
    var failed = 0;
    for (final id in ids) {
      try {
        await repo.unread(id);
        done.add(id);
      } on ApiException {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() {
      _locallyUnread.addAll(done);
      _locallyRead.removeAll(done);
      _selectedReadState.clear();
    });
    ref.invalidate(unreadCountProvider);
    if (failed > 0) {
      _toast(
        'Marked ${keys.length - failed}/${keys.length} — $failed failed',
        type: ToastType.error,
      );
    } else {
      _toast('Marked ${keys.length} as unread', type: ToastType.success);
    }
  }

  Future<void> _open(NotificationGroup g) async {
    try {
      // Match osTicket's inbox flow: selecting a ticket/task marks ALL of the
      // agent's notifications for that object read (POST /notifications/
      // read-object) — mirrors NotificationsV2Controller::readObject.
      await ref
          .read(notificationsRepositoryProvider)
          .readObject(g.type, g.objectId);
      // Flip the local override so the card flips to Read immediately — the
      // backend is in sync but we don't re-fetch (see [_locallyRead] docs).
      if (mounted && g.hasUnread) {
        setState(() => _locallyRead.addAll(g.ids));
      }
    } on ApiException catch (_) {
      // Best-effort; open regardless.
    }
    ref.invalidate(unreadCountProvider);
    if (!mounted) return;
    if (g.type == 'task') {
      setState(() {
        _openTaskId = g.objectId;
        _openTicketId = null;
      });
    } else {
      setState(() {
        _openTicketId = g.objectId;
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

  /// Group the accumulated notifications into per-object cards and apply the
  /// active view/type/search filters, mirroring osTicket's inbox (one row per
  /// ticket/task, newest activity first). Also refreshes the selection ledgers
  /// ([_groupsByKey], [_visibleKeys], [_visibleReadState]) so the header's
  /// select-all reflects exactly what's rendered. Called once at the top of
  /// build(), before the header and list body are constructed.
  List<NotificationGroup> _computeVisibleGroups() {
    final q = _search.trim();
    // Normalize the needle once, not 4× per notification.
    final needle = q.isEmpty ? null : _norm(q);

    // Content signature of every input this computation reads. When it's
    // unchanged (e.g. the rebuild came from a selection toggle), return the
    // cached groups and skip the regrouping / stripHtml pass entirely.
    final sig = Object.hash(
      Object.hashAll(_all.map((n) => n.id)),
      Object.hashAllUnordered(_locallyDeleted),
      Object.hashAllUnordered(_locallyRead),
      Object.hashAllUnordered(_locallyUnread),
      Object.hashAllUnordered(_typeFlags),
      needle,
      _view,
    );
    if (_cachedGroups != null && _cachedGroupsSig == sig) {
      return _cachedGroups!;
    }

    bool matchesSearch(AppNotification n) => needle == null
        ? true
        : (_norm(n.displayLabel).contains(needle) ||
              _norm(Fmt.stripHtml(n.body)).contains(needle) ||
              _norm(n.actor ?? '').contains(needle) ||
              _norm('${n.type}${n.objectId}').contains(needle));

    // Notification-level filter: drop optimistic-delete tombstones, apply the
    // read overrides, then type + search. The view (unread/read) is applied
    // per object after grouping.
    final filtered = <AppNotification>[];
    for (final raw in _all) {
      if (_locallyDeleted.contains(raw.id)) continue;
      if (_typeFlags.isNotEmpty && !_typeFlags.contains(raw.type)) continue;
      final n = _withReadOverride(raw);
      if (!matchesSearch(n)) continue;
      filtered.add(n);
    }

    final groups = NotificationGroup.from(filtered)
        .where((g) {
          return switch (_view) {
            'unread' => g.hasUnread,
            'read' => !g.hasUnread,
            _ => true,
          };
        })
        .toList(growable: false);

    // Refresh the selection ledgers for the header select-all + bulk actions.
    _groupsByKey
      ..clear()
      ..addEntries(groups.map((g) => MapEntry(g.key, g)));
    _visibleKeys
      ..clear()
      ..addAll(groups.map((g) => g.key));
    _visibleReadState
      ..clear()
      ..addEntries(groups.map((g) => MapEntry(g.key, !g.hasUnread)));

    _cachedGroups = groups;
    _cachedGroupsSig = sig;
    return groups;
  }

  List<WebQuickFilter> _quickFilters() {
    WebQuickFilter chip(String key, String label) => WebQuickFilter(
      label: label,
      active: _typeFlags.contains(key),
      onToggle: () => setState(() {
        if (!_typeFlags.add(key)) _typeFlags.remove(key);
      }),
    );
    return [chip('ticket', 'Tickets only'), chip('task', 'Tasks only')];
  }

  static final RegExp _normPattern = RegExp(r'[#,\s₹]');
  static String _norm(String s) => s.toLowerCase().replaceAll(_normPattern, '');

  /// The scrolling list of grouped object rows (or skeleton / error / empty).
  Widget _buildGroupedBody(List<NotificationGroup> groups) {
    if (_initialLoad && _loadingPage) {
      return const DotsLoader();
    }
    if (_pageError != null && _all.isEmpty) {
      return ErrorView(
        error: _pageError!,
        onRetry: () => _loadPage(reset: true),
      );
    }
    if (groups.isEmpty) {
      return const EmptyView(
        icon: Icons.notifications_none,
        message: 'No notifications',
        hint: 'You are all caught up.',
      );
    }
    return ListView.builder(
      controller: _vScroll,
      padding: EdgeInsets.zero,
      // The trailing spinner tracks an in-flight fetch, not the mere
      // possibility of more. Keyed off `_hasMore` it sat there permanently:
      // grouping collapses 25 notifications into a handful of object rows, so
      // the list is rarely tall enough to scroll, the scroll trigger never
      // fires, and nothing ever clears it.
      itemCount: groups.length + (_hasMore && _loadingPage ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= groups.length) {
          return const Padding(
            padding: EdgeInsets.all(ZebuSpacing.s4),
            child: DotsLoader(),
          );
        }
        final g = groups[index];
        return _NotificationGroupRow(
          group: g,
          selected: _selectedReadState.containsKey(g.key),
          // Selecting an object captures whether it's fully read so the header
          // can label the bulk button Mark read / Mark unread.
          onToggleSelected: () => _toggleSelected(g.key, !g.hasUnread),
          onTap: () => _open(g),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);

    // Group + filter up-front so the header's select-all and the list body
    // both read the same visible-object ledger this frame.
    final groups = _computeVisibleGroups();

    final tabItems = [
      for (final v in _views)
        SegmentedTabItem<String>(value: v.key, label: v.label, icon: v.icon),
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
                    // Only the filter button sits beside the search field
                    // now — the two whole-list ghosts moved to the floating
                    // bar, so the reserve drops from 360 to just the filter
                    // plus its gap.
                    const actionsAllowance = 60.0;
                    final available = c.hasBoundedWidth
                        ? c.maxWidth - actionsAllowance
                        : 320.0;
                    final searchWidth = available.clamp(200.0, 320.0);
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: searchWidth,
                          child: ListSearchInput(
                            hintText: 'Search',
                            onChanged: _onSearchChanged,
                          ),
                        ),
                        const SizedBox(width: ZebuSpacing.s3),

                        WebFilterButton(
                          filters: _quickFilters(),
                          // Always pass the reset callback — the popover
                          // decides visibility itself from its live local
                          // state.
                          onClear: () => setState(_typeFlags.clear),
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
                child: Stack(
                  children: [
                    ListTableShell(
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _TableHeader(
                                      scrollGutter: horizontalScroll,
                                      allChecked:
                                          _visibleKeys.isNotEmpty &&
                                          _selectedReadState.keys
                                              .toSet()
                                              .containsAll(_visibleKeys),
                                      someChecked:
                                          _selectedReadState.isNotEmpty &&
                                          !_selectedReadState.keys
                                              .toSet()
                                              .containsAll(_visibleKeys),
                                      onToggleAll: _toggleSelectAll,
                                    ),
                                    Expanded(
                                      child: ColoredBox(
                                        color: t.bgElevated,
                                        child: _buildGroupedBody(groups),
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
                    if (_selectedReadState.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 32,
                        child: WebBulkBar(
                          count: _selectedReadState.length,
                          onClear: () => setState(_selectedReadState.clear),
                          actions: [
                            WebBulkAction(
                              icon: _allSelectedRead
                                  ? Icons.mark_email_unread_outlined
                                  : Icons.done_all_rounded,
                              label: _allSelectedRead
                                  ? 'Mark unread'
                                  : 'Mark read',
                              primary: true,
                              onTap: (_) => _allSelectedRead
                                  ? _markSelectedUnread()
                                  : _markSelectedRead(),
                            ),
                            WebBulkAction(
                              icon: Icons.delete_outline_rounded,
                              label: 'Delete',
                              // Inline, not behind ⋯: with only two actions
                              // the menu hid half the bar's contents behind
                              // an extra click.
                              primary: true,
                              destructive: true,
                              onTap: (_) => _deleteSelected(),
                            ),
                          ],
                        ),
                      ),
                  ],
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
    final t = ZebuTheme.of(context);
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
                // Matches the panel header's Actions pill — 14 px medium.
                // At 12 px semibold these read as a different control from
                // every other ghost button in the app.
                style: ZebuTextStyles.body(
                  context,
                  color: fg,
                  fontWeight: ZebuFonts.medium,
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
          height: 32,
          // Square-ish icon button in compact mode; roomier padding when
          // the label is visible.
          padding: EdgeInsets.symmetric(horizontal: iconOnly ? 10 : 12),
          decoration: BoxDecoration(
            color: _hover
                ? (widget.tone == t.danger ? t.dangerLight : t.bgHover)
                : t.bgElevated,
            border: Border.all(
              color: _hover && widget.tone == t.danger
                  ? t.danger.withValues(alpha: 0.35)
                  : t.borderSubtle,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(5),
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
    final t = ZebuTheme.of(context);
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
                child: SelectCheckbox(
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
            const _HeaderCell(width: _kColRefWidth, label: 'Reference'),
            const _HeaderCell(flex: _kColTitleFlex, label: 'Notification'),
            const _HeaderCell(width: _kColTypeWidth, label: 'Type'),
            const _HeaderCell(flex: _kColActorFlex, label: 'Actor'),
            const _HeaderCell(
              width: _kColReceivedWidth,
              label: 'Received',
              alignRight: true,
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
    this.alignRight = false,
  }) : assert(
         label != null || child != null,
         'Pass either label or child to _HeaderCell.',
       );
  final String? label;
  final Widget? child;
  final int? flex;
  final double? width;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final inner =
        child ??
        Text(
          label!,
          style: ZebuTextStyles.tableHeader(context),
          textAlign: alignRight ? TextAlign.right : TextAlign.left,
        );
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: ZebuSpacing.s3,
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
    this.alignRight = false,
  });
  final Widget child;
  final int? flex;
  final double? width;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: 8,
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

class _NotificationGroupRow extends StatefulWidget {
  const _NotificationGroupRow({
    required this.group,
    required this.onTap,
    required this.selected,
    required this.onToggleSelected,
  });

  /// One collapsed object (all of an agent's notifications for a ticket/task).
  final NotificationGroup group;
  final VoidCallback onTap;

  /// True when the row's leading checkbox is ticked. Drives the object-level
  /// bulk-action selection on the parent screen.
  final bool selected;

  /// Fired when the row's leading checkbox is toggled.
  final VoidCallback onToggleSelected;

  @override
  State<_NotificationGroupRow> createState() => _NotificationGroupRowState();
}

class _NotificationGroupRowState extends State<_NotificationGroupRow> {
  bool _hover = false;

  // Rounded icon set for the Type-column pill, keyed on the latest activity's
  // event — raw osTicket events (see inbox.inc.php $LABELS).
  IconData get _eventIcon => switch (widget.group.latest.event) {
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

  /// Tone the Type-column icon + label by object type (Task = green,
  /// Ticket = accent blue) so the column scans as two colour bands.
  /// One hue per type, so the column is legible from the icon alone.
  ///
  /// Tickets take the product accent — they are the primary object here.
  /// Tasks take teal, which is far enough round the wheel to separate at
  /// 13 px and is already in the avatar palette, so it is not a new colour.
  Color _typeTone(ZebuTheme t) => widget.group.type == 'task'
      ? (t.isLight ? const Color(0xFF0E7490) : const Color(0xFF5CC8D8))
      : t.accent;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final g = widget.group;
    final latest = g.latest;
    final typeTone = _typeTone(t);
    final unread = g.hasUnread;
    final snippet = (latest.body != null && latest.body!.isNotEmpty)
        ? Fmt.stripHtml(latest.body)
        : null;
    final isTask = g.type == 'task';
    // Latest activity as the row's headline; a "(N)" prefix flags a collapsed
    // object that carries more than one activity.
    final headline = snippet == null || snippet.isEmpty
        ? latest.displayLabel
        : '${latest.displayLabel} — $snippet';
    final title = g.count > 1 ? '(${g.count}) $headline' : headline;

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
            color: _hover ? t.bgHover : (unread ? t.accentSoft : t.bgElevated),
            border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
          ),
          child: SizedBox(
            height: _kRowHeight,
            child: Row(
              children: [
                _BodyCell(
                  width: _kColSelectWidth,
                  // Nested GestureDetector swallows the tap so it doesn't
                  // bubble to the row's own onTap (which opens the panel).
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onToggleSelected,
                      child: SelectCheckbox(
                        value: widget.selected,
                        onChanged: (_) => widget.onToggleSelected(),
                      ),
                    ),
                  ),
                ),
                _BodyCell(
                  width: _kColRefWidth,
                  child: Text(
                    '#${g.objectId}',
                    style: ZebuTextStyles.tableCell(
                      context,
                      color: t.accent,
                      fontWeight: ZebuFonts.semiBold,
                    ).withTabularNums(),
                  ),
                ),
                _BodyCell(
                  flex: _kColTitleFlex,
                  // Unread is carried by the row itself — a bold title beside
                  // an accent dot, plus the row's tinted fill. A whole column
                  // spelling out "Unread" / "Read" repeated on every line what
                  // the line already showed.
                  child: Row(
                    children: [
                      if (unread) ...[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: t.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: ZebuSpacing.s2),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZebuTextStyles.tableCell(
                            context,
                            fontWeight: unread
                                ? ZebuFonts.semiBold
                                : ZebuFonts.medium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _BodyCell(
                  width: _kColTypeWidth,
                  // Icon plus a coloured word, not a filled chip. Every row
                  // carries this cell, so a pill on each one banded the whole
                  // table — and the column only ever holds two values, which
                  // an outline glyph separates on its own.
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Glyph in a tinted tile, label in ordinary ink — the
                      // same device the ticket sidebar uses for its field
                      // icons. Colouring the word as well made the column
                      // read as a link.
                      Icon(
                        isTask
                            ? Icons.assignment_outlined
                            : Icons.confirmation_number_outlined,
                        size: 16,
                        color: typeTone,
                      ),
                      const SizedBox(width: ZebuSpacing.s2),
                      // Flexible so a narrow viewport ellipsises the word
                      // instead of overflowing the cell — "Ticket" at 14 px
                      // beside a 22 px tile was 0.7 px over the old width.
                      Flexible(
                        child: Text(
                          isTask ? 'Task' : 'Ticket',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ZebuTextStyles.tableCell(
                            context,
                            fontWeight: ZebuFonts.medium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _BodyCell(
                  flex: _kColActorFlex,
                  child: ZebuGridTextCell(text: latest.actor ?? ''),
                ),
                _BodyCell(
                  width: _kColReceivedWidth,
                  alignRight: true,
                  child: Text(
                    g.lastActivity != null ? Fmt.ago(g.lastActivity) : '—',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.right,
                    style: ZebuTextStyles.tableCell(context).withTabularNums(),
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

// ---------------------------------------------------------------------------
// Skeleton loader — rendered by [PagedListView.loadingBuilder] on the first
// paint before notification rows arrive. Mirrors the real row's column grid
// so the transition to live data is a swap-in-place rather than a layout
// jump. A single shared pulse controller drives the greyscale opacity across
// every placeholder block for a synchronised "one heartbeat" feel.
// ---------------------------------------------------------------------------
