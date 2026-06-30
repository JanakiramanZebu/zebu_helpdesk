import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/router/routes.dart';
import '../../models/saved_queue.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/states.dart';

class QueuesScreen extends ConsumerStatefulWidget {
  const QueuesScreen({super.key});

  @override
  ConsumerState<QueuesScreen> createState() => _QueuesScreenState();
}

class _QueuesScreenState extends ConsumerState<QueuesScreen> {
  String? _type; // null = all, 'ticket', 'task'
  List<SavedQueue>? _queues;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final queues = await ref.read(queuesRepositoryProvider).list(type: _type);
      if (!mounted) return;
      setState(() {
        _queues = queues;
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

  void _setType(String? type) {
    setState(() => _type = type);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Queues'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                _filterChip('All', null),
                const SizedBox(width: 8),
                _filterChip('Tickets', 'ticket'),
                const SizedBox(width: 8),
                _filterChip('Tasks', 'task'),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _filterChip(String label, String? type) => ChoiceChip(
    label: Text(label),
    selected: _type == type,
    onSelected: (_) => _setType(type),
  );

  Widget _buildBody() {
    if (_loading && _queues == null) return const LoadingView();
    if (_error != null && _queues == null) {
      return ErrorView(error: _error!, onRetry: _load);
    }
    final queues = _queues ?? const [];
    return RefreshIndicator(
      onRefresh: _load,
      child: queues.isEmpty
          ? ListView(
              children: const [
                SizedBox(
                  height: 360,
                  child: EmptyView(
                    icon: Icons.bookmark_border,
                    message: 'No saved queues',
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: queues.length,
              itemBuilder: (context, i) => _QueueCard(
                queue: queues[i],
                onTap: () => _onTap(queues[i]),
                onEdit: () => _openEdit(queues[i]),
                onDelete: () => _confirmDelete(queues[i]),
              ),
            ),
    );
  }

  void _onTap(SavedQueue queue) {
    if (queue.type == 'ticket') {
      context.push(Routes.tickets);
    } else {
      _toast('Task queues open in the tasks list.');
    }
  }

  Future<void> _openCreate() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _QueueEditor(),
    );
    if (saved == true) _load();
  }

  Future<void> _openEdit(SavedQueue queue) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QueueEditor(existing: queue),
    );
    if (saved == true) _load();
  }

  Future<void> _confirmDelete(SavedQueue queue) async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete queue?',
      message: 'Delete "${queue.fullName}"? This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ref.read(queuesRepositoryProvider).delete(queue.id);
      _toast('Deleted');
      _load();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.queue,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final SavedQueue queue;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tags = <String>[
      if (queue.public) 'Public',
      if (queue.personal) 'Personal',
    ];
    final criteriaCount = queue.criteria.length;
    final summary = StringBuffer();
    if (tags.isNotEmpty) summary.write(tags.join(' · '));
    if (criteriaCount > 0) {
      if (summary.isNotEmpty) summary.write('  ·  ');
      summary.write('$criteriaCount filter${criteriaCount == 1 ? '' : 's'}');
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(
          queue.type == 'task'
              ? Icons.task_alt
              : Icons.confirmation_number_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          queue.fullName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: summary.isEmpty ? null : Text(summary.toString()),
        trailing: queue.editable
            ? PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              )
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Create a personal queue / rename an existing editable queue.
class _QueueEditor extends ConsumerStatefulWidget {
  const _QueueEditor({this.existing});
  final SavedQueue? existing;

  @override
  ConsumerState<_QueueEditor> createState() => _QueueEditorState();
}

class _QueueEditorState extends ConsumerState<_QueueEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  final _q = TextEditingController();

  bool _saving = false;
  final Map<String, String> _fieldErrors = {};

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _q.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _fieldErrors.clear();
    });
    final repo = ref.read(queuesRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.update(widget.existing!.id, {'name': _name.text.trim()});
      } else {
        final q = _q.text.trim();
        await repo.create(
          name: _name.text.trim(),
          criteria: q.isEmpty ? null : {'q': q},
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        if (e.fields.isNotEmpty) {
          _fieldErrors.addAll(e.fields);
        } else {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(e.message)));
        }
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
            _isEdit ? 'Rename queue' : 'New personal queue',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _fieldErrors['name'],
            ),
          ),
          if (!_isEdit) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _q,
              decoration: const InputDecoration(
                labelText: 'Search filter (optional)',
                hintText: 'Keyword to match',
              ),
            ),
          ],
          const SizedBox(height: 12),
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
                : Text(_isEdit ? 'Save' : 'Create'),
          ),
        ],
      ),
    );
  }
}
