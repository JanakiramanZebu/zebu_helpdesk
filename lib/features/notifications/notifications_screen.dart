import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/paginated.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_notification.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/filter_chip_tabs.dart';
import '../../widgets/glass.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';

/// Filter tabs. osTicket's Activity Inbox offers All and Unread (n); the
/// server groups by object and can filter `type=ticket` / `type=task` with a
/// real per-type total behind it (`/notifications/count` -> `by_type`), so the
/// mobile inbox carries those two views as well. Every view narrows in the
/// query — nothing here filters a loaded page, because a page is now counted in
/// cards and filtering it locally would hide cards the server never sent.
const _views = <({String key, String label})>[
  (key: 'all', label: 'All'),
  (key: 'unread', label: 'Unread'),
  (key: 'ticket', label: 'Tickets'),
  (key: 'task', label: 'Tasks'),
];

/// event => human label, mirroring `$LABELS` in `include/staff/inbox.inc.php`.
/// The server already resolves the per-viewer wording for `assigned`
/// ("Assigned to you" / "Assigned to that agent") and sends it as `label`.
const _eventLabels = <String, String>{
  'message': 'New reply',
  'note': 'Internal note',
  'assigned': 'Assigned to you',
  'transfer': 'Transferred',
  'status': 'Status changed',
  'mention': 'You were mentioned',
  'overdue': 'Overdue',
  'new_unassigned': 'New unassigned',
};

/// The snippet/timeline label for one activity — `label` when the server
/// resolved one, else the static event label, else the raw event.
String _labelFor(AppNotification n) =>
    n.label ?? _eventLabels[n.event] ?? n.event;

/// The agent's notification inbox (`GET /notifications`), ported from the web's
/// Activity Inbox (`include/staff/inbox.inc.php` + `scp/js/inbox.js`): All /
/// Unread / Tickets / Tasks filters, one card per ticket/task showing
/// `#number`, the subject, a TICKET/TASK chip and an `actor · label · time`
/// snippet, and a selected card that expands into the web's recent-activity
/// detail panel. The pill search field and actor avatars are mobile additions
/// the web has no room for.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  int _refreshKey = 0;
  int? _total;
  // Cards swiped away this session, keyed `type:objectId`. A dismissed
  // Dismissible must leave the tree immediately, so we filter these out
  // synchronously (before the network delete completes) rather than waiting for
  // a refetch.
  final Set<String> _deleted = {};
  String _view = 'all';

  /// The selected card, whose recent-activity detail is expanded below it —
  /// the mobile stand-in for the web's right-hand `.inbox-detail` panel.
  String? _expandedKey;

  /// Objects marked read in place this session. inbox.js drops `.unread` and
  /// the dot on select without reloading the list, so the card must stay put
  /// (and stay visible under the Unread filter) until the next refresh.
  final Set<String> _readKeys = {};
  String _search = '';
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  /// The server filters the list; these map the selected chip to its query.
  bool? get _readFilter => _view == 'unread' ? false : null;
  String? get _typeFilter =>
      _view == 'ticket' || _view == 'task' ? _view : null;

  /// Semantic dot color per filter chip: unread = red (attention, matches the
  /// nav badge), the type views take the card chip's own tint.
  static Color _viewColor(String key) => switch (key) {
    'unread' => AppTheme.overdue,
    'ticket' => AppTheme.brandLight,
    'task' => AppTheme.warning,
    _ => AppTheme.closed, // 'all'
  };

  void _refresh() {
    setState(() {
      _refreshKey++;
      // The list reloads from the server (which no longer has the deleted
      // rows), so the local tombstones are no longer needed.
      _deleted.clear();
      _readKeys.clear();
      _expandedKey = null;
    });
    ref.invalidate(notificationCountsProvider);
  }

  void _toast(String msg) => AppSnack.error(context, msg);

  void _ok(String msg) {
    if (mounted) AppSnack.success(context, msg);
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final next = value.trim();
      if (next != _search && mounted) setState(() => _search = next);
    });
  }

  void _applySearch(String value) {
    _debounce?.cancel();
    final next = value.trim();
    if (next != _search) setState(() => _search = next);
  }

  Future<void> _markAllRead() async {
    try {
      await ref.read(notificationsRepositoryProvider).readAll();
      _refresh();
      _ok('All notifications marked read');
    } on ApiException catch (e) {
      _toast(e.message);
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
      final deleted =
          await ref.read(notificationsRepositoryProvider).deleteAll();
      _refresh();
      _ok(deleted == 1
          ? '1 notification deleted'
          : '$deleted notifications deleted');
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  /// Delete a card's notifications. There is no delete-by-object endpoint, so
  /// clear each activity the group carries.
  Future<void> _deleteGroup(NotificationGroup g) async {
    // Drop the card from the tree this frame — a dismissed Dismissible must not
    // stay mounted, or Flutter asserts.
    final ids = g.activities.map((a) => a.id).toList();
    setState(() => _deleted.add(g.key));
    try {
      await Future.wait(
        ids.map(
          (id) => ref.read(notificationsRepositoryProvider).deleteOne(id),
        ),
      );
      ref.invalidate(notificationCountsProvider);
      _ok(ids.length == 1
          ? 'Notification deleted'
          : '${ids.length} notifications deleted');
    } on ApiException catch (e) {
      // Restore the card so the failed delete isn't silently lost.
      setState(() => _deleted.remove(g.key));
      _toast(e.message);
      _refresh();
    }
  }

  /// Mark a whole object's notifications read without opening it (swipe-right)
  /// — one `read-object` call, not one per unread activity.
  Future<void> _markGroupRead(NotificationGroup g) async {
    if (!g.hasUnread || _readKeys.contains(g.key)) return;
    try {
      await ref
          .read(notificationsRepositoryProvider)
          .readObject(g.type, g.objectId);
      if (mounted) setState(() => _readKeys.add(g.key));
      ref.invalidate(notificationCountsProvider);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  /// Select a card — the web's `selectCard()` in `scp/js/inbox.js`: reveal the
  /// object's recent activity and mark ALL of its notifications read in place
  /// (POST /notifications/read-object), without reloading the list. Tapping the
  /// selected card again collapses it.
  Future<void> _selectGroup(NotificationGroup g) async {
    final opening = _expandedKey != g.key;
    setState(() => _expandedKey = opening ? g.key : null);
    if (!opening || !g.hasUnread || _readKeys.contains(g.key)) return;
    setState(() => _readKeys.add(g.key));
    try {
      await ref
          .read(notificationsRepositoryProvider)
          .readObject(g.type, g.objectId);
      ref.invalidate(notificationCountsProvider);
    } on ApiException catch (_) {
      if (mounted) setState(() => _readKeys.remove(g.key));
    }
  }

  /// Open the ticket/task itself — the panel's "Open" / "View All Activity"
  /// links. The route target is the group's `object_id`, never an activity id
  /// (that only identifies a notification row, and routing on it is what used
  /// to land agents on "ticket not available"). Selecting already marked the
  /// object read; do it again defensively for the case where the card was
  /// opened without being selected first. [tab] pre-selects a tab on the detail
  /// screen: "View All Activity" asks for the Activity tab (the object's full
  /// event log), "Open" for the default.
  Future<void> _openGroup(NotificationGroup g, {String? tab}) async {
    try {
      await ref
          .read(notificationsRepositoryProvider)
          .readObject(g.type, g.objectId);
    } on ApiException catch (_) {
      // Best-effort; navigate regardless.
    }
    ref.invalidate(notificationCountsProvider);
    if (!mounted) return;
    // Await the detail route so that on return we refetch — the object is now
    // read on the server, so a refresh clears the card's unread state.
    if (g.isTask) {
      await context.push(Routes.task(g.objectId, tab: tab));
    } else {
      await context.push(Routes.ticket(g.objectId, tab: tab));
    }
    if (mounted) _refresh();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(notificationsRepositoryProvider);
    // Object-based totals: `unread` can no longer contradict the Unread view's
    // own `pagination.total`, and `by_type` gives the Tickets/Tasks chips a
    // real number instead of one derived from the pages that happen to be
    // loaded.
    final counts = ref
        .watch(notificationCountsProvider)
        .maybeWhen(data: (c) => c, orElse: () => NotificationCounts.empty);
    // Bumped by the shell when the app returns to the foreground, and by an
    // incoming push. Part of the list's refresh key below.
    final resumed = ref.watch(notificationsChangedProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Inbox'),
            if (_total != null && _total! > 0)
              AppText.paraText(
                context,
                '$_total ${_total == 1 ? 'conversation' : 'conversations'}',
              ),
          ],
        ),
        actions: [
          _InboxMenuButton(
            onMarkAllRead: _markAllRead,
            onDeleteAll: _deleteAll,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(98),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: AppSearchField(
                  controller: _searchCtrl,
                  hintText: 'Search notifications',
                  onChanged: _onSearchChanged,
                  onSubmitted: _applySearch,
                  onClear: () => _applySearch(''),
                ),
              ),
              FilterChipTabs(
                items: _views,
                selectedKey: _view,
                // Each chip badges the number of cards its own view lists, so
                // a chip can be checked against the list it opens.
                counts: {
                  if (counts.total > 0) 'all': counts.total,
                  if (counts.unread > 0) 'unread': counts.unread,
                  if (counts.totalOf('ticket') > 0)
                    'ticket': counts.totalOf('ticket'),
                  if (counts.totalOf('task') > 0)
                    'task': counts.totalOf('task'),
                },
                colorFor: _viewColor,
                onSelected: (k) {
                  if (k == _view) return;
                  setState(() {
                    _view = k;
                    _expandedKey = null;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      body: Glass.listBackdrop(
        context: context,
        child: _InboxList(
          // `resumed` folds in the app-resume signal: alerts that arrived in
          // the tray while we were backgrounded are already on the server, so
          // the list must refetch rather than keep the pre-push page.
          refreshKey: '$_view|$_search|$_refreshKey|$resumed',
          excludeKeys: _deleted,
          onTotal: (n) {
            if (mounted && n != _total) setState(() => _total = n);
          },
          onRefreshed: () => ref.invalidate(notificationCountsProvider),
          // A page is a page of cards now — the server does the grouping, the
          // view filter and the text match, so 25 cards is 25 rows on screen
          // and nothing is dropped after the fetch.
          fetchPage: (page) => repo.list(
            page: page,
            limit: 25,
            read: _readFilter,
            type: _typeFilter,
            q: _search.isEmpty ? null : _search,
          ),
          cardBuilder: (context, g) => _NotificationGroupCard(
            group: g,
            unread: g.hasUnread && !_readKeys.contains(g.key),
            expanded: _expandedKey == g.key,
            onTap: () => _selectGroup(g),
            onOpen: () => _openGroup(g),
            onOpenActivity: () => _openGroup(g, tab: 'activity'),
            onDelete: () => _deleteGroup(g),
            onMarkRead: () => _markGroupRead(g),
          ),
        ),
      ),
    );
  }
}

/// App-bar overflow menu for the Inbox, styled to match the list-screen
/// download menu: a rounded, elevated popup whose rows pair a tinted icon tile
/// with a bold label. "Delete all" reads in the error color to signal it's
/// destructive.
class _InboxMenuButton extends StatelessWidget {
  const _InboxMenuButton({
    required this.onMarkAllRead,
    required this.onDeleteAll,
  });

  final VoidCallback onMarkAllRead;
  final VoidCallback onDeleteAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'More',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      elevation: 8,
      color: scheme.surface,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      icon: const Icon(Icons.more_vert),
      onSelected: (v) {
        if (v == 'mark_all') onMarkAllRead();
        if (v == 'delete_all') onDeleteAll();
      },
      itemBuilder: (context) => [
        _menuItem(
          context,
          value: 'mark_all',
          icon: Icons.done_all,
          label: 'Mark all read',
          tint: AppTheme.open,
        ),
        _menuItem(
          context,
          value: 'delete_all',
          icon: Icons.delete_sweep_outlined,
          label: 'Delete all',
          tint: scheme.error,
          danger: true,
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
    BuildContext context, {
    required String value,
    required IconData icon,
    required String label,
    required Color tint,
    bool danger = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 48,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: tint),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: danger ? tint : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Infinite-scroll list of inbox cards. `GET /notifications` returns one entry
/// per ticket/task with its events nested, already filtered and ordered the way
/// the staff web inbox orders them, so this only appends pages — there is no
/// client-side grouping, de-duplication or filtering left to do, and
/// `pagination.total` is a straight count of cards.
class _InboxList extends StatefulWidget {
  const _InboxList({
    required this.fetchPage,
    required this.refreshKey,
    required this.excludeKeys,
    required this.cardBuilder,
    required this.onTotal,
    required this.onRefreshed,
  });

  final Future<Paginated<NotificationGroup>> Function(int page) fetchPage;
  final Object refreshKey;

  /// Group keys to hide (optimistic-delete tombstones).
  final Set<String> excludeKeys;
  final Widget Function(BuildContext context, NotificationGroup group)
  cardBuilder;

  /// The server's card total for the current view.
  final ValueChanged<int> onTotal;

  /// Pull-to-refresh reloads the list in place; the host uses this to refetch
  /// the unread badge alongside it.
  final VoidCallback onRefreshed;

  @override
  State<_InboxList> createState() => _InboxListState();
}

class _InboxListState extends State<_InboxList> {
  final _scroll = ScrollController();
  final List<NotificationGroup> _groups = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  bool _initial = true;
  Object? _error;
  int? _lastNotifiedTotal;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant _InboxList old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    if (!reset && !_hasMore) return;
    setState(() {
      _loading = true;
      if (reset) {
        _initial = true;
        _error = null;
        _page = 1;
        _hasMore = true;
        _groups.clear();
      }
    });
    try {
      final result = await widget.fetchPage(_page);
      if (!mounted) return;
      setState(() {
        _groups.addAll(result.items);
        _hasMore = result.hasMore && result.items.isNotEmpty;
        _page += 1;
        _initial = false;
      });
      _notifyTotal(result.total);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Surface the server's card total to the host — only when it changes, so we
  /// don't schedule a redundant setState on every page.
  void _notifyTotal(int total) {
    if (total == _lastNotifiedTotal) return;
    _lastNotifiedTotal = total;
    widget.onTotal(total);
  }

  Future<void> _refresh() async {
    widget.onRefreshed();
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_initial && _loading) return const ListSkeleton();
    if (_error != null && _groups.isEmpty) {
      return ErrorView(error: _error!, onRetry: () => _load(reset: true));
    }

    final groups = widget.excludeKeys.isEmpty
        ? _groups
        : _groups
              .where((g) => !widget.excludeKeys.contains(g.key))
              .toList(growable: false);

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final listPadding = EdgeInsets.only(top: 6, bottom: bottomInset + 150);

    if (groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        // Scrollable was not enough on its own: 360px inside a taller
        // viewport still has nothing to overscroll.
        child: const RefreshableState(
          child: EmptyView(
            icon: Icons.notifications_none,
            message: 'No notifications',
            hint: 'You are all caught up.',
          ),
        ),
      );
    }

    return Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          controller: _scroll,
          physics: alwaysScrollablePhysics,
          padding: listPadding,
          itemCount: groups.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= groups.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ),
              );
            }
            final g = groups[index];
            final card = widget.cardBuilder(context, g);
            final child = index < groups.length - 1
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      card,
                      Divider(
                        height: 1,
                        thickness: 0.3,
                        indent: 66,
                        color: Theme.of(context).colorScheme.outlineVariant
                            .withValues(alpha: 0.4),
                      ),
                    ],
                  )
                : card;
            return RepaintBoundary(child: child);
          },
        ),
      ),
    );
  }
}

/// One collapsed inbox card = all of an agent's notifications for a single
/// ticket/task, laid out like osTicket's `.inbox-card`: an unread rail and dot,
/// `#number`, the subject, a TICKET/TASK chip and a single
/// `actor · label · time` snippet — plus the actor avatar the mobile design
/// keeps. Tapping selects the card, which marks the object read in place and
/// expands its recent activity (the web's `.inbox-detail` panel, inlined).
/// Swipe left to delete the object's notifications, swipe right to mark read.
class _NotificationGroupCard extends StatelessWidget {
  const _NotificationGroupCard({
    required this.group,
    required this.unread,
    required this.expanded,
    required this.onTap,
    required this.onOpen,
    required this.onOpenActivity,
    required this.onDelete,
    required this.onMarkRead,
  });

  final NotificationGroup group;

  /// Unread *for the viewer* — false once the card has been selected this
  /// session, even though the loaded rows still say otherwise.
  final bool unread;

  /// True while this card is the selected one and its detail is showing.
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  /// Opens the object on its **Activity** tab — the full event log this panel
  /// only shows the latest five of.
  final VoidCallback onOpenActivity;
  final VoidCallback onDelete;
  final VoidCallback onMarkRead;

  bool get _isTask => group.isTask;

  /// The web panel windows each object's activity to the latest five and offers
  /// "View All Activity" beyond that (`rn <= 5`, `total_count > 5`).
  static const _maxActivities = 5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actor = (group.latest?.actor ?? '').trim();
    final refLabel = _isTask
        ? 'Task ${group.displayRef}'
        : 'Ticket ${group.displayRef}';

    return Dismissible(
      key: ValueKey('notif-group-${group.key}'),
      // Swipe left (endToStart) = delete the object's notifications; swipe right
      // (startToEnd) = mark them all read. A fully-read card can only be
      // deleted, so drop the mark-read direction there.
      direction: unread
          ? DismissDirection.horizontal
          : DismissDirection.endToStart,
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onMarkRead(); // mark read in place — don't remove the card
          return false;
        }
        return true; // endToStart → let it dismiss, then delete
      },
      onDismissed: (_) => onDelete(),
      background: _SwipeBg(
        color: AppTheme.open,
        icon: Icons.mark_email_read_outlined,
        label: 'Mark read',
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _SwipeBg(
        color: scheme.error,
        icon: Icons.delete_outline,
        label: 'Delete',
        alignment: Alignment.centerRight,
      ),
      child: Material(
        // `.inbox-card.selected` tints with --accent-muted.
        color: expanded
            ? scheme.primary.withValues(alpha: 0.05)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // `.inbox-card.unread { border-left:3px solid var(--accent) }`
                Container(
                  width: 3,
                  color: unread ? scheme.primary : Colors.transparent,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _TypeAvatar(
                              name: actor.isEmpty ? refLabel : actor,
                              isTask: _isTask,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _titleRow(context),
                                  const SizedBox(height: 3),
                                  _snippet(context),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (expanded) _detail(context),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// `● #009893  Subject…  [TICKET] [3]` — the web's `.inbox-card-title`,
  /// with the object's `unread_count` badged at the end: one card can stand for
  /// several unread events, and the count is the server's, not a tally of the
  /// activities this payload happened to carry.
  Widget _titleRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (unread) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
        ],
        AppText.captionText(
          context,
          group.displayRef,
          color: scheme.onSurfaceVariant,
          fw: 2,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: AppText.subText(
            context,
            group.displaySubject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            fw: unread ? 1 : 2,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(width: 6),
        _TypeChip(isTask: _isTask),
        if (unread && group.unreadCount > 1) ...[
          const SizedBox(width: 4),
          _UnreadBadge(count: group.unreadCount),
        ],
      ],
    );
  }

  /// `actor · label · time` on one clipped line — `.inbox-card-snippet`.
  Widget _snippet(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final latest = group.latest;
    final actor = (latest?.actor ?? '').trim();
    final base = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11.5,
      height: 1.3,
      color: scheme.onSurfaceVariant,
    );
    final sep = TextSpan(
      text: '  ·  ',
      style: base?.copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
    return Text.rich(
      TextSpan(
        children: [
          if (actor.isNotEmpty) ...[
            TextSpan(
              text: actor,
              style: base?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            sep,
          ],
          if (latest != null) ...[
            TextSpan(text: _labelFor(latest), style: base),
            sep,
          ],
          TextSpan(text: Fmt.ago(group.lastActivity), style: base),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// The expanded panel: the latest five activities on a timeline rail, then
  /// "View All Activity" (when more were collapsed) and "Open".
  Widget _detail(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final acts = group.activities.take(_maxActivities).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(
            height: 1,
            thickness: 0.4,
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < acts.length; i++)
            _ActivityRow(item: acts[i], isLast: i == acts.length - 1),
          const SizedBox(height: 6),
          Row(
            children: [
              if (group.count > acts.length)
                _PanelLink(
                  label: 'View All Activity',
                  onTap: onOpenActivity,
                ),
              const Spacer(),
              _PanelLink(label: 'Open', onTap: onOpen),
            ],
          ),
        ],
      ),
    );
  }
}

/// The card's leading avatar: the actor's initials with a small ticket/task
/// badge, so the object type reads even before the chip.
class _TypeAvatar extends StatelessWidget {
  const _TypeAvatar({required this.name, required this.isTask});

  final String name;
  final bool isTask;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        UserAvatar(name: name, radius: 19),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isTask ? Icons.task_alt : Icons.confirmation_number_outlined,
              size: 12,
              color: scheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// `.inbox-chip` — a small uppercase TICKET / TASK pill (blue / amber).
class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.isTask});

  final bool isTask;

  @override
  Widget build(BuildContext context) {
    final color = isTask ? AppTheme.warning : AppTheme.brandLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: AppText.custmText(
        context,
        isTask ? 'TASK' : 'TICKET',
        fs: 9.5,
        fw: 2,
        color: color,
      ),
    );
  }
}

/// The card's `unread_count` — a small filled pill, shown only when the object
/// carries more than one unread event (a single one is already said by the dot).
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(9),
      ),
      child: AppText.custmText(
        context,
        count > 99 ? '99+' : '$count',
        fs: 10,
        fw: 2,
        color: scheme.onPrimary,
        align: TextAlign.center,
      ),
    );
  }
}

/// One activity in the expanded panel — `.inbox-activity`: an initials avatar
/// on a continuous rail, an `actor · label · time` head, and (for replies only)
/// the message body in a clamped bubble with a See more / See less toggle.
class _ActivityRow extends StatefulWidget {
  const _ActivityRow({required this.item, required this.isLast});

  final AppNotification item;
  final bool isLast;

  @override
  State<_ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<_ActivityRow> {
  bool _showFull = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = widget.item;
    final actor = (n.actor ?? '').trim();
    // Only real replies carry useful text; assigned/status/transfer do not.
    final body = n.event == 'message' ? (n.body ?? '').trim() : '';
    final muted = theme.textTheme.bodySmall?.copyWith(
      fontSize: 11.5,
      height: 1.3,
      color: scheme.onSurfaceVariant,
    );
    final sep = TextSpan(
      text: '  ·  ',
      style: muted?.copyWith(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                UserAvatar(name: actor.isEmpty ? 'System' : actor, radius: 12),
                if (!widget.isLast)
                  Expanded(
                    child: Center(
                      child: Container(
                        width: 2,
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.isLast ? 0 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: actor.isEmpty ? 'System' : actor,
                          style: muted?.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        sep,
                        TextSpan(
                          text: _labelFor(n),
                          style: muted?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        sep,
                        TextSpan(text: Fmt.ago(n.created), style: muted),
                      ],
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: AppText.paraText(
                        context,
                        body,
                        maxLines: _showFull ? null : 5,
                        overflow: _showFull
                            ? TextOverflow.clip
                            : TextOverflow.ellipsis,
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    // The web offers the toggle past 70 characters.
                    if (body.length > 70)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _showFull = !_showFull),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: AppText.captionText(
                            context,
                            _showFull ? 'See less' : 'See more',
                            color: scheme.primary,
                            fw: 2,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.inbox-panel-open` / `.inbox-viewall` — a small accent text action with a
/// trailing chevron.
class _PanelLink extends StatelessWidget {
  const _PanelLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText.captionText(context, label, color: scheme.primary, fw: 2),
            Icon(Icons.chevron_right, size: 15, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// The colored background revealed behind a swiped notification row.
class _SwipeBg extends StatelessWidget {
  const _SwipeBg({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final leading = alignment == Alignment.centerLeft;
    final content = [
      Icon(icon, color: Colors.white, size: 22),
      const SizedBox(width: 8),
      AppText.subText(context, label, color: Colors.white, fw: 1),
    ];
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: leading ? content : content.reversed.toList(),
      ),
    );
  }
}
