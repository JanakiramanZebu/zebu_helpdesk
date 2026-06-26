import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../models/app_notification.dart';
import '../../providers.dart';
import '../../widgets/paged_list_view.dart';

/// The agent's notification inbox (`GET /notifications`).
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  int _refreshKey = 0;

  void _refresh() {
    setState(() => _refreshKey++);
    ref.invalidate(unreadCountProvider);
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _markAllRead() async {
    try {
      await ref.read(notificationsRepositoryProvider).readAll();
      _refresh();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete all notifications?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
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

  IconData _iconFor(String event) => switch (event) {
        'assigned' => Icons.person_add_alt,
        'message' => Icons.mail_outline,
        'note' => Icons.note_outlined,
        'transferred' => Icons.swap_horiz,
        'overdue' => Icons.warning_amber_rounded,
        _ => Icons.notifications_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(notificationsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _markAllRead,
            child: const Text('Mark all read'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete_all') _deleteAll();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete_all', child: Text('Delete all')),
            ],
          ),
        ],
      ),
      body: PagedListView<AppNotification>(
        refreshKey: _refreshKey,
        emptyMessage: 'No notifications',
        emptyHint: 'You are all caught up.',
        emptyIcon: Icons.notifications_none,
        fetch: (page) => repo.list(page: page),
        itemBuilder: (context, n) => _NotificationTile(
          n: n,
          icon: _iconFor(n.event),
          onTap: () => _open(n),
          onDismissed: () => _deleteOne(n),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.n,
    required this.icon,
    required this.onTap,
    required this.onDismissed,
  });

  final AppNotification n;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      if (n.body != null && n.body!.isNotEmpty) Fmt.stripHtml(n.body),
      if (n.actor != null && n.actor!.isNotEmpty) n.actor!,
      if (n.created != null) Fmt.ago(n.created),
    ];

    return Dismissible(
      key: ValueKey('notif-${n.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        color: theme.colorScheme.error,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(icon, color: theme.colorScheme.primary, size: 20),
        ),
        title: Text(
          n.displayLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: n.read ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
        subtitle: subtitleParts.isEmpty
            ? null
            : Text(
                subtitleParts.join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
        trailing: n.read
            ? null
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
        onTap: onTap,
      ),
    );
  }
}
