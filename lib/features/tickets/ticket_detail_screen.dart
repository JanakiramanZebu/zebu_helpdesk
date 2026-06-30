import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:parchment/codecs.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/theme/app_theme.dart';
import '../../models/common.dart';
import '../../models/meta.dart';
import '../../models/ticket.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
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

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

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
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'status', child: Text('Change status')),
      const PopupMenuItem(value: 'assign', child: Text('Assign')),
      const PopupMenuItem(value: 'claim', child: Text('Claim')),
      const PopupMenuItem(value: 'release', child: Text('Release')),
      const PopupMenuItem(value: 'transfer', child: Text('Transfer dept')),
      const PopupMenuItem(value: 'priority', child: Text('Set priority')),
      const PopupMenuItem(value: 'topic', child: Text('Change topic')),
      const PopupMenuItem(value: 'owner', child: Text('Change owner')),
      const PopupMenuItem(value: 'duedate', child: Text('Set due date')),
      const PopupMenuItem(value: 'mark', child: Text('Mark answered/overdue')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'tags', child: Text('Tags')),
      const PopupMenuItem(value: 'collaborators', child: Text('Collaborators')),
      const PopupMenuDivider(),
      const PopupMenuItem(value: 'delete', child: Text('Delete')),
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
                        Text(
                          t.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .appBarTheme
                                    .foregroundColor
                                    ?.withValues(alpha: 0.8),
                              ),
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
                        _DetailsTab(ticket: t),
                        _ActivityTab(events: _events),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_tabs.index == 0)
            _InlineComposer(ticketId: widget.ticketId, onSent: _load),
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
        await _pickMeta(MetaKind.departments, title: 'Transfer department', (
          id,
        ) async {
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
      case 'tags':
        await _manageTags();
      case 'collaborators':
        await _manageCollaborators();
      case 'delete':
        await _confirmDelete();
    }
  }

  Future<void> _setDueDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _ticket?.due ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
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

  Future<void> _manageTags() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _TagsSheet(ticketId: widget.ticketId),
    );
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
  }) async {
    final items = await ref.read(metaRepositoryProvider).get(kind);
    if (!mounted) return;
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text(title),
        children: [
          for (final m in items)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, m.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(m.name),
              ),
            ),
        ],
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
          Text(
            ticket.subject,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
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
            Text(
              'SLA: ${ticket.sla!.label ?? '—'}',
              style: theme.textTheme.bodySmall,
            ),
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
  const _DetailsTab({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String?)>[
      ('Requester', ticket.requester),
      ('Email', ticket.userEmail),
      ('Department', ticket.departmentName),
      ('Assignee', ticket.assignee),
      ('Created', Fmt.dateTime(ticket.created)),
      ('Updated', Fmt.dateTime(ticket.updated)),
      ('Due', Fmt.dateTime(ticket.due)),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (label, value) in rows)
          if (value != null && value.isNotEmpty && value != '—')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
        if (ticket.customFields.isNotEmpty) ...[
          const Divider(height: 28),
          Text('Custom fields', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final e in ticket.customFields.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      e.key,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(child: Text(e.value)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.events});
  final List<ThreadEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const EmptyView(message: 'No activity');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: events.length,
      itemBuilder: (context, i) {
        final e = events[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (i != events.length - 1)
                    Container(
                      width: 2,
                      height: 30,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.description ?? e.state,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '${e.actor ?? ''} · ${Fmt.ago(e.created)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
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

// --- Tags sheet -------------------------------------------------------------

class _TagsSheet extends ConsumerStatefulWidget {
  const _TagsSheet({required this.ticketId});
  final int ticketId;

  @override
  ConsumerState<_TagsSheet> createState() => _TagsSheetState();
}

class _TagsSheetState extends ConsumerState<_TagsSheet> {
  final _name = TextEditingController();
  List<Tag> _tags = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final tags = await ref
          .read(ticketsRepositoryProvider)
          .tags(widget.ticketId);
      if (mounted) {
        setState(() {
          _tags = tags;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final tags = await ref
          .read(ticketsRepositoryProvider)
          .addTag(widget.ticketId, name: name);
      _name.clear();
      if (mounted) setState(() => _tags = tags);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(int tagId) async {
    setState(() => _busy = true);
    try {
      final tags = await ref
          .read(ticketsRepositoryProvider)
          .removeTag(widget.ticketId, tagId);
      if (mounted) setState(() => _tags = tags);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tags'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_tags.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No tags yet'),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in _tags)
                    Chip(
                      label: Text(t.name),
                      onDeleted: _busy ? null : () => _remove(t.id),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(),
                    decoration: const InputDecoration(
                      hintText: 'Add a tag by name',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _add,
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Collaborators')),
          TextButton.icon(
            onPressed: _busy ? null : _add,
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Add'),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            : _collabs.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No collaborators'),
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
