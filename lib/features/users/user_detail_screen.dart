import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../models/common.dart';
import '../../models/ticket.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/paged_list_view.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';
import '../tickets/widgets/ticket_card.dart';

class UserDetailScreen extends ConsumerStatefulWidget {
  const UserDetailScreen({super.key, required this.userId});
  final int userId;

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  AppUser? _user;
  Object? _error;
  bool _loading = true;
  final int _ticketsKey = 0;

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
      final user = await ref.read(usersRepositoryProvider).get(widget.userId);
      if (!mounted) return;
      setState(() {
        _user = user;
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
      case 'clear-org':
        await _clearOrg();
      case 'register':
      case 'lock':
      case 'unlock':
      case 'reset-password':
        await _accountAction(value);
      case 'delete':
        await _confirmDelete();
    }
  }

  Future<void> _openEdit() async {
    final u = _user;
    if (u == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditUserSheet(user: u),
    );
    if (saved == true) {
      _toast('User updated');
      await _load();
    }
  }

  Future<void> _clearOrg() async {
    try {
      await ref.read(usersRepositoryProvider).setOrg(widget.userId, null);
      _toast('Organization cleared');
      await _load();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _accountAction(String action) async {
    try {
      final result =
          await ref.read(usersRepositoryProvider).account(widget.userId, action);
      final detail = result.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      _toast(detail.isEmpty ? 'Done: $action' : detail);
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete user?'),
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
      await ref.read(usersRepositoryProvider).delete(widget.userId);
      if (mounted) {
        _toast('User deleted');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    return Scaffold(
      appBar: AppBar(
        title: Text(u?.name ?? 'User'),
        actions: [
          if (u != null)
            PopupMenuButton<String>(
              onSelected: _onMenu,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'clear-org', child: Text('Clear organization')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'register', child: Text('Register account')),
                PopupMenuItem(value: 'lock', child: Text('Lock account')),
                PopupMenuItem(value: 'unlock', child: Text('Unlock account')),
                PopupMenuItem(
                    value: 'reset-password', child: Text('Reset password')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
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
                    _Header(user: u!),
                    TabBar(
                      controller: _tabs,
                      tabs: const [
                        Tab(text: 'Tickets'),
                        Tab(text: 'Notes'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          _UserTicketsTab(
                            userId: widget.userId,
                            refreshKey: _ticketsKey,
                          ),
                          _NotesTab(userId: widget.userId),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

// --- Header -----------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: user.name, radius: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(user.email, style: theme.textTheme.bodyMedium),
                    if (user.phone != null && user.phone!.isNotEmpty)
                      Text(user.phone!, style: theme.textTheme.bodySmall),
                    if (user.org != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.apartment,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(user.org!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (user.customFields.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final e in user.customFields.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(e.key,
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant)),
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

// --- Tickets tab ------------------------------------------------------------

class _UserTicketsTab extends ConsumerWidget {
  const _UserTicketsTab({required this.userId, required this.refreshKey});
  final int userId;
  final int refreshKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(usersRepositoryProvider);
    return PagedListView<Ticket>(
      refreshKey: refreshKey,
      emptyMessage: 'No tickets',
      fetch: (page) => repo.tickets(userId, page: page),
      itemBuilder: (context, t) => TicketCard(
        ticket: t,
        onTap: () => context.push(Routes.ticket(t.id)),
      ),
    );
  }
}

// --- Notes tab --------------------------------------------------------------

class _NotesTab extends ConsumerStatefulWidget {
  const _NotesTab({required this.userId});
  final int userId;

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
      final notes = await ref.read(usersRepositoryProvider).notes(widget.userId);
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
      await ref.read(usersRepositoryProvider).addNote(widget.userId, text);
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
      await ref
          .read(usersRepositoryProvider)
          .deleteNote(widget.userId, note.id);
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
                                child: const Icon(Icons.delete,
                                    color: Colors.white),
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
                          child: CircularProgressIndicator(strokeWidth: 2.2))
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

class _EditUserSheet extends ConsumerStatefulWidget {
  const _EditUserSheet({required this.user});
  final AppUser user;

  @override
  ConsumerState<_EditUserSheet> createState() => _EditUserSheetState();
}

class _EditUserSheetState extends ConsumerState<_EditUserSheet> {
  late final _name = TextEditingController(text: widget.user.name);
  late final _email = TextEditingController(text: widget.user.email);
  late final _phone = TextEditingController(text: widget.user.phone ?? '');
  bool _saving = false;
  String? _formError;
  final _fieldErrors = <String, String>{};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _formError = null;
      _fieldErrors.clear();
    });
    try {
      await ref.read(usersRepositoryProvider).update(widget.user.id, {
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
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
          Text('Edit user', style: Theme.of(context).textTheme.titleMedium),
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
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              errorText: _fieldErrors['email'],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone',
              errorText: _fieldErrors['phone'],
            ),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 12),
            Text(_formError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : const Text('Save changes'),
          ),
        ],
      ),
    );
  }
}
