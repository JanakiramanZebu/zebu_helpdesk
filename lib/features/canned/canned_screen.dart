import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../models/canned.dart';
import '../../providers.dart';
import '../../widgets/attachment_tile.dart';
import '../../widgets/paged_list_view.dart';

class CannedScreen extends ConsumerStatefulWidget {
  const CannedScreen({super.key});

  @override
  ConsumerState<CannedScreen> createState() => _CannedScreenState();
}

class _CannedScreenState extends ConsumerState<CannedScreen> {
  int _reload = 0;

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  void _refresh() => setState(() => _reload++);

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(cannedRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Canned Responses')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        child: const Icon(Icons.add),
      ),
      body: PagedListView<CannedResponse>(
        refreshKey: _reload,
        emptyMessage: 'No canned responses',
        emptyIcon: Icons.quickreply_outlined,
        fetch: (page) => repo.list(page: page),
        itemBuilder: (context, c) => _CannedCard(
          canned: c,
          onTap: () => _openDetail(c),
          onEdit: () => _openEdit(c),
          onDelete: () => _confirmDelete(c),
        ),
      ),
    );
  }

  Future<void> _openDetail(CannedResponse c) async {
    final repo = ref.read(cannedRepositoryProvider);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) {
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                c.title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(Fmt.stripHtml(c.body)),
              if (c.notes != null && c.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Notes', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(c.notes!),
              ],
              FutureBuilder(
                future: repo.attachments(c.id),
                builder: (context, snap) {
                  final atts = snap.data ?? const [];
                  if (atts.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      Text('Attachments',
                          style: Theme.of(context).textTheme.titleSmall),
                      for (final a in atts) AttachmentTile(attachment: a),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: Fmt.stripHtml(c.body)));
                  if (context.mounted) Navigator.pop(context);
                  _toast('Copied');
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openCreate() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CannedEditor(),
    );
    if (saved == true) _refresh();
  }

  Future<void> _openEdit(CannedResponse c) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CannedEditor(existing: c),
    );
    if (saved == true) _refresh();
  }

  Future<void> _confirmDelete(CannedResponse c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete response?'),
        content: Text('Delete "${c.title}"? This cannot be undone.'),
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
      await ref.read(cannedRepositoryProvider).delete(c.id);
      _toast('Deleted');
      _refresh();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }
}

class _CannedCard extends StatelessWidget {
  const _CannedCard({
    required this.canned,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final CannedResponse canned;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      canned.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Fmt.stripHtml(canned.body),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (!canned.isEnabled || canned.isGlobal) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          if (!canned.isEnabled)
                            _chip(context, 'Disabled', theme.colorScheme.error),
                          if (canned.isGlobal)
                            _chip(context, 'Global', theme.colorScheme.primary),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}

/// Create / edit bottom sheet.
class _CannedEditor extends ConsumerStatefulWidget {
  const _CannedEditor({this.existing});
  final CannedResponse? existing;

  @override
  ConsumerState<_CannedEditor> createState() => _CannedEditorState();
}

class _CannedEditorState extends ConsumerState<_CannedEditor> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _response =
      TextEditingController(text: widget.existing?.body ?? '');
  late bool _enabled = widget.existing?.isEnabled ?? true;

  bool _saving = false;
  final Map<String, String> _fieldErrors = {};

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _title.dispose();
    _response.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _fieldErrors.clear();
    });
    final repo = ref.read(cannedRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.update(widget.existing!.id, {
          'title': _title.text.trim(),
          'response': _response.text.trim(),
          'is_enabled': _enabled,
        });
      } else {
        await repo.create(
          title: _title.text.trim(),
          response: _response.text.trim(),
          isEnabled: _enabled,
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
          Text(_isEdit ? 'Edit response' : 'New canned response',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: 'Title',
              errorText: _fieldErrors['title'],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _response,
            maxLines: 6,
            minLines: 3,
            decoration: InputDecoration(
              labelText: 'Response',
              alignLabelWithHint: true,
              errorText: _fieldErrors['response'],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
            title: const Text('Enabled'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : Text(_isEdit ? 'Save changes' : 'Create'),
          ),
        ],
      ),
    );
  }
}
