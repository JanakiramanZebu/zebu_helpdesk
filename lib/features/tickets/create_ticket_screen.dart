import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../models/canned.dart';
import '../../models/meta.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/pickers.dart';

/// Ticket source options (the `source` param), mirroring the web dropdown.
const _sources = ['Phone', 'Email', 'Web', 'Other'];

/// `POST /tickets` — create a ticket for an existing user.
class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _internalNote = TextEditingController();

  AppUser? _user;
  final List<AppUser> _collaborators = [];
  String _source = 'Phone';
  MetaItem? _topic;
  MetaItem? _department;
  MetaItem? _priority;
  MetaItem? _status;
  MetaItem? _agent;
  MetaItem? _team;
  DateTime? _due;
  CannedResponse? _canned;
  final List<PlatformFile> _files = [];

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    _internalNote.dispose();
    super.dispose();
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _submit() async {
    if (_user == null) {
      setState(() => _error = 'Pick a requester first');
      return;
    }
    if (_subject.text.trim().isEmpty || _message.text.trim().isEmpty) {
      setState(() => _error = 'Subject and message are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final repo = ref.read(ticketsRepositoryProvider);
      final ticket = await repo.create(
        {
          'user_id': _user!.id,
          'subject': _subject.text.trim(),
          'message': _message.text.trim(),
          'source': _source,
          if (_topic != null) 'topic_id': _topic!.id,
          if (_department != null) 'dept_id': _department!.id,
          if (_priority != null) 'priority_id': _priority!.id,
          if (_due != null) 'duedate': Fmt.apiDateTime(_due!),
        },
        files: [
          for (final f in _files)
            if (f.bytes != null)
              MultipartFile.fromBytes(f.bytes!, filename: f.name),
        ],
      );

      // Apply assignment / status / collaborators / note via their dedicated
      // endpoints (best-effort, so none can fail the create itself).
      if (_agent != null || _team != null) {
        try {
          await repo.assign(
            ticket.id,
            staffId: _agent?.id,
            teamId: _team?.id,
          );
        } catch (_) {}
      }
      if (_status != null) {
        try {
          await repo.setStatus(ticket.id, _status!.id);
        } catch (_) {}
      }
      for (final c in _collaborators) {
        try {
          await repo.addCollaborator(ticket.id, c.id);
        } catch (_) {}
      }
      if (_internalNote.text.trim().isNotEmpty) {
        try {
          await repo.note(ticket.id, body: _internalNote.text.trim());
        } catch (_) {}
      }

      if (!mounted) return;
      _toast('Ticket #${ticket.number} created');
      context.pushReplacement(Routes.ticket(ticket.id));
    } on ApiException catch (e) {
      setState(() {
        _error = e.fields.isEmpty ? e.message : null;
        _fieldErrors = e.fields;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true, // need bytes to upload on every platform
    );
    if (res == null || !mounted) return;
    setState(() {
      for (final f in res.files) {
        if (f.bytes != null && !_files.any((e) => e.name == f.name)) {
          _files.add(f);
        }
      }
    });
  }

  Future<void> _addCollaborator() async {
    final u = await pickUser(context, ref);
    if (u != null && !_collaborators.any((c) => c.id == u.id)) {
      setState(() => _collaborators.add(u));
    }
  }

  Future<void> _pickSource() async {
    final s = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in _sources)
              ListTile(
                title: Text(o),
                trailing: o == _source
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(context, o),
              ),
          ],
        ),
      ),
    );
    if (s != null) setState(() => _source = s);
  }

  Future<void> _pickCanned() async {
    final c = await showModalBottomSheet<CannedResponse>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CannedPickerSheet(),
    );
    if (c == null) return;
    setState(() {
      _canned = c;
      final text = Fmt.stripHtml(c.body);
      final current = _message.text.trim();
      _message.text = current.isEmpty ? text : '$current\n\n$text';
    });
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due ?? now),
    );
    setState(() {
      _due = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 17,
        time?.minute ?? 0,
      );
    });
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New ticket')),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_saving) const LinearProgressIndicator(minHeight: 2),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: scheme.error)),
                const SizedBox(height: 12),
              ],

              // --- User & collaborators ---------------------------------
              _section('User & collaborators'),
              _PickerTile(
                icon: Icons.person_outline,
                label: 'Requester',
                value: _user?.name,
                hint: 'Required',
                error: _fieldErrors['user_id'],
                onTap: () async {
                  final u = await pickUser(context, ref);
                  if (u != null) setState(() => _user = u);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.group_outlined),
                title: const Text('Collaborators (Cc)'),
                subtitle: Text(
                  _collaborators.isEmpty
                      ? 'Optional'
                      : '${_collaborators.length} added',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addCollaborator,
                ),
                onTap: _addCollaborator,
              ),
              if (_collaborators.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _collaborators)
                      Chip(
                        label: Text(c.name),
                        onDeleted: () =>
                            setState(() => _collaborators.remove(c)),
                      ),
                  ],
                ),

              // --- Ticket details ---------------------------------------
              _section('Ticket details'),
              TextField(
                controller: _subject,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Subject',
                  errorText: _fieldErrors['subject'],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickCanned,
                icon: const Icon(Icons.bolt_outlined, size: 18),
                label: Text(
                  _canned == null
                      ? 'Insert canned response'
                      : 'Canned: ${_canned!.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _message,
                minLines: 4,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                  errorText: _fieldErrors['message'],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Attachments', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Add files'),
                  ),
                ],
              ),
              if (_files.isEmpty)
                Text(
                  'No files added',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in _files)
                      Chip(
                        avatar: const Icon(
                          Icons.insert_drive_file_outlined,
                          size: 18,
                        ),
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            '${f.name}  ·  ${Fmt.fileSize(f.size)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        onDeleted: () => setState(() => _files.remove(f)),
                      ),
                  ],
                ),

              // --- Options ----------------------------------------------
              _section('Options'),
              _PickerTile(
                icon: Icons.podcasts_outlined,
                label: 'Source',
                value: _source,
                onTap: _pickSource,
              ),
              _PickerTile(
                icon: Icons.topic_outlined,
                label: 'Help topic',
                value: _topic?.name,
                onTap: () async {
                  final m = await pickMeta(
                    context,
                    ref,
                    MetaKind.topics,
                    title: 'Help topic',
                  );
                  if (m != null) setState(() => _topic = m);
                },
              ),
              _PickerTile(
                icon: Icons.apartment_outlined,
                label: 'Department',
                value: _department?.name,
                onTap: () async {
                  final m = await pickMeta(
                    context,
                    ref,
                    MetaKind.departments,
                    title: 'Department',
                  );
                  if (m != null) setState(() => _department = m);
                },
              ),
              _PickerTile(
                icon: Icons.flag_outlined,
                label: 'Priority',
                value: _priority?.name,
                onTap: () async {
                  final m = await pickMeta(
                    context,
                    ref,
                    MetaKind.priorities,
                    title: 'Priority',
                  );
                  if (m != null) setState(() => _priority = m);
                },
              ),
              _PickerTile(
                icon: Icons.event_outlined,
                label: 'Due date',
                value: _due == null ? null : Fmt.dateTime(_due),
                trailing: _due == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _due = null),
                      ),
                onTap: _pickDue,
              ),
              _PickerTile(
                icon: Icons.assignment_ind_outlined,
                label: 'Assign to agent',
                value: _agent?.name,
                trailing: _agent == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _agent = null),
                      ),
                onTap: () async {
                  final m = await pickMeta(
                    context,
                    ref,
                    MetaKind.agents,
                    title: 'Assign to agent',
                  );
                  if (m != null) setState(() => _agent = m);
                },
              ),
              _PickerTile(
                icon: Icons.groups_outlined,
                label: 'Assign to team',
                value: _team?.name,
                trailing: _team == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _team = null),
                      ),
                onTap: () async {
                  final m = await pickMeta(
                    context,
                    ref,
                    MetaKind.teams,
                    title: 'Assign to team',
                  );
                  if (m != null) setState(() => _team = m);
                },
              ),
              _PickerTile(
                icon: Icons.label_outline,
                label: 'Status',
                value: _status?.name,
                onTap: () async {
                  final m = await pickMeta(
                    context,
                    ref,
                    MetaKind.statuses,
                    title: 'Status',
                  );
                  if (m != null) setState(() => _status = m);
                },
              ),

              // --- Internal note ----------------------------------------
              _section('Internal note'),
              TextField(
                controller: _internalNote,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Internal note (optional)',
                  alignLabelWithHint: true,
                  hintText: 'Visible to staff only',
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              child: const Text('Create ticket'),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tappable row that shows a selected value (or a hint) — used for pickers.
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.hint,
    this.error,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? value;
  final String? hint;
  final String? error;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(
        value ?? hint ?? 'Not set',
        style: TextStyle(
          color: error != null
              ? theme.colorScheme.error
              : value != null
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: value != null ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Bottom-sheet picker over the canned-response list.
class _CannedPickerSheet extends ConsumerStatefulWidget {
  const _CannedPickerSheet();

  @override
  ConsumerState<_CannedPickerSheet> createState() => _CannedPickerSheetState();
}

class _CannedPickerSheetState extends ConsumerState<_CannedPickerSheet> {
  List<CannedResponse> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await ref.read(cannedRepositoryProvider).list(limit: 50);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Canned responses',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _error != null
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
                  : _items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No canned responses'),
                    )
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final c = _items[i];
                        return ListTile(
                          title: Text(c.title),
                          subtitle: Text(
                            Fmt.stripHtml(c.body),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
