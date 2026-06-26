import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../models/common.dart';
import '../../models/meta.dart';
import '../../models/ticket.dart';
import '../../providers.dart';
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

  Ticket? _ticket;
  List<ThreadEntry> _thread = [];
  List<ThreadEvent> _events = [];
  Object? _error;
  bool _loading = true;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
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

  Future<void> _runAction(Future<Ticket> Function() action,
      {String? success}) async {
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

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    return Scaffold(
      appBar: AppBar(
        title: Text(t == null ? 'Ticket' : '#${t.number}'),
        actions: [
          if (t != null)
            PopupMenuButton<String>(
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
                const PopupMenuItem(
                    value: 'collaborators', child: Text('Collaborators')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : Column(
                  children: [
                    if (_acting) const LinearProgressIndicator(minHeight: 2),
                    _Header(ticket: t!),
                    TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorPadding:
                          const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                      tabs: const [
                        Tab(text: 'Conversation'),
                        Tab(text: 'Details'),
                        Tab(text: 'Activity'),
                      ],
                    ),
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
      bottomNavigationBar: t == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openComposer(isNote: true),
                        icon: const Icon(Icons.note_add_outlined, size: 18),
                        label: const Text('Note'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _openComposer(isNote: false),
                        icon: const Icon(Icons.reply, size: 18),
                        label: const Text('Reply'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _onMenu(String value) async {
    final repo = ref.read(ticketsRepositoryProvider);
    switch (value) {
      case 'claim':
        await _runAction(() => repo.claim(widget.ticketId),
            success: 'Ticket claimed');
        await _load();
      case 'release':
        await _runAction(() => repo.release(widget.ticketId),
            success: 'Ticket released');
        await _load();
      case 'status':
        await _pickMeta(MetaKind.statuses, (id) async {
          await _runAction(() => repo.setStatus(widget.ticketId, id),
              success: 'Status updated');
          await _load();
        });
      case 'priority':
        await _pickMeta(MetaKind.priorities, (id) async {
          await _runAction(() => repo.setPriority(widget.ticketId, id),
              success: 'Priority updated');
        });
      case 'transfer':
        await _pickMeta(MetaKind.departments, (id) async {
          await _runAction(() => repo.transfer(widget.ticketId, id),
              success: 'Transferred');
          await _load();
        });
      case 'assign':
        await _pickMeta(MetaKind.agents, (id) async {
          await _runAction(() => repo.assign(widget.ticketId, staffId: id),
              success: 'Assigned');
          await _load();
        });
      case 'topic':
        await _pickMeta(MetaKind.topics, (id) async {
          await _runAction(() => repo.setTopic(widget.ticketId, id),
              success: 'Topic updated');
          await _load();
        });
      case 'owner':
        final user = await pickUser(context, ref);
        if (user != null) {
          await _runAction(() => repo.setOwner(widget.ticketId, user.id),
              success: 'Owner changed');
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
        date.year, date.month, date.day, time?.hour ?? 17, time?.minute ?? 0);
    await _runAction(
        () => ref
            .read(ticketsRepositoryProvider)
            .setDueDate(widget.ticketId, duedate: Fmt.apiDateTime(due)),
        success: 'Due date set');
    await _load();
  }

  Future<void> _markState() async {
    const states = {
      'answered': 'Answered',
      'unanswered': 'Unanswered',
      'overdue': 'Overdue',
      'notoverdue': 'Not overdue',
    };
    final chosen = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ListView(
        shrinkWrap: true,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        children: [
          for (final e in states.entries)
            ListTile(
              title: Text(e.value),
              onTap: () => Navigator.pop(context, e.key),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await _runAction(() => ref.read(ticketsRepositoryProvider).mark(widget.ticketId, chosen),
        success: 'Marked ${states[chosen]!.toLowerCase()}');
    await _load();
  }

  Future<void> _manageTags() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TagsSheet(ticketId: widget.ticketId),
    );
  }

  Future<void> _manageCollaborators() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CollaboratorsSheet(ticketId: widget.ticketId),
    );
  }

  Future<void> _pickMeta(String kind, Future<void> Function(int id) onPick) async {
    final items = await ref.read(metaRepositoryProvider).get(kind);
    if (!mounted) return;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ListView(
        shrinkWrap: true,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        children: [
          for (final m in items)
            ListTile(
              title: Text(m.name),
              onTap: () => Navigator.pop(context, m.id),
            ),
        ],
      ),
    );
    if (chosen != null) await onPick(chosen);
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete ticket?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
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

  Future<void> _openComposer({required bool isNote}) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _Composer(ticketId: widget.ticketId, isNote: isNote),
    );
    if (sent == true) await _load();
  }
}

// --- Header -----------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ticket.subject,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
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
                    dense: true),
            ],
          ),
          if (ticket.sla != null && ticket.sla!.frac != null) ...[
            const SizedBox(height: 12),
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
            Text('SLA: ${ticket.sla!.label ?? '—'}',
                style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
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
                    child: Text(label,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ),
                  Expanded(
                      child: Text(value,
                          style: const TextStyle(
                              fontWeight: FontWeight.w500))),
                ],
              ),
            ),
        if (ticket.customFields.isNotEmpty) ...[
          const Divider(height: 28),
          Text('Custom fields',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final e in ticket.customFields.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                      width: 130,
                      child: Text(e.key,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant))),
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
                    Text(e.description ?? e.state,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
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

// --- Composer (reply/note) --------------------------------------------------

class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.ticketId, required this.isNote});
  final int ticketId;
  final bool isNote;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final _body = TextEditingController();
  bool _alert = true;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_body.text.trim().isEmpty) {
      setState(() => _error = 'Message is required');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      if (widget.isNote) {
        await repo.note(widget.ticketId, body: _body.text.trim());
      } else {
        await repo.reply(widget.ticketId,
            body: _body.text.trim(), alert: _alert);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final insets = mq.viewInsets.bottom + mq.padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.isNote ? 'Internal note' : 'Reply to requester',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            maxLines: 6,
            minLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.isNote
                  ? 'Visible to staff only'
                  : 'Type your reply…',
              errorText: _error,
            ),
          ),
          if (!widget.isNote)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _alert,
              onChanged: (v) => setState(() => _alert = v),
              title: const Text('Send alert to requester'),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : Text(widget.isNote ? 'Add note' : 'Send reply'),
          ),
        ],
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
      final tags = await ref.read(ticketsRepositoryProvider).tags(widget.ticketId);
      if (mounted) {
        setState(() {
          _tags = tags;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final tags =
          await ref.read(ticketsRepositoryProvider).addTag(widget.ticketId, name: name);
      _name.clear();
      if (mounted) setState(() => _tags = tags);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(int tagId) async {
    setState(() => _busy = true);
    try {
      final tags =
          await ref.read(ticketsRepositoryProvider).removeTag(widget.ticketId, tagId);
      if (mounted) setState(() => _tags = tags);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final insets = mq.viewInsets.bottom + mq.padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + insets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tags', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Collaborators',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_collabs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No collaborators'),
            )
          else
            ConstrainedBox(
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
