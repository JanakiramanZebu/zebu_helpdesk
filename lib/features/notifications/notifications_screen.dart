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
import '../../widgets/app_toast.dart';
import '../../widgets/states.dart';

/// The agent's notification inbox (`GET /notifications`), collapsed per
/// ticket/task like osTicket's `inbox.inc.php`: one card per object, newest
/// activity first, unread objects bumped to the top.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  // Accumulated flat pages; grouping is done client-side over every loaded
  // page (see [NotificationGroup]).
  final List<AppNotification> _all = [];
  final Set<int> _deleted = {}; // optimistic-delete tombstones
  int _page = 1;
  bool _loadingPage = false;
  bool _hasMore = true;
  bool _initialLoad = true;
  Object? _error;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadPage(reset: true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 320) {
      _loadPage();
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loadingPage) return;
    if (!reset && !_hasMore) return;
    setState(() {
      _loadingPage = true;
      if (reset) {
        _initialLoad = true;
        _error = null;
        _page = 1;
        _hasMore = true;
        _all.clear();
        _deleted.clear();
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loadingPage = false);
    }
  }

  Future<void> _refresh() => _loadPage(reset: true);

  void _toast(String msg, {ToastType type = ToastType.info}) =>
      AppToast.show(context, msg, type: type);

  Future<void> _markAllRead() async {
    try {
      await ref.read(notificationsRepositoryProvider).readAll();
      _refresh();
      ref.invalidate(unreadCountProvider);
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
      ref.invalidate(unreadCountProvider);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    }
  }

  /// Delete every notification for one object (the collapsed card). No
  /// delete-by-object endpoint exists, so clear each id, optimistically.
  Future<void> _deleteGroup(NotificationGroup g) async {
    final ids = g.ids.toList();
    setState(() => _deleted.addAll(ids));
    try {
      final repo = ref.read(notificationsRepositoryProvider);
      await Future.wait(ids.map(repo.deleteOne));
      ref.invalidate(unreadCountProvider);
    } on ApiException catch (e) {
      setState(() => _deleted.removeAll(ids));
      _toast(e.message);
      _refresh();
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
    } on ApiException catch (_) {
      // Best-effort; navigate regardless.
    }
    ref.invalidate(unreadCountProvider);
    if (!mounted) return;
    if (g.type == 'task') {
      await context.push(Routes.task(g.objectId));
    } else {
      await context.push(Routes.ticket(g.objectId));
    }
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final groups = NotificationGroup.from(
      _all.where((n) => !_deleted.contains(n.id)),
    );

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
      body: _buildBody(groups),
    );
  }

  Widget _buildBody(List<NotificationGroup> groups) {
    if (_initialLoad && _loadingPage) return const LoadingView();
    if (_error != null && _all.isEmpty) {
      return ErrorView(error: _error!, onRetry: _refresh);
    }
    if (groups.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: const [
            SizedBox(
              height: 400,
              child: EmptyView(
                icon: Icons.notifications_none,
                message: 'No notifications',
                hint: 'You are all caught up.',
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scroll,
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
          return _NotificationGroupTile(
            group: g,
            onTap: () => _open(g),
            onDismissed: () => _deleteGroup(g),
          );
        },
      ),
    );
  }
}

/// One collapsed card = all of an agent's notifications for a single
/// ticket/task. Shows the latest activity, an "N updates" hint when more than
/// one was collapsed, and an unread dot when any activity is unread.
class _NotificationGroupTile extends StatelessWidget {
  const _NotificationGroupTile({
    required this.group,
    required this.onTap,
    required this.onDismissed,
  });

  final NotificationGroup group;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  /// Distinct color + glyph keyed on the latest activity's event. Event keys
  /// are the raw osTicket events (see inbox.inc.php $LABELS).
  (Color, IconData) _style(ColorScheme scheme) => switch (group.latest.event) {
    'assigned' => (AppTheme.brand, Icons.person_add_alt),
    'message' => (AppTheme.open, Icons.mail_outline),
    'note' => (AppTheme.warning, Icons.sticky_note_2_outlined),
    'transfer' => (AppTheme.brandLight, Icons.swap_horiz),
    'status' => (AppTheme.brandLight, Icons.change_circle_outlined),
    'mention' => (AppTheme.warning, Icons.alternate_email),
    'overdue' => (AppTheme.overdue, Icons.warning_amber_rounded),
    'new_unassigned' => (AppTheme.brand, Icons.move_to_inbox_outlined),
    _ => (scheme.primary, Icons.notifications_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final n = group.latest;
    final unread = group.hasUnread;
    final (color, icon) = _style(scheme);

    final snippet = (n.body != null && n.body!.isNotEmpty)
        ? Fmt.stripHtml(n.body)
        : null;
    final meta = [
      group.type == 'task'
          ? 'Task #${group.objectId}'
          : 'Ticket #${group.objectId}',
      if (group.count > 1) '${group.count} updates',
      if (n.actor != null && n.actor!.isNotEmpty) n.actor!,
      if (group.lastActivity != null) Fmt.ago(group.lastActivity),
    ].join('  ·  ');

    return Dismissible(
      key: ValueKey('notif-group-${group.key}'),
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
