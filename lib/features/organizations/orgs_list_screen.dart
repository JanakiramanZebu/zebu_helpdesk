import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/router/routes.dart';
import '../../models/organization.dart';
import '../../providers.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/paged_list_view.dart';

class OrgsListScreen extends ConsumerStatefulWidget {
  const OrgsListScreen({super.key});

  @override
  ConsumerState<OrgsListScreen> createState() => _OrgsListScreenState();
}

class _OrgsListScreenState extends ConsumerState<OrgsListScreen> {
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
      builder: (_) => const _CreateOrgSheet(),
    );
    if (created == true) {
      _toast('Organization created');
      if (mounted) setState(() => _refreshKey++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(orgsRepositoryProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Organizations'),
            if (_total != null)
              Text('$_total total', style: theme.textTheme.bodySmall),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: AppSearchField(
              controller: _searchCtrl,
              hintText: 'Search organizations',
              onSubmitted: (v) => setState(() => _q = v.trim()),
              onClear: () => setState(() => _q = ''),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        child: const Icon(Icons.add_business),
      ),
      body: PagedListView<Organization>(
        refreshKey: '$_q|$_refreshKey',
        emptyMessage: 'No organizations',
        emptyHint: 'Try a different search.',
        emptyIcon: Icons.apartment,
        onTotalChanged: (t) {
          if (mounted && t != _total) setState(() => _total = t);
        },
        fetch: (page) => repo.list(q: _q.isEmpty ? null : _q, page: page),
        itemBuilder: (context, o) {
          final subtitle = o.domain != null && o.domain!.isNotEmpty
              ? '${o.userCount} users · ${o.domain}'
              : '${o.userCount} users';
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primary.withValues(
                  alpha: 0.14,
                ),
                child: Icon(Icons.apartment, color: theme.colorScheme.primary),
              ),
              title: Text(o.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => context.push(Routes.organization(o.id)),
            ),
          );
        },
      ),
    );
  }
}

class _CreateOrgSheet extends ConsumerStatefulWidget {
  const _CreateOrgSheet();

  @override
  ConsumerState<_CreateOrgSheet> createState() => _CreateOrgSheetState();
}

class _CreateOrgSheetState extends ConsumerState<_CreateOrgSheet> {
  final _name = TextEditingController();
  final _domain = TextEditingController();
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
      final domain = _domain.text.trim();
      await ref.read(orgsRepositoryProvider).create({
        'name': _name.text.trim(),
        if (domain.isNotEmpty) 'domain': domain,
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
            'New organization',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
            controller: _domain,
            decoration: InputDecoration(
              labelText: 'Domain (optional)',
              hintText: 'example.com',
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
                : const Text('Create organization'),
          ),
        ],
      ),
    );
  }
}
