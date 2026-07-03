import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:parchment/codecs.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../models/canned.dart';
import '../../models/meta.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/date_picker_sheet.dart';
import '../../widgets/pickers.dart';
import '../../widgets/rich_message_field.dart';

/// Ticket source options (the `source` param), mirroring the web dropdown.
const _sources = ['Phone', 'Email', 'Web', 'Other'];

/// `POST /tickets` — create a ticket for an existing user.
class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _message = FleatherController();
  final _internalNote = TextEditingController();
  // Focus target so a failed submit can jump to the empty subject field.
  final _subjectFocus = FocusNode();
  final _scrollCtrl = ScrollController();
  // Set true once the user first tries to submit, so the Requester tile only
  // shows its "Required" error after an attempt (not on a pristine form).
  bool _attempted = false;

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
  String? _messageError;

  @override
  void initState() {
    super.initState();
    // Rebuild the submit button's enabled state as the required text changes.
    _subject.addListener(_onRequiredChanged);
    _message.addListener(_onRequiredChanged);
  }

  void _onRequiredChanged() => setState(() {
    // Clear the message error once the user has typed something.
    if (_messageError != null && _messageText.isNotEmpty) _messageError = null;
  });

  /// Plain-text view of the rich message, for empty/required checks.
  String get _messageText => _message.document.toPlainText().trim();

  /// Requester, subject and message are the required fields.
  bool get _canSubmit =>
      _user != null &&
      _subject.text.trim().isNotEmpty &&
      _messageText.isNotEmpty;

  @override
  void dispose() {
    _subject.removeListener(_onRequiredChanged);
    _message.removeListener(_onRequiredChanged);
    _subject.dispose();
    _message.dispose();
    _internalNote.dispose();
    _subjectFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) => AppSnack.info(context, msg);

  Future<void> _submit() async {
    setState(() => _attempted = true);
    // Validate the subject field inline via the Form, and the rich message
    // separately (it's not a FormField).
    final formOk = _formKey.currentState?.validate() ?? false;
    final messageOk = _messageText.isNotEmpty;
    setState(() => _messageError = messageOk ? null : 'Message is required');
    if (_user == null) {
      // Surface the missing requester on its own tile and scroll it into view.
      setState(() => _error = 'Pick a requester first');
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    if (!formOk || !messageOk) return;
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
          'message': parchmentHtml.encode(_message.document),
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
    final s = await showAppSheet<String>(
      context: context,
      builder: (_) => AppSheet(
        title: 'Source',
        scrollable: false,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in _sources)
              PickerOptionTile(
                label: o,
                selected: o == _source,
                onTap: () => Navigator.pop(context, o),
              ),
          ],
        ),
      ),
    );
    if (s != null) setState(() => _source = s);
  }

  Future<void> _pickCanned() async {
    final c = await showAppSheet<CannedResponse>(
      context: context,
      builder: (_) => const _CannedPickerSheet(),
    );
    if (c == null) return;
    // Insert the canned body's text into the rich document. The document
    // always ends with a trailing "\n", so its editable length is length - 1.
    final doc = _message.document;
    final end = doc.length - 1;
    final text = Fmt.stripHtml(c.body);
    final insert = end > 0 ? '\n\n$text' : text;
    _message.replaceText(
      end,
      0,
      insert,
      selection: TextSelection.collapsed(offset: end + insert.length),
    );
    setState(() {
      _canned = c;
      if (_messageError != null) _messageError = null;
    });
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await pickDate(
      context,
      initial: _due ?? now,
      first: DateTime(now.year, now.month, now.day), // today at the earliest
      last: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due ?? now),
    );
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 17,
      time?.minute ?? 0,
    );
    // Reject a due time already in the past (e.g. today + an earlier hour).
    if (picked.isBefore(DateTime.now())) {
      _toast('Due date must be in the future');
      return;
    }
    setState(() => _due = picked);
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: AppText.subText(context, title, fw: 2),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: AppText.titleText(context, 'New ticket', fw: 1)),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _saving,
          child: Form(
            key: _formKey,
            autovalidateMode: _attempted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                if (_saving) const LinearProgressIndicator(minHeight: 2),
                if (_error != null) ...[
                  _ErrorBanner(message: _error!),
                  const SizedBox(height: 12),
                ],

              // --- User & collaborators ---------------------------------
              _section('User & collaborators'),
              _PickerTile(
                icon: Icons.person_outline,
                label: 'Requester',
                value: _user?.name,
                hint: 'Required',
                error: _fieldErrors['user_id'] ??
                    (_attempted && _user == null
                        ? 'Please select a requester'
                        : null),
                onTap: () async {
                  final u = await pickUser(context, ref);
                  if (u != null) setState(() => _user = u);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.group_outlined),
                title: AppText.subText(context, 'Collaborators (Cc)'),
                subtitle: AppText.paraText(
                  context,
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
              TextFormField(
                controller: _subject,
                focusNode: _subjectFocus,
                textInputAction: TextInputAction.next,
                validator: (v) => (v ?? '').trim().isEmpty
                    ? 'Subject is required'
                    : null,
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
              RichMessageField(
                controller: _message,
                label: 'Message',
                hintText: 'Type your message…',
                errorText: _messageError ?? _fieldErrors['message'],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  AppText.subText(context, 'Attachments'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _pickFiles,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Add files'),
                  ),
                ],
              ),
              if (_files.isEmpty)
                AppText.subText(
                  context,
                  'No files added',
                  color: scheme.onSurfaceVariant,
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
                    selectedId: _topic?.id,
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
                    selectedId: _department?.id,
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
                    selectedId: _priority?.id,
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
                    selectedId: _agent?.id,
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
                    selectedId: _team?.id,
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
                    selectedId: _status?.id,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_canSubmit && !_saving) ...[
                  AppText.paraText(
                    context,
                    _missingHint,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: (_saving || !_canSubmit) ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Create ticket'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Human-readable list of the still-missing required fields, shown above the
  /// disabled submit button.
  String get _missingHint {
    final missing = <String>[
      if (_user == null) 'requester',
      if (_subject.text.trim().isEmpty) 'subject',
      if (_messageText.isEmpty) 'message',
    ];
    if (missing.isEmpty) return '';
    return 'Add ${missing.join(', ')} to continue';
  }
}

/// A prominent inline error banner (icon + tinted container) shown at the top
/// of the form for submit-level failures.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: AppText.subText(
              context,
              message,
              color: scheme.error,
              fw: 0,
            ),
          ),
        ],
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
      title: AppText.subText(context, label),
      subtitle: AppText.subText(
        context,
        value ?? hint ?? 'Not set',
        color: error != null
            ? theme.colorScheme.error
            : value != null
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant,
        fw: value != null ? 1 : null,
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
    return AppSheet(
      title: 'Canned responses',
      scrollable: false,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: AppText.subText(context, _error!),
                    )
                  : _items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: AppText.subText(context, 'No canned responses'),
                    )
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final c = _items[i];
                        return ListTile(
                          title: AppText.subText(context, c.title),
                          subtitle: AppText.paraText(
                            context,
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
