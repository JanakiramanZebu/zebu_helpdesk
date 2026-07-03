import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_notification.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/paged_list_view.dart';
import '../../widgets/segmented_tabs.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/user_avatar.dart';

/// Filter tabs, matching the ticket/task list pattern. Filtering is client-side
/// (the `/notifications` endpoint returns the full inbox).
const _views = <({String key, String label})>[
  (key: 'all', label: 'All'),
  (key: 'unread', label: 'Unread'),
  (key: 'tickets', label: 'Tickets'),
  (key: 'tasks', label: 'Tasks'),
  (key: 'mentions', label: 'Mentions'),
];

/// The agent's notification inbox (`GET /notifications`), styled to match the
/// Tickets / Tasks list screens: a list-screen app bar with a pill search
/// field, segmented filter tabs, and card-based rows.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  int _refreshKey = 0;
  int? _total;
  String _view = 'all';
  String _search = '';
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  void _refresh() {
    setState(() => _refreshKey++);
    ref.invalidate(unreadCountProvider);
  }

  void _toast(String msg) => AppSnack.error(context, msg);

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final next = value.trim().toLowerCase();
      if (next != _search && mounted) setState(() => _search = next);
    });
  }

  void _applySearch(String value) {
    _debounce?.cancel();
    final next = value.trim().toLowerCase();
    if (next != _search) setState(() => _search = next);
  }

  Future<void> _markAllRead() async {
    try {
      await ref.read(notificationsRepositoryProvider).readAll();
      _refresh();
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
      await ref.read(notificationsRepositoryProvider).deleteAll();
      _refresh();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _deleteOne(AppNotification n) async {
    try {
      await ref.read(notificationsRepositoryProvider).deleteOne(n.id);
      ref.invalidate(unreadCountProvider);
    } on ApiException catch (e) {
      _toast(e.message);
      _refresh();
    }
  }

  /// Mark a single notification read without opening it (swipe-right action).
  Future<void> _markRead(AppNotification n) async {
    if (n.read) return;
    try {
      await ref.read(notificationsRepositoryProvider).read(n.id);
      ref.invalidate(unreadCountProvider);
      _refresh();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _open(AppNotification n) async {
    try {
      await ref.read(notificationsRepositoryProvider).read(n.id);
    } on ApiException catch (_) {
      // Best-effort; navigate regardless.
    }
    ref.invalidate(unreadCountProvider);
    if (!mounted) return;
    if (n.type == 'task') {
      context.push(Routes.task(n.objectId));
    } else {
      context.push(Routes.ticket(n.objectId));
    }
  }

  /// Client-side tab + search filter, mirroring the ticket/task list screens.
  bool _matches(AppNotification n) {
    final viewOk = switch (_view) {
      'unread' => !n.read,
      'tickets' => n.type == 'ticket',
      'tasks' => n.type == 'task',
      'mentions' => n.event == 'message' || n.event == 'note',
      _ => true,
    };
    if (!viewOk) return false;

    if (_search.isEmpty) return true;
    return n.displayLabel.toLowerCase().contains(_search) ||
        (n.actor ?? '').toLowerCase().contains(_search) ||
        '${n.objectId}'.contains(_search);
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

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Inbox'),
            if (_total != null) AppText.paraText(context, '$_total total'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            onSelected: (v) {
              if (v == 'mark_all') _markAllRead();
              if (v == 'delete_all') _deleteAll();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'mark_all',
                child: Row(
                  children: [
                    Icon(Icons.done_all, size: 20),
                    SizedBox(width: 12),
                    Text('Mark all read'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Delete all'),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(90),
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
              SegmentedTabs(
                items: _views,
                selectedKey: _view,
                onSelected: (k) => setState(() => _view = k),
              ),
            ],
          ),
        ),
      ),
      body: PagedListView<AppNotification>(
        fabClearance: true,
        skeleton: const ListSkeleton(),
        separated: true,
        refreshKey: '$_view|$_refreshKey',
        itemFilter: _matches,
        onTotalChanged: (t) {
          if (mounted && t != _total) setState(() => _total = t);
        },
        emptyMessage: 'No notifications',
        emptyHint: 'You are all caught up.',
        emptyIcon: Icons.notifications_none,
        fetch: (page) => repo.list(page: page),
        itemBuilder: (context, n) => _NotificationRow(
          n: n,
          onTap: () => _open(n),
          onDelete: () => _deleteOne(n),
          onMarkRead: () => _markRead(n),
        ),
      ),
    );
  }
}

/// A single notification, rendered as a Gmail-style edge-to-edge row: a type
/// avatar with an unread dot, an unread left rail, the message (bold when
/// unread), an event chip, and a top-right timestamp. Swipe left to delete,
/// swipe right to mark read.
class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.n,
    required this.onTap,
    required this.onDelete,
    required this.onMarkRead,
  });

  final AppNotification n;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onMarkRead;

  bool get _isTask => n.type == 'task';

  /// (label, color) for the event chip on the right of the header row.
  ({String label, Color color})? _eventChip() => switch (n.event) {
    'message' => (label: 'Reply', color: AppTheme.open),
    'note' => (label: 'Note', color: AppTheme.brandLight),
    'assigned' => (label: 'Assigned', color: AppTheme.brand),
    'transferred' => (label: 'Transferred', color: AppTheme.warning),
    'overdue' => (label: 'Overdue', color: AppTheme.overdue),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = !n.read;
    final chip = _eventChip();
    final actor = (n.actor ?? '').trim();
    final refLabel = _isTask ? 'Task #${n.objectId}' : 'Ticket #${n.objectId}';

    return Dismissible(
      key: ValueKey('notif-${n.id}'),
      // Swipe left (endToStart) = delete; swipe right (startToEnd) = mark read.
      // A read notification can't be marked-read again, so only allow delete.
      direction: unread
          ? DismissDirection.horizontal
          : DismissDirection.endToStart,
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          onMarkRead(); // mark read in place — don't remove the row
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
        color: unread
            ? scheme.primary.withValues(alpha: 0.05)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Unread left rail.
                Container(
                  width: 4,
                  color: unread ? scheme.primary : Colors.transparent,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Leading: type-tinted avatar with an unread dot.
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            UserAvatar(
                              name: actor.isEmpty ? refLabel : actor,
                              radius: 19,
                            ),
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
                                  _isTask
                                      ? Icons.task_alt
                                      : Icons.confirmation_number_outlined,
                                  size: 12,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Header: reference + time.
                              Row(
                                children: [
                                  Expanded(
                                    child: AppText.paraText(
                                      context,
                                      refLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      color: scheme.primary,
                                      fw: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AppText.captionText(
                                    context,
                                    Fmt.ago(n.created),
                                    color: scheme.onSurfaceVariant,
                                    fw: unread ? 2 : 0,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              // Message.
                              AppText.subText(
                                context,
                                n.displayLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                fw: unread ? 2 : 3,
                                color: unread
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                                lineHeight: 1.3,
                              ),
                              if (actor.isNotEmpty || chip != null) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    if (actor.isNotEmpty)
                                      Expanded(
                                        child: AppText.paraText(
                                          context,
                                          actor,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      )
                                    else
                                      const Spacer(),
                                    if (chip != null) ...[
                                      const SizedBox(width: 8),
                                      _EventChip(chip: chip),
                                    ],
                                  ],
                                ),
                              ],
                            ],
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

class _EventChip extends StatelessWidget {
  const _EventChip({required this.chip});
  final ({String label, Color color}) chip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: chip.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: AppText.custmText(
        context,
        chip.label,
        fs: 10.5,
        color: chip.color,
        fw: 2,
      ),
    );
  }
}
