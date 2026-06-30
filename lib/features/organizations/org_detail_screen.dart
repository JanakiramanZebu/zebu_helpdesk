import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../models/common.dart';
import '../../models/organization.dart';
import '../../models/ticket.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/paged_list_view.dart';
import '../../widgets/states.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/user_avatar.dart';
import '../tickets/widgets/ticket_card.dart';

class OrgDetailScreen extends ConsumerStatefulWidget {
  const OrgDetailScreen({super.key, required this.orgId});
  final int orgId;

  @override
  ConsumerState<OrgDetailScreen> createState() => _OrgDetailScreenState();
}

class _OrgDetailScreenState extends ConsumerState<OrgDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  Organization? _org;
  Object? _error;
  bool _loading = true;
  int _membersKey = 0;

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
    try {
      final org = await ref.read(orgsRepositoryProvider).get(widget.orgId);
      if (!mounted) return;
      setState(() {
        _org = org;
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

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _onMenu(String value) async {
    switch (value) {
      case 'edit':
        await _openEdit();
      case 'delete':
        await _confirmDelete();
    }
  }

  Future<void> _openEdit() async {
    final o = _org;
    if (o == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditOrgSheet(org: o),
    );
    if (saved == true) {
      _toast('Organization updated');
      await _load();
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete organization?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ref.read(orgsRepositoryProvider).delete(widget.orgId);
      if (mounted) {
        _toast('Organization deleted');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _org;
    return Scaffold(
      appBar: AppBar(
        title: Text(o?.name ?? 'Organization'),
        actions: [
          if (o != null)
            PopupMenuButton<String>(
              onSelected: _onMenu,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const LoadingView()
            : _error != null
            ? ErrorView(error: _error!, onRetry: _load)
            : Column(
                children: [
                  _Header(org: o!),
                  TabBar(
                    controller: _tabs,
                    tabs: const [
                      Tab(text: 'Members'),
                      Tab(text: 'Tickets'),
                      Tab(text: 'Notes'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _MembersTab(
                          orgId: widget.orgId,
                          refreshKey: _membersKey,
                          onRemoved: () => setState(() => _membersKey++),
                        ),
                        _OrgTicketsTab(orgId: widget.orgId),
                        _NotesTab(orgId: widget.orgId),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// --- Header -----------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.org});
  final Organization org;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String?)>[
      ('Domain', org.domain),
      ('Manager', org.manager?.name),
      ('Sharing', org.sharing),
      ('Members', '${org.userCount}'),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            org.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            if (value != null && value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (org.collabAll)
                const StatusChip(label: 'Collab all', dense: true),
              if (org.collabPrimary)
                const StatusChip(label: 'Collab primary', dense: true),
              if (org.autoAssign)
                const StatusChip(label: 'Auto-assign', dense: true),
            ],
          ),
          if (org.customFields.isNotEmpty) ...[
            const Divider(height: 24),
            for (final e in org.customFields.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        e.key,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: Text(e.value)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// --- Members tab ------------------------------------------------------------

class _MembersTab extends ConsumerWidget {
  const _MembersTab({
    required this.orgId,
    required this.refreshKey,
    required this.onRemoved,
  });
  final int orgId;
  final int refreshKey;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(orgsRepositoryProvider);
    return PagedListView<AppUser>(
      refreshKey: refreshKey,
      emptyMessage: 'No members',
      emptyIcon: Icons.people_outline,
      fetch: (page) => repo.users(orgId, page: page),
      itemBuilder: (context, u) => Dismissible(
        key: ValueKey(u.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          color: Theme.of(context).colorScheme.error,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.person_remove, color: Colors.white),
        ),
        onDismissed: (_) async {
          try {
            await repo.removeUser(orgId, u.id);
            onRemoved();
          } on ApiException catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(e.message)));
            }
            onRemoved();
          }
        },
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: UserAvatar(name: u.name),
            title: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              u.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => context.push(Routes.user(u.id)),
          ),
        ),
      ),
    );
  }
}

// --- Tickets tab ------------------------------------------------------------

class _OrgTicketsTab extends ConsumerWidget {
  const _OrgTicketsTab({required this.orgId});
  final int orgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(orgsRepositoryProvider);
    return PagedListView<Ticket>(
      emptyMessage: 'No tickets',
      fetch: (page) => repo.tickets(orgId, page: page),
      itemBuilder: (context, t) =>
          TicketCard(ticket: t, onTap: () => context.push(Routes.ticket(t.id))),
    );
  }
}

// --- Notes tab --------------------------------------------------------------

class _NotesTab extends ConsumerStatefulWidget {
  const _NotesTab({required this.orgId});
  final int orgId;

  @override
  ConsumerState<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends ConsumerState<_NotesTab> {
  final _note = TextEditingController();
  List<StaffNote> _notes = [];
  Object? _error;
  bool _loading = true;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notes = await ref.read(orgsRepositoryProvider).notes(widget.orgId);
      if (!mounted) return;
      setState(() {
        _notes = notes;
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

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _add() async {
    final text = _note.text.trim();
    if (text.isEmpty) return;
    setState(() => _adding = true);
    try {
      await ref.read(orgsRepositoryProvider).addNote(widget.orgId, text);
      _note.clear();
      if (mounted) FocusScope.of(context).unfocus();
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _delete(StaffNote note) async {
    try {
      await ref.read(orgsRepositoryProvider).deleteNote(widget.orgId, note.id);
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _loading
              ? const LoadingView()
              : _error != null
              ? ErrorView(error: _error!, onRetry: _load)
              : _notes.isEmpty
              ? const EmptyView(message: 'No notes')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _notes.length,
                  itemBuilder: (context, i) {
                    final n = _notes[i];
                    return Dismissible(
                      key: ValueKey(n.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        color: Theme.of(context).colorScheme.error,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _delete(n),
                      child: ListTile(
                        title: Text(n.body),
                        subtitle: Text(
                          '${n.staff?.name ?? 'Staff'} · ${Fmt.ago(n.created)}',
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _note,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Add a note…',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _adding ? null : _add,
                  icon: _adding
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --- Edit sheet -------------------------------------------------------------

class _EditOrgSheet extends ConsumerStatefulWidget {
  const _EditOrgSheet({required this.org});
  final Organization org;

  @override
  ConsumerState<_EditOrgSheet> createState() => _EditOrgSheetState();
}

class _EditOrgSheetState extends ConsumerState<_EditOrgSheet> {
  late final _name = TextEditingController(text: widget.org.name);
  late final _domain = TextEditingController(text: widget.org.domain ?? '');
  bool _saving = false;
  String? _formError;
  final _fieldErrors = <String, String>{};

  @override
  void dispose() {
    _name.dispose();
    _domain.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _formError = null;
      _fieldErrors.clear();
    });
    try {
      await ref.read(orgsRepositoryProvider).update(widget.org.id, {
        'name': _name.text.trim(),
        'domain': _domain.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        _formError = e.fields.isEmpty ? e.message : null;
        _fieldErrors.addAll(e.fields);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
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
          Text(
            'Edit organization',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _fieldErrors['name'],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _domain,
            decoration: InputDecoration(
              labelText: 'Domain',
              errorText: _fieldErrors['domain'],
            ),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 12),
            Text(
              _formError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save changes'),
          ),
        ],
      ),
    );
  }
}
