import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_theme.dart';
import '../../models/app_notification.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
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
    required this.onTap,
    required this.onDismissed,
  });

  final AppNotification n;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  /// Distinct color + glyph per notification event, so the inbox is scannable.
  (Color, IconData) _style(ColorScheme scheme) => switch (n.event) {
    'assigned' => (AppTheme.brand, Icons.person_add_alt),
    'message' => (AppTheme.open, Icons.mail_outline),
    'note' => (AppTheme.warning, Icons.sticky_note_2_outlined),
    'transferred' => (AppTheme.brandLight, Icons.swap_horiz),
    'overdue' => (AppTheme.overdue, Icons.warning_amber_rounded),
    _ => (scheme.primary, Icons.notifications_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final unread = !n.read;
    final (color, icon) = _style(scheme);

    final snippet = (n.body != null && n.body!.isNotEmpty)
        ? Fmt.stripHtml(n.body)
        : null;
    final meta = [
      n.type == 'task' ? 'Task #${n.objectId}' : 'Ticket #${n.objectId}',
      if (n.actor != null && n.actor!.isNotEmpty) n.actor!,
      if (n.created != null) Fmt.ago(n.created),
    ].join('  ·  ');

    return Dismissible(
      key: ValueKey('notif-${n.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        color: scheme.error,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: unread
              ? scheme.primary.withValues(alpha: isDark ? 0.10 : 0.045)
              : scheme.surface,
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 21),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                n.displayLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: unread
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: scheme.onSurface,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            if (unread)
                              Container(
                                margin: const EdgeInsets.only(top: 5, left: 8),
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        if (snippet != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            snippet,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 5),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
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
      ),
    );
  }
}
