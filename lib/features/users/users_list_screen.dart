import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/router/routes.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/paged_list_view.dart';
import '../../widgets/user_avatar.dart';

class UsersListScreen extends ConsumerStatefulWidget {
  const UsersListScreen({super.key});

  @override
  ConsumerState<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends ConsumerState<UsersListScreen> {
  String _q = '';
  final _searchCtrl = TextEditingController();
  int _refreshKey = 0;
  int? _total;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _openCreate() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CreateUserSheet(),
    );
    if (created == true) {
      _toast('User created');
      if (mounted) setState(() => _refreshKey++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(usersRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Users'),
            if (_total != null)
              Text(
                '$_total total',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AppSearchField(
              controller: _searchCtrl,
              hintText: 'Search users',
              onSubmitted: (v) => setState(() => _q = v.trim()),
              onClear: () => setState(() => _q = ''),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        child: const Icon(Icons.person_add),
      ),
      body: PagedListView<AppUser>(
        refreshKey: '$_q|$_refreshKey',
        emptyMessage: 'No users',
        emptyHint: 'Try a different search.',
        emptyIcon: Icons.people_outline,
        onTotalChanged: (t) {
          if (mounted && t != _total) setState(() => _total = t);
        },
        fetch: (page) => repo.list(q: _q.isEmpty ? null : _q, page: page),
        itemBuilder: (context, u) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: UserAvatar(name: u.name),
            title: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              u.org != null ? '${u.email} · ${u.org!.name}' : u.email,
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

class _CreateUserSheet extends ConsumerStatefulWidget {
  const _CreateUserSheet();

  @override
  ConsumerState<_CreateUserSheet> createState() => _CreateUserSheetState();
}

class _CreateUserSheetState extends ConsumerState<_CreateUserSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
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
      await ref
          .read(usersRepositoryProvider)
          .create(
            name: _name.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
          );
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
          Text('New user', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
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
              labelText: 'Phone (optional)',
              errorText: _fieldErrors['phone'],
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
                : const Text('Create user'),
          ),
        ],
      ),
    );
  }
}
