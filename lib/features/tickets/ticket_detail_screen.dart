import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parchment/codecs.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../models/common.dart';
import '../../models/meta.dart';
import '../../models/ticket.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/date_picker_sheet.dart';
import '../../widgets/pickers.dart';
import '../../widgets/states.dart';
import '../../widgets/status_chip.dart';
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
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
    itemBuilder: (context) => [
      // Workflow / status.
      _menuItem('status', Icons.published_with_changes, 'Change status'),
      _menuItem('mark', Icons.rule, 'Mark answered/overdue'),
      const PopupMenuDivider(),
      // Assignment.
      _menuItem('assign', Icons.assignment_ind_outlined, 'Assign'),
      _menuItem('claim', Icons.how_to_reg_outlined, 'Claim'),
      _menuItem('release', Icons.logout, 'Release'),
      _menuItem('owner', Icons.manage_accounts_outlined, 'Change owner'),
      const PopupMenuDivider(),
      // Attributes.
      _menuItem('transfer', Icons.apartment_outlined, 'Transfer dept'),
      _menuItem('priority', Icons.flag_outlined, 'Set priority'),
      _menuItem('topic', Icons.topic_outlined, 'Change topic'),
      _menuItem('duedate', Icons.event_outlined, 'Set due date'),
      const PopupMenuDivider(),
      // Metadata.
      _menuItem('collaborators', Icons.group_outlined, 'Collaborators'),
      const PopupMenuDivider(),
      _menuItem(
        'delete',
        Icons.delete_outline,
        'Delete',
        color: Theme.of(context).colorScheme.error,
      ),
    ],
  );

  /// A â‹®-menu row with a leading icon; [color] tints destructive actions.
  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Text(label, style: color == null ? null : TextStyle(color: color)),
        ],
      ),
    );
  }

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
      body: Column(
        children: [
          Expanded(
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
                        _ConversationTab(thread: _thread),
                        _DetailsTab(ticket: t, onEdit: _onMenu),
                        _ActivityTab(events: _events),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Rebuild on every swipe frame (the controller's own listener only
          // fires on settled index changes) so the composer hides the instant
          // the user drags away from the Conversation tab.
          ListenableBuilder(
            listenable: _tabs.animation!,
            builder: (context, _) => _onConversationTab
                ? _InlineComposer(ticketId: widget.ticketId, onSent: _load)
                : const SizedBox.shrink(),
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
  const _ConversationTab({required this.thread});
  final List<ThreadEntry> thread;

  @override
  Widget build(BuildContext context) {
    if (thread.isEmpty) {
      return const EmptyView(message: 'No messages yet');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: thread.length,
      itemBuilder: (_, i) => ThreadEntryTile(entry: thread[i]),
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
    return ListView.builder(
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
    );
  }
}

// --- Inline composer (WhatsApp-style reply/note input) ----------------------

class _InlineComposer extends ConsumerStatefulWidget {
  const _InlineComposer({required this.ticketId, required this.onSent});
  final int ticketId;
  final Future<void> Function() onSent;

  @override
  ConsumerState<_InlineComposer> createState() => _InlineComposerState();
}

class _InlineComposerState extends ConsumerState<_InlineComposer> {
  final FleatherController _controller = FleatherController();
  final FocusNode _focus = FocusNode();
  final List<PlatformFile> _files = [];
  bool _note = false; // false = reply to requester, true = internal note
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onChange);
    _controller.addListener(_onChange);
  }

  // Rebuilds so the hint, send-enabled state and toolbar track edits/focus.
  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onChange);
    _controller.removeListener(_onChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool get _isEmpty => _controller.document.toPlainText().trim().isEmpty;

  void _clearDocument() {
    final len = _controller.document.length;
    if (len > 1) {
      _controller.replaceText(
        0,
        len - 1,
        '',
        selection: const TextSelection.collapsed(offset: 0),
      );
    }
  }

  Future<void> _attach(AttachSource source) async {
    final picked = await pickAttachmentsOf(source);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (!_files.any((e) => e.name == f.name)) _files.add(f);
      }
    });
  }

  /// Sends the document (as HTML) plus attachments. Returns true on success so
  /// the fullscreen editor knows when to close.
  Future<bool> _send() async {
    final empty = _isEmpty;
    if (empty && _files.isEmpty) return false;
    setState(() => _sending = true);
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      final files = [
        for (final f in _files)
          if (f.bytes != null)
            MultipartFile.fromBytes(f.bytes!, filename: f.name),
      ];
      final body = empty ? '' : parchmentHtml.encode(_controller.document);
      if (_note) {
        await repo.note(widget.ticketId, body: body, files: files);
      } else {
        await repo.reply(
          widget.ticketId,
          body: body,
          alert: true,
          files: files,
        );
      }
      _clearDocument();
      if (mounted) setState(() => _files.clear());
      await widget.onSent();
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        AppSnack.error(context, e.message);
      }
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openFullscreen() async {
    _focus.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _FullscreenEditor(
          controller: _controller,
          note: _note,
          onSend: _send,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _note ? AppTheme.warning : scheme.primary;
    final noteTint = AppTheme.warning.withValues(alpha: isDark ? 0.10 : 0.07);
    final barColor = isDark ? const Color(0xFF121B22) : scheme.surface;
    final pillColor = isDark ? const Color(0xFF1F2C34) : Colors.white;
    final canSend = !_isEmpty || _files.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: _note ? Color.alphaBlend(noteTint, barColor) : barColor,
        border: Border(
          top: BorderSide(
            color: _note
                ? accent.withValues(alpha: 0.5)
                : scheme.outlineVariant,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _ModeToggle(
                    note: _note,
                    onChanged: (v) => setState(() => _note = v),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Expand',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.open_in_full,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: _openFullscreen,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (_files.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final f in _files)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: const Icon(
                            Icons.insert_drive_file_outlined,
                            size: 16,
                          ),
                          label: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: Text(
                              f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          onDeleted: () => setState(() => _files.remove(f)),
                        ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: pillColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _note
                              ? accent
                              : scheme.outlineVariant.withValues(alpha: 0.7),
                          width: _note ? 1.4 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Stack(
                              children: [
                                FleatherEditor(
                                  controller: _controller,
                                  focusNode: _focus,
                                  minHeight: 24,
                                  maxHeight: 120,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                                if (_isEmpty)
                                  Positioned(
                                    left: 0,
                                    top: 10,
                                    child: IgnorePointer(
                                      child: Text(
                                        _note
                                            ? 'Internal note (staff only)'
                                            : 'Add a comment',
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          PopupMenuButton<AttachSource>(
                            tooltip: 'Attach',
                            position: PopupMenuPosition.over,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            icon: Transform.rotate(
                              angle: -0.7,
                              child: Icon(
                                Icons.attach_file,
                                size: 22,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            onSelected: _attach,
                            itemBuilder: (_) => attachMenuItems(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _sending
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.6),
                          ),
                        )
                      : Material(
                          color: canSend
                              ? accent
                              : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: canSend ? _send : null,
                            child: Padding(
                              padding: const EdgeInsets.all(11),
                              child: Icon(
                                _note ? Icons.note_add : Icons.send,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                ],
              ),
              if (_focus.hasFocus) ...[
                const SizedBox(height: 2),
                FleatherToolbar.basic(
                  controller: _controller,
                  hideBackgroundColor: true,
                  hideForegroundColor: true,
                  hideDirection: true,
                  hideListChecks: true,
                  hideHorizontalRule: true,
                  hideAlignment: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen rich-text editor that shares the composer's [FleatherController].
class _FullscreenEditor extends StatefulWidget {
  const _FullscreenEditor({
    required this.controller,
    required this.note,
    required this.onSend,
  });

  final FleatherController controller;
  final bool note;
  final Future<bool> Function() onSend;

  @override
  State<_FullscreenEditor> createState() => _FullscreenEditorState();
}

class _FullscreenEditorState extends State<_FullscreenEditor> {
  final FocusNode _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final ok = await widget.onSend();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.note
        ? AppTheme.warning
        : Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Collapse',
          icon: const Icon(Icons.close_fullscreen),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.note ? 'Internal note' : 'Reply'),
        actions: [
          _sending
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: accent),
                    onPressed: _send,
                    icon: Icon(
                      widget.note ? Icons.note_add : Icons.send,
                      size: 18,
                    ),
                    label: const Text('Send'),
                  ),
                ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FleatherEditor(
              controller: widget.controller,
              focusNode: _focus,
              autofocus: true,
              expands: true,
              padding: const EdgeInsets.all(16),
            ),
          ),
          SafeArea(
            top: false,
            child: FleatherToolbar.basic(controller: widget.controller),
          ),
        ],
      ),
    );
  }
}

/// Segmented Reply / Internal note selector shown above the composer input.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.note, required this.onChanged});

  final bool note;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFF1F1F1);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            context: context,
            label: 'Reply',
            icon: Icons.reply_rounded,
            selected: !note,
            selectedColor: scheme.primary,
            onTap: () => onChanged(false),
          ),
          _segment(
            context: context,
            label: 'Internal note',
            icon: Icons.sticky_note_2_outlined,
            selected: note,
            selectedColor: AppTheme.warning,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool selected,
    required Color selectedColor,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? selectedColor : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? Colors.white : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
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
