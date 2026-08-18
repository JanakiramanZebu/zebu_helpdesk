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
import '../../models/meta.dart';
import '../../models/user.dart';
import '../../providers.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/composer_actions.dart';
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
      // Tell the list screens a ticket now exists so they refetch rows and
      // tab count badges without waiting for a manual pull-to-refresh.
      ref.read(ticketsChangedProvider.notifier).bump();
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
    // Offer Camera / Photo / File, then pick from the chosen source (mirrors
    // the reply composer's "+" attach flow).
    final source = await pickAttachSource(context);
    if (source == null || !mounted) return;
    final picked = await pickAttachmentsOf(source);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final f in picked) {
        if (!_files.any((e) => e.name == f.name)) _files.add(f);
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

  /// Picks a saved reply and splices its (rich) body into the message at the
  /// cursor.
  Future<void> _insertCanned() async {
    final canned = await pickCannedResponse(context, ref);
    if (canned == null || !mounted) return;
    insertRichHtml(_message, canned.body);
    setState(() {
      if (_messageError != null) _messageError = null;
    });
  }

  /// Picks a knowledgebase article and splices its answer into the message. The
  /// list payload may omit the body, so we fetch the full article when needed.
  Future<void> _insertFaq() async {
    final faq = await pickFaqArticle(context, ref);
    if (faq == null || !mounted) return;
    var html = faq.answer ?? '';
    if (html.trim().isEmpty) {
      try {
        final full = await ref.read(faqRepositoryProvider).get(faq.id);
        html = full.answer ?? '';
      } on ApiException {
        // Nothing to insert.
      }
    }
    if (!mounted || html.trim().isEmpty) return;
    insertRichHtml(_message, html);
    setState(() {
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

  /// Uppercase caption header sitting above a grouped card section — matches
  /// the settings-style section headers used across the app (e.g. the More tab).
  Widget _sectionLabel(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: AppText.captionText(
      context,
      title.toUpperCase(),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fw: 2,
    ),
  );

  /// Wraps a set of list [rows] in a flat, rounded "list group" surface —
  /// a hairline border, no card elevation — with an inset divider between each
  /// row (aligned under the label column: 16 pad + 20 icon + 14 gap = 50).
  Widget _group(List<Widget> rows, {double dividerIndent = 50}) {
    final scheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        children.add(
          Divider(
            height: 1,
            indent: dividerIndent,
            color: scheme.outlineVariant,
          ),
        );
      }
      children.add(rows[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

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
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  _ErrorBanner(message: _error!),
                ],

                // --- Requester & collaborators ---------------------------
                _sectionLabel('Requester'),
                _group([
                  _ListRow(
                    icon: Icons.person_outline,
                    label: 'Requester',
                    value: _user?.name,
                    hint: 'Required · tap to choose',
                    error:
                        _fieldErrors['user_id'] ??
                        (_attempted && _user == null
                            ? 'Please select a requester'
                            : null),
                    onTap: () async {
                      final u = await pickUser(context, ref);
                      if (u != null) setState(() => _user = u);
                    },
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ListRow(
                        icon: Icons.group_outlined,
                        label: 'Collaborators (Cc)',
                        value: _collaborators.isEmpty
                            ? null
                            : '${_collaborators.length} added',
                        hint: 'Optional',
                        trailing: IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: _addCollaborator,
                        ),
                        onTap: _addCollaborator,
                      ),
                      if (_collaborators.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final c in _collaborators)
                                Chip(
                                  label: Text(c.name),
                                  onDeleted: () => setState(
                                    () => _collaborators.remove(c),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ]),

                // --- Ticket details (Gmail-style compose) ----------------
                _sectionLabel('Ticket details'),
                _group([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                    child: TextFormField(
                      controller: _subject,
                      focusNode: _subjectFocus,
                      textInputAction: TextInputAction.next,
                      style: AppText.style(context, fontSize: 15, fw: 1),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Subject is required'
                          : null,
                      decoration: InputDecoration(
                        hintText: 'Subject',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        errorText: _fieldErrors['subject'],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: RichMessageField(
                      controller: _message,
                      hintText: 'Type your message…',
                      bordered: false,
                      onInsertCanned: _insertCanned,
                      onInsertFaq: _insertFaq,
                      errorText: _messageError ?? _fieldErrors['message'],
                    ),
                  ),
                ], dividerIndent: 0),

                // --- Attachments -----------------------------------------
                _sectionLabel('Attachments'),
                _group([
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ListRow(
                        icon: Icons.attach_file,
                        label: 'Files',
                        value: _files.isEmpty
                            ? null
                            : '${_files.length} attached',
                        hint: 'No files added',
                        trailing: TextButton.icon(
                          onPressed: _pickFiles,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add'),
                        ),
                        onTap: _pickFiles,
                      ),
                      if (_files.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Wrap(
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
                                    constraints: const BoxConstraints(
                                      maxWidth: 180,
                                    ),
                                    child: Text(
                                      '${f.name}  ·  ${Fmt.fileSize(f.size)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  onDeleted: () =>
                                      setState(() => _files.remove(f)),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ]),

                // --- Properties ------------------------------------------
                _sectionLabel('Properties'),
                _group([
                  _ListRow(
                    icon: Icons.podcasts_outlined,
                    label: 'Source',
                    value: _source,
                    onTap: _pickSource,
                  ),
                  _ListRow(
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
                  _ListRow(
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
                  _ListRow(
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
                  _ListRow(
                    icon: Icons.event_outlined,
                    label: 'Due date',
                    value: _due == null ? null : Fmt.dateTime(_due),
                    trailing: _due == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _due = null),
                          ),
                    onTap: _pickDue,
                  ),
                  _ListRow(
                    icon: Icons.assignment_ind_outlined,
                    label: 'Assign to agent',
                    value: _agent?.name,
                    trailing: _agent == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            visualDensity: VisualDensity.compact,
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
                  _ListRow(
                    icon: Icons.groups_outlined,
                    label: 'Assign to team',
                    value: _team?.name,
                    trailing: _team == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            visualDensity: VisualDensity.compact,
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
                  _ListRow(
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
                ]),

                // --- Internal note ---------------------------------------
                _sectionLabel('Internal note'),
                _group([
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: TextField(
                      controller: _internalNote,
                      minLines: 2,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: 'Visible to staff only',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        icon: Icon(Icons.lock_outline, size: 20),
                      ),
                    ),
                  ),
                ]),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: AppText.paraText(
                          context,
                          _missingHint,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  onPressed: (_saving || !_canSubmit) ? null : _submit,
                  icon: _saving
                      ? const SizedBox.shrink()
                      : const Icon(Icons.check_circle_outline, size: 20),
                  label: _saving
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

/// A compact, single-line "settings list" row: a small muted leading icon, the
/// field label, its selected value (or a hint) trailing on the right, and a
/// chevron. Flat and simple — no tinted badge, no stacked value. An [error]
/// paints the value line in the error color.
class _ListRow extends StatelessWidget {
  const _ListRow({
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
    final scheme = Theme.of(context).colorScheme;
    final hasError = error != null;
    final display = error ?? value ?? hint;
    final valueColor = hasError
        ? scheme.error
        : value != null
        ? scheme.onSurface
        : scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: hasError ? scheme.error : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            AppText.subText(context, label, fw: 0),
            const SizedBox(width: 12),
            Expanded(
              child: display == null
                  ? const SizedBox.shrink()
                  : AppText.subText(
                      context,
                      display,
                      color: valueColor,
                      fw: value != null ? 1 : 0,
                      align: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const SizedBox(width: 4),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
          ],
        ),
      ),
    );
  }
}
