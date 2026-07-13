import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/assets.dart';
import '../../core/format.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../models/common.dart';
import '../../models/meta.dart';
import '../../models/ticket.dart';
import '../../providers.dart';
import '../../widgets/action_menu.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/date_picker_sheet.dart';
import '../../widgets/message_composer.dart';
import '../../widgets/pickers.dart';
import '../../widgets/states.dart';
import '../../widgets/status_chip.dart';
import 'widgets/dynamic_fields_section.dart';
import 'widgets/thread_entry_tile.dart';

class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({super.key, required this.ticketId});
  final int ticketId;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  // Controls the outer (header) scroll view of the NestedScrollView, so its
  // offset tells us exactly how far the collapsing header has scrolled away.
  final ScrollController _headerScroll = ScrollController();

  Ticket? _ticket;
  List<ThreadEntry> _thread = [];
  List<ThreadEvent> _events = [];
  Object? _error;
  bool _loading = true;
  bool _acting = false;
  bool _subjectInBar = false;
  // Message the composer is quoting (set from a bubble's long-press → Reply).
  ThreadEntry? _replyTo;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTab);
    _headerScroll.addListener(_onHeaderScroll);
    _load();
  }

  void _onTab() {
    if (mounted) setState(() {}); // toggle the composer per active tab
  }

  /// Whether the composer (only shown for the Conversation tab, index 0) should
  /// be visible. Uses the controller's live [animation] value rather than
  /// [index] so the field hides the instant a swipe starts moving away â€” a
  /// small threshold means it disappears as soon as the drag begins, matching
  /// the immediate hide you get when tapping another tab.
  bool get _onConversationTab => (_tabs.animation?.value ?? 0) < 0.05;

  // Show the subject in the app bar once the collapsing header (which holds
  // the subject) has scrolled behind the pinned app bar.
  void _onHeaderScroll() {
    final show = _headerScroll.offset > 28;
    if (show != _subjectInBar && mounted) {
      setState(() => _subjectInBar = show);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _headerScroll.dispose();
    super.dispose();
  }

  // [silent] refreshes the data in place without flashing the full-screen
  // loader â€” used after sending a message so the conversation just updates.
  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      final ticket = await repo.get(widget.ticketId);
      final thread = await repo.thread(widget.ticketId, limit: 50);
      final events = await repo.events(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _thread = thread.items;
        _events = events;
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

  /// Composer transport: post the body (reply or internal note) plus any
  /// attachments, then silently refresh the thread. Returns false on failure so
  /// the composer keeps the draft.
  Future<bool> _sendMessage({
    required bool note,
    required String html,
    required List<MultipartFile> files,
  }) async {
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      if (note) {
        await repo.note(widget.ticketId, body: html, files: files);
      } else {
        await repo.reply(widget.ticketId, body: html, alert: true, files: files);
      }
      await _load(silent: true);
      return true;
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
      return false;
    }
  }

  void _apply(Ticket updated) => setState(() => _ticket = updated);

  void _toast(String msg) => AppSnack.info(context, msg);

  Future<void> _runAction(
    Future<Ticket> Function() action, {
    String? success,
  }) async {
    setState(() => _acting = true);
    try {
      final updated = await action();
      _apply(updated);
      if (success != null) _toast(success);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  PopupMenuButton<String> _menu() => PopupMenuButton<String>(
    onSelected: _onMenu,
    shape: AppActionMenu.shape,
    color: Theme.of(context).colorScheme.surface,
    elevation: AppActionMenu.elevation,
    menuPadding: AppActionMenu.menuPadding,
    itemBuilder: (context) => [
      // Workflow / status.
      appMenuItem(value: 'status', asset: Assets.actStatus, label: 'Change status'),
      appMenuItem(value: 'mark', asset: Assets.actMark, label: 'Mark answered/overdue'),
      const PopupMenuDivider(),
      // Assignment.
      appMenuItem(value: 'assign', asset: Assets.actAssign, label: 'Assign'),
      appMenuItem(value: 'assign_team', asset: Assets.actCollaborators, label: 'Assign to team'),
      appMenuItem(value: 'claim', asset: Assets.actClaim, label: 'Claim'),
      appMenuItem(value: 'release', asset: Assets.actRelease, label: 'Release'),
      appMenuItem(value: 'owner', asset: Assets.actOwner, label: 'Change owner'),
      appMenuItem(value: 'refer', asset: Assets.actRefer, label: 'Refer'),
      const PopupMenuDivider(),
      // Attributes.
      appMenuItem(value: 'transfer', asset: Assets.actTransfer, label: 'Transfer dept'),
      appMenuItem(value: 'priority', asset: Assets.actPriority, label: 'Set priority'),
      appMenuItem(value: 'topic', asset: Assets.actTopic, label: 'Change topic'),
      appMenuItem(value: 'duedate', asset: Assets.actDuedate, label: 'Set due date'),
      appMenuItem(value: 'fields', asset: Assets.actEdit, label: 'Edit fields'),
      appMenuItem(value: 'tags', asset: Assets.actTag, label: 'Tags'),
      const PopupMenuDivider(),
      // Relations.
      appMenuItem(value: 'link', asset: Assets.actLink, label: 'Link tickets'),
      appMenuItem(value: 'merge', asset: Assets.actMerge, label: 'Merge tickets'),
      const PopupMenuDivider(),
      // Metadata.
      appMenuItem(value: 'collaborators', asset: Assets.actCollaborators, label: 'Collaborators'),
      appMenuItem(value: 'ban', asset: Assets.actBan, label: 'Ban / unban email'),
      const PopupMenuDivider(),
      appMenuItem(value: 'delete', asset: Assets.actDelete, label: 'Delete', destructive: true),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket')),
        body: const LoadingView(),
      );
    }
    if (_error != null || t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket')),
        body: ErrorView(error: _error ?? 'Not found', onRetry: _load),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: NestedScrollView(
              controller: _headerScroll,
              headerSliverBuilder: (context, _) => [
                SliverAppBar(
                  pinned: true,
                  title: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('#${t.number}'),
                      if (_subjectInBar)
                        AppText.paraText(
                          context,
                          t.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          color: Theme.of(context)
                              .appBarTheme
                              .foregroundColor
                              ?.withValues(alpha: 0.8),
                        ),
                    ],
                  ),
                  actions: [_menu()],
                ),
                SliverToBoxAdapter(child: _CollapsingHeader(ticket: t)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverTabBarDelegate(
                    TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorPadding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 2,
                      ),
                      tabs: const [
                        Tab(text: 'Conversation'),
                        Tab(text: 'Details'),
                        Tab(text: 'Activity'),
                      ],
                    ),
                  ),
                ),
              ],
              body: Column(
                children: [
                  if (_acting) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _ConversationTab(
                          thread: _thread,
                          onReply: (e) => setState(() => _replyTo = e),
                        ),
                        _DetailsTab(ticket: t, onEdit: _onMenu),
                        _ActivityTab(events: _events),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The composer floats over the bottom of the conversation (frosted
          // glass), so messages scroll behind it. Rebuild on every swipe frame
          // (the controller's own listener only fires on settled index changes)
          // so the composer hides the instant the user drags off Conversation.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ListenableBuilder(
              listenable: _tabs.animation!,
              builder: (context, _) => _onConversationTab
                  ? MessageComposer(
                      hintReply: 'Reply to this ticket...',
                      replyTo: _replyTo,
                      onClearReply: () => setState(() => _replyTo = null),
                      expandCanned: (c) async {
                        final exp = await ref
                            .read(cannedRepositoryProvider)
                            .expand(c.id, ticketId: widget.ticketId);
                        return exp.expanded;
                      },
                      onSend:
                          ({required note, required html, required files}) =>
                              _sendMessage(
                                note: note,
                                html: html,
                                files: files,
                              ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(String value) async {
    final repo = ref.read(ticketsRepositoryProvider);
    switch (value) {
      case 'claim':
        await _runAction(
          () => repo.claim(widget.ticketId),
          success: 'Ticket claimed',
        );
        await _load();
      case 'release':
        await _runAction(
          () => repo.release(widget.ticketId),
          success: 'Ticket released',
        );
        await _load();
      case 'status':
        await _pickMeta(MetaKind.statuses, title: 'Change status', (id) async {
          await _runAction(
            () => repo.setStatus(widget.ticketId, id),
            success: 'Status updated',
          );
          await _load();
        });
      case 'priority':
        await _pickMeta(MetaKind.priorities, title: 'Set priority', (id) async {
          await _runAction(
            () => repo.setPriority(widget.ticketId, id),
            success: 'Priority updated',
          );
        });
      case 'transfer':
        await _pickMeta(MetaKind.departments, title: 'Transfer department',
            selectedId: _ticket?.departmentId, (id) async {
          await _runAction(
            () => repo.transfer(widget.ticketId, id),
            success: 'Transferred',
          );
          await _load();
        });
      case 'assign':
        await _pickMeta(MetaKind.agents, title: 'Assign to', (id) async {
          await _runAction(
            () => repo.assign(widget.ticketId, staffId: id),
            success: 'Assigned',
          );
          await _load();
        });
      case 'assign_team':
        await _pickMeta(MetaKind.teams, title: 'Assign to team', (id) async {
          await _runAction(
            () => repo.assign(widget.ticketId, teamId: id),
            success: 'Assigned to team',
          );
          await _load();
        });
      case 'topic':
        await _pickMeta(MetaKind.topics, title: 'Change topic', (id) async {
          await _runAction(
            () => repo.setTopic(widget.ticketId, id),
            success: 'Topic updated',
          );
          await _load();
        });
      case 'owner':
        final user = await pickUser(context, ref);
        if (user != null) {
          await _runAction(
            () => repo.setOwner(widget.ticketId, user.id),
            success: 'Owner changed',
          );
          await _load();
        }
      case 'duedate':
        await _setDueDate();
      case 'fields':
        await _editCustomFields();
      case 'tags':
        await _manageTags();
      case 'refer':
        await _manageReferrals();
      case 'link':
        await _linkOrMerge(merge: false);
      case 'merge':
        await _linkOrMerge(merge: true);
      case 'ban':
        await _banEmail();
      case 'mark':
        await _markState();
      case 'collaborators':
        await _manageCollaborators();
      case 'delete':
        await _confirmDelete();
    }
  }

  Future<void> _setDueDate() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day); // today
    // A ticket may already carry a due date in the past; the picker asserts if
    // initialDate is before firstDate, so clamp it up to today.
    final existingDue = _ticket?.due;
    final initialDate = (existingDue == null || existingDue.isBefore(firstDate))
        ? firstDate
        : existingDue;
    final date = await pickDate(
      context,
      initial: initialDate,
      first: firstDate,
      last: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_ticket?.due ?? now),
    );
    final due = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 17,
      time?.minute ?? 0,
    );
    // Reject a due time already in the past (e.g. today at an earlier hour).
    if (due.isBefore(DateTime.now())) {
      _toast('Due date must be in the future');
      return;
    }
    await _runAction(
      () => ref
          .read(ticketsRepositoryProvider)
          .setDueDate(widget.ticketId, duedate: Fmt.apiDateTime(due)),
      success: 'Due date set',
    );
    await _load();
  }

  Future<void> _markState() async {
    const states = {
      'answered': 'Answered',
      'unanswered': 'Unanswered',
      'overdue': 'Overdue',
      'notoverdue': 'Not overdue',
    };
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Mark as'),
        children: [
          for (final e in states.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(e.value),
              ),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await _runAction(
      () => ref.read(ticketsRepositoryProvider).mark(widget.ticketId, chosen),
      success: 'Marked ${states[chosen]!.toLowerCase()}',
    );
    await _load();
  }

  Future<void> _manageCollaborators() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CollaboratorsSheet(ticketId: widget.ticketId),
    );
  }

  /// Edit the ticket's dynamic custom fields via `GET /tickets/{id}/fields`
  /// (schema + current values) and `POST /tickets/{id}/edit`. Reloads the
  /// ticket on a successful save so the Details tab reflects the new values.
  Future<void> _editCustomFields() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomFieldsSheet(ticketId: widget.ticketId),
    );
    if (saved == true) await _load();
  }

  Future<void> _manageTags() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TagsSheet(ticketId: widget.ticketId),
    );
  }

  Future<void> _manageReferrals() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ReferralsSheet(ticketId: widget.ticketId),
    );
  }

  Future<void> _linkOrMerge({required bool merge}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _LinkMergeDialog(ticketId: widget.ticketId, merge: merge),
    );
    if (changed == true) await _load();
  }

  /// Ban or unban the requester's email address. Both operations are exposed
  /// (the ticket carries no ban flag) via a small chooser sheet.
  Future<void> _banEmail() async {
    final choice = await showAppSheet<String>(
      context: context,
      builder: (_) => AppSheet(
        title: 'Ban list',
        subtitle: _ticket?.userEmail,
        scrollable: false,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PickerOptionTile(
              label: 'Ban this email address',
              selected: false,
              onTap: () => Navigator.pop(context, 'ban'),
            ),
            PickerOptionTile(
              label: 'Remove from ban list',
              selected: false,
              onTap: () => Navigator.pop(context, 'unban'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      final banned = choice == 'ban'
          ? await repo.banEmail(widget.ticketId)
          : await repo.unbanEmail(widget.ticketId);
      if (mounted) _toast(banned ? 'Email banned' : 'Email removed from ban list');
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _pickMeta(
    String kind,
    Future<void> Function(int id) onPick, {
    String title = 'Select',
    int? selectedId,
  }) async {
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(kind);
    } on ApiException catch (e) {
      _toast(e.message);
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => _MetaPickerDialog(
        title: title,
        items: items,
        selectedId: selectedId,
      ),
    );
    if (chosen != null) await onPick(chosen);
  }

  Future<void> _confirmDelete() async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete ticket?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ref.read(ticketsRepositoryProvider).delete(widget.ticketId);
      if (mounted) {
        _toast('Ticket deleted');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }
}

// --- Collapsing header (status + SLA; scrolls away under the app bar) --------

class _CollapsingHeader extends StatelessWidget {
  const _CollapsingHeader({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.titleText(context, ticket.subject, fw: 2),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip.status(ticket.statusName, dense: true),
              if (ticket.priority != null)
                StatusChip.priority(ticket.priority!, dense: true),
              if (ticket.isOverdue)
                const StatusChip(
                  label: 'Overdue',
                  color: Color(0xFFD32F2F),
                  icon: Icons.warning_amber_rounded,
                  dense: true,
                ),
            ],
          ),
          if (ticket.sla != null && ticket.sla!.frac != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ticket.sla!.frac!.clamp(0, 1),
                minHeight: 6,
                color: ticket.sla!.isOverdue
                    ? const Color(0xFFD32F2F)
                    : theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            AppText.paraText(context, 'SLA: ${ticket.sla!.label ?? 'â€”'}'),
          ],
        ],
      ),
    );
  }
}

/// Pins the tab bar below the (collapsing) header.
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate old) => old.tabBar != tabBar;
}

// --- Tabs -------------------------------------------------------------------

class _ConversationTab extends StatelessWidget {
  const _ConversationTab({required this.thread, this.onReply});
  final List<ThreadEntry> thread;
  final ValueChanged<ThreadEntry>? onReply;

  @override
  Widget build(BuildContext context) {
    if (thread.isEmpty) {
      return const EmptyView(message: 'No messages yet');
    }
    // Reserve room for the floating composer so the newest message clears it.
    return ConversationList(
      thread: thread,
      onReply: onReply,
      bottomReserve: 104 + MediaQuery.of(context).padding.bottom,
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({required this.ticket, required this.onEdit});
  final Ticket ticket;

  /// Routes an edit intent (matching the â‹®-menu action keys) back to the host.
  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Editable attributes â€” tap to open the matching picker.
        _DetailSection(
          title: 'Attributes',
          children: [
            _DetailRow(
              icon: Icons.published_with_changes,
              label: 'Status',
              value: ticket.statusName,
              onTap: () => onEdit('status'),
            ),
            _DetailRow(
              icon: Icons.flag_outlined,
              label: 'Priority',
              value: ticket.priority,
              placeholder: 'Set priority',
              onTap: () => onEdit('priority'),
            ),
            _DetailRow(
              icon: Icons.apartment_outlined,
              label: 'Department',
              value: ticket.departmentName,
              placeholder: 'Transfer',
              onTap: () => onEdit('transfer'),
            ),
            _DetailRow(
              icon: Icons.assignment_ind_outlined,
              label: 'Assignee',
              value: ticket.assignee,
              placeholder: 'Assign',
              onTap: () => onEdit('assign'),
            ),
            _DetailRow(
              icon: Icons.event_outlined,
              label: 'Due date',
              value: ticket.due == null ? null : Fmt.dateTime(ticket.due),
              placeholder: 'Set due date',
              onTap: () => onEdit('duedate'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Read-only requester / timestamps.
        _DetailSection(
          title: 'Information',
          children: [
            _DetailRow(
              icon: Icons.person_outline,
              label: 'Requester',
              value: ticket.requester,
            ),
            _DetailRow(
              icon: Icons.mail_outline,
              label: 'Email',
              value: ticket.userEmail,
            ),
            _DetailRow(
              icon: Icons.schedule,
              label: 'Created',
              value: Fmt.dateTime(ticket.created),
            ),
            _DetailRow(
              icon: Icons.update,
              label: 'Updated',
              value: Fmt.dateTime(ticket.updated),
            ),
          ],
        ),
        if (ticket.customFields.isNotEmpty) ...[
          const SizedBox(height: 16),
          _DetailSection(
            title: 'Custom fields',
            children: [
              for (final e in ticket.customFields.entries)
                _DetailRow(
                  icon: Icons.list_alt_outlined,
                  label: e.key,
                  value: e.value,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A titled card grouping a set of [_DetailRow]s.
class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: AppText.captionText(
            context,
            title.toUpperCase(),
            fw: 2,
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i != 0) const Divider(height: 1, indent: 52),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A single detail row. When [onTap] is set it renders as tappable (chevron +
/// ripple); otherwise it's static. A null/empty [value] shows [placeholder]
/// in a muted style.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.placeholder,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? placeholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final has = value != null && value!.isNotEmpty && value != 'â€”';
    // Static rows with no value at all render nothing.
    if (!has && onTap == null) return const SizedBox.shrink();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 16),
            SizedBox(
              width: 96,
              child: AppText.subText(
                context,
                label,
                color: scheme.onSurfaceVariant,
              ),
            ),
            Expanded(
              child: AppText.subText(
                context,
                has ? value! : (placeholder ?? 'â€”'),
                fw: has ? 1 : 3,
                color: has ? scheme.onSurface : scheme.primary,
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.events});
  final List<ThreadEvent> events;

  /// (icon, colour) for an event, derived from its state slug.
  static (IconData, Color) _style(String state) {
    final s = state.toLowerCase();
    if (s.contains('close') || s.contains('resolved')) {
      return (Icons.check_circle_outline, AppTheme.closed);
    }
    if (s.contains('open') || s.contains('reopen')) {
      return (Icons.play_circle_outline, AppTheme.open);
    }
    if (s.contains('assign') || s.contains('claim') || s.contains('owner')) {
      return (Icons.person_outline, AppTheme.brand);
    }
    if (s.contains('transfer')) {
      return (Icons.swap_horiz, AppTheme.warning);
    }
    if (s.contains('overdue')) {
      return (Icons.warning_amber_rounded, AppTheme.overdue);
    }
    if (s.contains('note')) {
      return (Icons.sticky_note_2_outlined, AppTheme.brandLight);
    }
    if (s.contains('reply') || s.contains('message')) {
      return (Icons.reply, AppTheme.open);
    }
    return (Icons.fiber_manual_record, AppTheme.brand);
  }

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const EmptyView(message: 'No activity');
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: events.length,
        itemBuilder: (context, i) {
          final e = events[i];
          final (icon, color) = _style(e.state);
          final isLast = i == events.length - 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timeline rail: a coloured icon node with a connector below.
                Column(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 17, color: color),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: scheme.outlineVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 18, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText.subText(
                          context,
                          e.description ?? e.state,
                          fw: 1,
                          lineHeight: 1.3,
                        ),
                        const SizedBox(height: 2),
                        AppText.paraText(
                          context,
                          [
                            if ((e.actor ?? '').isNotEmpty) e.actor!,
                            Fmt.ago(e.created),
                          ].join(' Â· '),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// --- Collaborators sheet ----------------------------------------------------

class _CollaboratorsSheet extends ConsumerStatefulWidget {
  const _CollaboratorsSheet({required this.ticketId});
  final int ticketId;

  @override
  ConsumerState<_CollaboratorsSheet> createState() =>
      _CollaboratorsSheetState();
}

class _CollaboratorsSheetState extends ConsumerState<_CollaboratorsSheet> {
  List<Collaborator> _collabs = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await ref
          .read(ticketsRepositoryProvider)
          .collaborators(widget.ticketId);
      if (mounted) {
        setState(() {
          _collabs = c;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppSnack.error(context, e.message);
      }
    }
  }

  Future<void> _add() async {
    final user = await pickUser(context, ref);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ticketsRepositoryProvider)
          .addCollaborator(widget.ticketId, user.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        AppSnack.error(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(int cid) async {
    setState(() => _busy = true);
    try {
      final c = await ref
          .read(ticketsRepositoryProvider)
          .removeCollaborator(widget.ticketId, cid);
      if (mounted) setState(() => _collabs = c);
    } on ApiException catch (e) {
      if (mounted) {
        AppSnack.error(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Collaborators',
      actionLabel: 'Add collaborator',
      onAction: _busy ? null : _add,
      actionEnabled: !_busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _collabs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: AppText.subText(context, 'No collaborators'),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in _collabs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.name),
                          subtitle: c.email != null ? Text(c.email!) : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _busy ? null : () => _remove(c.id),
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

// --- Custom fields editor sheet ---------------------------------------------

/// Loads a ticket's editable dynamic form fields and lets the agent edit them,
/// posting the changed `{name: value}` map to `POST /tickets/{id}/edit`. Pops
/// `true` when a save succeeds so the caller can reload the ticket.
class _CustomFieldsSheet extends ConsumerStatefulWidget {
  const _CustomFieldsSheet({required this.ticketId});
  final int ticketId;

  @override
  ConsumerState<_CustomFieldsSheet> createState() => _CustomFieldsSheetState();
}

class _CustomFieldsSheetState extends ConsumerState<_CustomFieldsSheet> {
  List<TicketField> _fields = const [];
  Map<String, dynamic> _values = {};
  Map<String, String> _errors = const {};
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final fields = await ref
          .read(ticketsRepositoryProvider)
          .fields(widget.ticketId);
      if (!mounted) return;
      setState(() {
        // Only fields the agent may actually change are worth showing.
        _fields = fields.where((f) => f.editable).toList();
        _values = {
          for (final f in _fields)
            if (f.value != null) f.name: f.value,
        };
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    // Send every editable field (empty string clears a value), so the payload
    // is never the empty map the server rejects with a 422.
    final payload = {for (final f in _fields) f.name: _values[f.name] ?? ''};
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      await ref.read(ticketsRepositoryProvider).editFields(
        widget.ticketId,
        payload,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors = e.fields;
        if (e.fields.isEmpty) AppSnack.error(context, e.message);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFields = _fields.isNotEmpty;
    return AppDialog(
      title: 'Edit fields',
      actionLabel: hasFields ? 'Save' : null,
      actionBusy: _saving,
      onAction: _save,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : _loadError != null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AppText.subText(context, _loadError!),
            )
          : !hasFields
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AppText.subText(context, 'No editable fields'),
            )
          : DynamicFieldsSection(
              fields: _fields,
              values: _values,
              errors: _errors,
              onChanged: (v) => setState(() => _values = v),
            ),
    );
  }
}

// --- Tags sheet -------------------------------------------------------------

/// Lists a ticket's tags and lets the agent add (from the shared tag list) or
/// remove them via `GET/POST/DELETE /tickets/{id}/tags`.
class _TagsSheet extends ConsumerStatefulWidget {
  const _TagsSheet({required this.ticketId});
  final int ticketId;

  @override
  ConsumerState<_TagsSheet> createState() => _TagsSheetState();
}

class _TagsSheetState extends ConsumerState<_TagsSheet> {
  List<Tag> _tags = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await ref.read(ticketsRepositoryProvider).tags(widget.ticketId);
      if (mounted) {
        setState(() {
          _tags = t;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppSnack.error(context, e.message);
      }
    }
  }

  Future<void> _add() async {
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(MetaKind.tags);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => _MetaPickerDialog(title: 'Add tag', items: items),
    );
    if (chosen == null) return;
    setState(() => _busy = true);
    try {
      final t = await ref
          .read(ticketsRepositoryProvider)
          .addTag(widget.ticketId, tagId: chosen);
      if (mounted) setState(() => _tags = t);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(int tagId) async {
    setState(() => _busy = true);
    try {
      final t = await ref
          .read(ticketsRepositoryProvider)
          .removeTag(widget.ticketId, tagId);
      if (mounted) setState(() => _tags = t);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Tags',
      actionLabel: 'Add tag',
      onAction: _busy ? null : _add,
      actionEnabled: !_busy,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : _tags.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AppText.subText(context, 'No tags'),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _tags)
                  Chip(
                    label: Text(t.name),
                    onDeleted: _busy ? null : () => _remove(t.id),
                  ),
              ],
            ),
    );
  }
}

// --- Referrals sheet --------------------------------------------------------

/// Lists a ticket's referrals and lets the agent refer it to an agent, team or
/// department, or remove a referral (`GET/POST/DELETE /tickets/{id}/referrals`).
class _ReferralsSheet extends ConsumerStatefulWidget {
  const _ReferralsSheet({required this.ticketId});
  final int ticketId;

  @override
  ConsumerState<_ReferralsSheet> createState() => _ReferralsSheetState();
}

class _ReferralsSheetState extends ConsumerState<_ReferralsSheet> {
  List<Referral> _refs = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ref
          .read(ticketsRepositoryProvider)
          .referrals(widget.ticketId);
      if (mounted) {
        setState(() {
          _refs = r;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppSnack.error(context, e.message);
      }
    }
  }

  Future<void> _add() async {
    final target = await showAppSheet<String>(
      context: context,
      builder: (_) => AppSheet(
        title: 'Refer to',
        scrollable: false,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PickerOptionTile(
              label: 'Agent',
              selected: false,
              onTap: () => Navigator.pop(context, 'agent'),
            ),
            PickerOptionTile(
              label: 'Team',
              selected: false,
              onTap: () => Navigator.pop(context, 'team'),
            ),
            PickerOptionTile(
              label: 'Department',
              selected: false,
              onTap: () => Navigator.pop(context, 'dept'),
            ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    final kind = target == 'agent'
        ? MetaKind.agents
        : target == 'team'
        ? MetaKind.teams
        : MetaKind.departments;
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(kind);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => _MetaPickerDialog(title: 'Refer to', items: items),
    );
    if (chosen == null) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(ticketsRepositoryProvider).addReferral(
        widget.ticketId,
        staffId: target == 'agent' ? chosen : null,
        teamId: target == 'team' ? chosen : null,
        deptId: target == 'dept' ? chosen : null,
      );
      if (mounted) setState(() => _refs = r);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(int rid) async {
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(ticketsRepositoryProvider)
          .removeReferral(widget.ticketId, rid);
      if (mounted) setState(() => _refs = r);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Referrals',
      actionLabel: 'Add referral',
      onAction: _busy ? null : _add,
      actionEnabled: !_busy,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : _refs.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AppText.subText(context, 'No referrals'),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in _refs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.name),
                      subtitle: Text(r.type),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _busy ? null : () => _remove(r.id),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// --- Link / merge dialog ----------------------------------------------------

/// Links or merges other tickets into this one by their ticket numbers, showing
/// any existing relations and offering to undo. Pops `true` when something
/// changed so the caller reloads.
class _LinkMergeDialog extends ConsumerStatefulWidget {
  const _LinkMergeDialog({required this.ticketId, required this.merge});
  final int ticketId;
  final bool merge;

  @override
  ConsumerState<_LinkMergeDialog> createState() => _LinkMergeDialogState();
}

class _LinkMergeDialogState extends ConsumerState<_LinkMergeDialog> {
  final _numbers = TextEditingController();
  TicketRelations? _relations;
  bool _loading = true;
  bool _busy = false;
  bool _combine = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _numbers.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ref
          .read(ticketsRepositoryProvider)
          .relations(widget.ticketId);
      if (mounted) {
        setState(() {
          _relations = r;
          _loading = false;
        });
      }
    } on ApiException catch (_) {
      // Relations are informational only; a failure just hides the summary.
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _parsed => _numbers.text
      .split(RegExp(r'[,\s]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  bool get _hasRelations {
    final r = _relations;
    return r != null && (r.parent != null || r.children.isNotEmpty);
  }

  Future<void> _submit() async {
    final nums = _parsed;
    if (nums.isEmpty) {
      AppSnack.error(context, 'Enter at least one ticket number');
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(ticketsRepositoryProvider);
      if (widget.merge) {
        await repo.merge(widget.ticketId, nums, combine: _combine ? 1 : 0);
      } else {
        await repo.link(widget.ticketId, nums);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnack.error(context, e.message);
      }
    }
  }

  Future<void> _undo() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(ticketsRepositoryProvider);
      if (widget.merge) {
        await repo.unmerge(widget.ticketId);
      } else {
        await repo.unlink(widget.ticketId);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnack.error(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppDialog(
      title: widget.merge ? 'Merge tickets' : 'Link tickets',
      actionLabel: widget.merge ? 'Merge' : 'Link',
      actionBusy: _busy,
      onAction: _submit,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_hasRelations) ...[
                  AppText.subText(
                    context,
                    () {
                      final r = _relations!;
                      if (r.children.isNotEmpty) {
                        final nums = r.children.map((c) => '#${c.number}').join(', ');
                        return 'Currently ${r.children.length} linked: $nums';
                      }
                      return 'Linked to #${r.parent!.number}';
                    }(),
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _undo,
                      icon: const Icon(Icons.link_off, size: 18),
                      label: Text(widget.merge ? 'Unmerge' : 'Unlink'),
                    ),
                  ),
                  const Divider(height: 20),
                ],
                TextField(
                  controller: _numbers,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'Ticket numbers',
                    hintText: 'e.g. 100234, 100235',
                  ),
                ),
                if (widget.merge)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _combine,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _combine = v),
                    title: AppText.subText(context, 'Combine threads', fw: 1),
                    subtitle: AppText.paraText(
                      context,
                      'Merge conversations into one thread',
                    ),
                  ),
              ],
            ),
    );
  }
}

// --- Meta picker dialog (with search) ----------------------------------------

class _MetaPickerDialog extends StatefulWidget {
  const _MetaPickerDialog({
    required this.title,
    required this.items,
    this.selectedId,
  });

  final String title;
  final List<MetaItem> items;
  final int? selectedId;

  @override
  State<_MetaPickerDialog> createState() => _MetaPickerDialogState();
}

class _MetaPickerDialogState extends State<_MetaPickerDialog> {
  final _searchCtrl = TextEditingController();
  late List<MetaItem> _filtered = widget.items;

  /// Only show the search field for lists long enough to warrant it; short
  /// pick-lists (priorities, statuses, â€¦) don't need one.
  bool get _searchable => widget.items.length > 8;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_updateFilter);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_updateFilter);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _updateFilter() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = widget.items
          .where((item) => item.name.toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      title: widget.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_searchable) ...[
            SheetSearchField(
              controller: _searchCtrl,
              hintText: 'Search',
            ),
            const SizedBox(height: 12),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: _filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: AppText.subText(context, 'No results found'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final item in _filtered)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(context, item.id),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: AppText.subText(
                                context,
                                item.name,
                                fw: item.id == widget.selectedId ? 2 : 3,
                                color: item.id == widget.selectedId
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
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
