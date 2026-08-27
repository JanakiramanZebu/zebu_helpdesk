import 'dart:async';

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
import '../../models/task.dart';
import '../../providers.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/composer_actions.dart';
import '../../widgets/date_picker_sheet.dart';
import '../../widgets/pickers.dart';
import '../../widgets/rich_message_field.dart';

/// `POST /tasks` — create a task.
class CreateTaskScreen extends ConsumerStatefulWidget {
  const CreateTaskScreen({
    super.key,
    this.ticketId,
    this.ticketNumber,
    this.parentTask,
  });

  /// When opened from a ticket ("Create task"), the task is linked to it via
  /// `ticket_id`. [ticketNumber] is only for display.
  final int? ticketId;
  final String? ticketNumber;

  /// When opened from a task's "Add subtask", the parent it hangs under. The
  /// subtask is created through the same `POST /tasks` as any other task, with
  /// `parent_id` set — which is what the web does ("New Subtask of #6090" is
  /// the ordinary task form with Parent Task pre-filled). A subtask is validated
  /// like any staff-created task, so it still needs a department and a due date;
  /// the department is seeded from the parent and both stay editable.
  final Task? parentTask;

  @override
  ConsumerState<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends ConsumerState<CreateTaskScreen> {
  final _title = TextEditingController();
  final _description = FleatherController();

  MetaItem? _department;
  MetaItem? _priority;
  DateTime? _due;
  Task? _parent;
  final List<PlatformFile> _files = [];

  final _scrollCtrl = ScrollController();
  // Anchors so a failed submit can scroll the first offending required field
  // into view — Title/Description sit up top, Department/Due date lower.
  final _titleKey = GlobalKey();
  final _descriptionKey = GlobalKey();
  final _departmentKey = GlobalKey();
  final _dueKey = GlobalKey();
  // Set true once the user first tries to submit, so required-field errors only
  // show after an attempt (not on a pristine form).
  bool _attempted = false;

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;
  String? _titleError;
  String? _descriptionError;
  String? _dueError;

  @override
  void initState() {
    super.initState();
    // Rebuild the submit button's enabled state as the required text changes.
    _title.addListener(_onRequiredChanged);
    _description.addListener(_onRequiredChanged);
    final parent = widget.parentTask;
    if (parent != null) {
      _parent = parent;
      _seedDepartmentFrom(parent);
    }
  }

  /// Copies [parent]'s department onto the form. The server does not inherit
  /// it, so we seed it here rather than making the agent re-pick the one it is
  /// already looking at — and the web's subtask form does the same, pre-filled
  /// from the parent and still editable, so a parent picked later overwrites
  /// whatever sits on the row. Returns false when the parent carries no
  /// department id, which is what we have to post.
  bool _seedDepartmentFrom(Task parent) {
    if (parent.departmentId == null) return false;
    _department = MetaItem(
      id: parent.departmentId!,
      name: parent.departmentName ?? 'Department',
    );
    return true;
  }

  /// Picks the parent task and inherits its department (TC_789) — the picker
  /// path used to set the parent alone, so only a subtask started from a task's
  /// "Add subtask" ever inherited anything. A picked row may serve `department`
  /// as a bare name with no id, so fall back to the full task before giving up.
  Future<void> _pickParent() async {
    final picked = await pickTask(context, title: 'Select parent task');
    if (picked == null || !mounted) return;
    setState(() {
      _parent = picked;
      _seedDepartmentFrom(picked);
    });
    if (picked.departmentId != null) return;
    try {
      final full = await ref.read(tasksRepositoryProvider).get(picked.id);
      if (!mounted || _parent?.id != picked.id) return;
      setState(() => _seedDepartmentFrom(full));
    } catch (_) {
      // The department is required and editable anyway; leaving it unset is
      // better than failing the pick over it.
    }
  }

  void _onRequiredChanged() => setState(() {
    if (_titleError != null && _title.text.trim().isNotEmpty) _titleError = null;
    if (_descriptionError != null && _descriptionText.isNotEmpty) {
      _descriptionError = null;
    }
  });

  /// The field-error keys this form has a row for. A server error keyed
  /// anything else has nowhere to land, so it goes to the banner instead.
  static const _renderedFieldKeys = {
    'title',
    'description',
    'dept_id',
    'duedate',
  };

  /// `TaskInternalForm` field ids, as the API returns them in a 422. Priority
  /// and parent go through the form now, so an inactive priority or an invalid
  /// parent comes back keyed by 4 / 5 instead of being silently dropped.
  static const _taskFieldIds = {
    '1': 'dept_id',
    '3': 'duedate',
    '4': 'priority_id',
    '5': 'parent_id',
  };

  static const _fieldLabels = {
    'title': 'Title',
    'description': 'Description',
    'dept_id': 'Department',
    'duedate': 'Due date',
    'priority_id': 'Priority',
    'parent_id': 'Parent task',
  };

  /// "Priority: Invalid" — an error with no row on this form still names the
  /// field it came from instead of arriving as a bare message.
  static String _labelled(String key, String message) {
    final label = _fieldLabels[key];
    final msg = message.trim();
    if (label == null) return msg;
    return msg.isEmpty ? '$label is invalid' : '$label: $msg';
  }

  /// A field-level error to show for [key], preferring a clear, field-named
  /// message over the API's terse `"Required"` (or an empty string). Any other
  /// server message passes through unchanged.
  String? _apiFieldError(String key, String label) {
    final msg = _fieldErrors[key];
    if (msg == null) return null;
    final t = msg.trim();
    return (t.isEmpty || t.toLowerCase() == 'required') ? '$label is required' : t;
  }

  /// The anchor of the first still-missing required field, in top-to-bottom
  /// order, so a failed submit scrolls straight to it.
  GlobalKey? get _firstInvalidKey {
    if (_title.text.trim().isEmpty) return _titleKey;
    if (_descriptionText.isEmpty) return _descriptionKey;
    if (_department == null) return _departmentKey;
    if (_due == null || _dueError != null) return _dueKey;
    return null;
  }

  @override
  void dispose() {
    _title.removeListener(_onRequiredChanged);
    _description.removeListener(_onRequiredChanged);
    _title.dispose();
    _description.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) => AppSnack.success(context, msg);

  /// Plain-text view of the rich description, for empty/required checks.
  String get _descriptionText =>
      _description.document.toPlainText().trim();

  /// The required fields, mirroring the osTicket task create (the `/tasks` API
  /// validates dept_id, title, description; and the due date is required for
  /// staff-created tasks unless a lead-time priority computes it — the API never
  /// sends one, so it is always required).
  bool get _canSubmit =>
      _department != null &&
      _title.text.trim().isNotEmpty &&
      _descriptionText.isNotEmpty &&
      _due != null;

  Future<void> _submit() async {
    setState(() => _attempted = true);
    final titleOk = _title.text.trim().isNotEmpty;
    final descriptionOk = _descriptionText.isNotEmpty;
    // A due date chosen a while ago can have gone stale while the form was
    // being filled in (picked 5 pm, submitted at 6). The server refuses it
    // either way, so catch it here and say so on the row rather than letting
    // the create round-trip and fail.
    final dueOk = _due == null || _due!.isAfter(DateTime.now());
    setState(() {
      _titleError = titleOk ? null : 'Title is required';
      _descriptionError = descriptionOk ? null : 'Description is required';
      _dueError = dueOk ? null : 'Due date must be in the future';
    });
    // Any missing required field (title, description, department or due date)
    // surfaces its own inline error — scroll the first one into view and stop
    // before calling the API.
    if (!_canSubmit || !titleOk || !descriptionOk || !dueOk) {
      final ctx = _firstInvalidKey?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.1,
        );
      }
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      // `POST /tasks` now feeds parent_id and priority_id through
      // TaskInternalForm (field ids 5 and 4) the way the web does, so both are
      // stamped on the row before the insert — and both are validated, which
      // is what [_taskFieldIds] maps back onto this form.
      final parentId = _parent?.id;
      final task = await ref.read(tasksRepositoryProvider).create(
        {
          'dept_id': _department!.id,
          'title': _title.text.trim(),
          'description': parchmentHtml.encode(_description.document),
          if (_priority != null) 'priority_id': _priority!.id,
          if (_due != null) 'duedate': Fmt.apiDateTime(_due!),
          if (parentId != null) 'parent_id': parentId,
          if (widget.ticketId != null) 'ticket_id': widget.ticketId,
        },
        // Only the seeded parent may address the parent-scoped endpoint: it is
        // gated on task.create in *that* task's department, which is what the
        // "Add subtask" action already checks. A parent picked by hand goes
        // through POST /tasks with `parent_id` in the body.
        parentId: parentId != null && parentId == widget.parentTask?.id
            ? parentId
            : null,
        files: [
          for (final f in _files)
            if (f.bytes != null)
              MultipartFile.fromBytes(f.bytes!, filename: f.name),
        ],
      );
      if (!mounted) return;
      // Tell the list screens a task now exists so they refetch rows and tab
      // count badges without waiting for a manual pull-to-refresh (TC_150).
      ref.read(tasksChangedProvider.notifier).bump();
      _toast(
        parentId == null
            ? 'Task #${task.number} created'
            : 'Subtask #${task.number} created',
      );
      context.pushReplacement(Routes.task(task.id));
    } on ApiException catch (e) {
      // The task forms report errors keyed by osTicket's DB field id; name
      // them first so each one either lands on its row or reaches the banner
      // saying which field it belongs to (a rejected due date used to vanish).
      final fields = <String, String>{
        for (final f in e.fields.entries)
          (_taskFieldIds[f.key] ?? f.key): f.value,
      };
      setState(() {
        _fieldErrors = fields;
        final unplaced = [
          for (final f in fields.entries)
            if (!_renderedFieldKeys.contains(f.key)) _labelled(f.key, f.value),
        ];
        _error = unplaced.isNotEmpty
            ? unplaced.join('\n')
            : (fields.isEmpty ? e.message : null);
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

  /// Picks a saved reply and splices its (rich) body into the description at
  /// the cursor.
  Future<void> _insertCanned() async {
    final canned = await pickCannedResponse(context, ref);
    if (canned == null || !mounted) return;
    insertRichHtml(_description, canned.body);
    setState(() {
      if (_descriptionError != null) _descriptionError = null;
    });
  }

  /// Picks a knowledgebase article and splices its answer into the description.
  /// The list payload may omit the body, so we fetch the full article if needed.
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
    insertRichHtml(_description, html);
    setState(() {
      if (_descriptionError != null) _descriptionError = null;
    });
  }

  /// Due date, on the web's terms. osTicket builds this field with
  /// `'min' => Misc::gmtime(), 'future' => true` (`Task::getForm()`,
  /// class.task.php) — the calendar starts at today and the server refuses
  /// anything at or before now with **Due date must be in the future**
  /// (class.task.php:2166). Offering yesterday only produced a date the API
  /// would bounce. The far end is a mobile-only bound: the web's picker has no
  /// maxDate, but a swipeable month grid needs one, so it stops at a true three
  /// years out (not 365×3 days, which falls a day short across a leap year).
  Future<void> _pickDue() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = await pickDate(
      context,
      initial: _due ?? now,
      first: today,
      last: DateTime(now.year + 3, now.month, now.day),
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
    // Today plus an hour already gone is still in the past — the same case the
    // server rejects.
    if (!mounted) return;
    if (picked.isBefore(DateTime.now())) {
      AppSnack.info(context, 'Due date must be in the future');
      return;
    }
    setState(() {
      _due = picked;
      _dueError = null;
      _fieldErrors = {..._fieldErrors}..remove('duedate');
    });
  }

  /// Uppercase caption header sitting above a grouped card section — matches
  /// the create-ticket / settings-style section headers used across the app.
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
      appBar: AppBar(
        title: AppText.titleText(
          context,
          _parent == null ? 'New task' : 'New subtask',
          fw: 1,
        ),
      ),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _saving,
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
              if (widget.ticketId != null) ...[
                const SizedBox(height: 8),
                _LinkBanner(
                  message: widget.ticketNumber != null
                      ? 'This task will be linked to ticket #${widget.ticketNumber}'
                      : 'This task will be linked to the ticket',
                ),
              ],
              // Keyed off the live parent, not the one handed in: the Parent
              // task row can clear a seeded parent or set one on a plain new
              // task, and the banner has to follow it either way (TC_790).
              if (_parent != null) ...[
                const SizedBox(height: 8),
                _LinkBanner(
                  message:
                      'This subtask will be added under '
                      '#${_parent!.number}',
                ),
              ],

              // --- Task details (Gmail-style compose) ------------------
              _sectionLabel('Task details'),
              _group([
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                  child: TextField(
                    key: _titleKey,
                    controller: _title,
                    textInputAction: TextInputAction.next,
                    style: AppText.style(context, fontSize: 15, fw: 1),
                    decoration: InputDecoration(
                      hintText: 'Title',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      errorText: _titleError ?? _apiFieldError('title', 'Title'),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: RichMessageField(
                    key: _descriptionKey,
                    controller: _description,
                    hintText: 'Describe the task…',
                    bordered: false,
                    onInsertCanned: _insertCanned,
                    onInsertFaq: _insertFaq,
                    errorText: _descriptionError ??
                        _apiFieldError('description', 'Description'),
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
                  key: _departmentKey,
                  icon: Icons.apartment_outlined,
                  label: 'Department',
                  value: _department?.name,
                  hint: 'Required · tap to choose',
                  error:
                      _apiFieldError('dept_id', 'Department') ??
                      (_attempted && _department == null
                          ? 'Please select a department'
                          : null),
                  onTap: () async {
                    final m = await pickMeta(
                      context,
                      ref,
                      MetaKind.departments,
                      title: 'Department',
                      selectedId: _department?.id,
                      searchable: true,
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
                      MetaKind.taskPriorities,
                      title: 'Priority',
                      selectedId: _priority?.id,
                    );
                    if (m != null) setState(() => _priority = m);
                  },
                ),
                _ListRow(
                  key: _dueKey,
                  icon: Icons.event_outlined,
                  label: 'Due date',
                  value: _due == null ? null : Fmt.dateTime(_due),
                  hint: 'Required · tap to set',
                  error:
                      _apiFieldError('duedate', 'Due date') ??
                      _dueError ??
                      (_attempted && _due == null
                          ? 'Due date is required'
                          : null),
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
                  icon: Icons.account_tree_outlined,
                  label: 'Parent task',
                  value: _parent == null
                      ? null
                      : '#${_parent!.number} · ${_parent!.title}',
                  trailing: _parent == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _parent = null),
                        ),
                  onTap: _pickParent,
                ),
              ]),
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
                  // Always tappable (except mid-save): tapping an incomplete
                  // form runs validation and surfaces a clear inline error on
                  // each missing field, rather than leaving the user stuck at a
                  // disabled button with no explanation.
                  onPressed: _saving ? null : _submit,
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
                      : Text(
                          _parent == null ? 'Create task' : 'Create subtask',
                        ),
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
      if (_title.text.trim().isEmpty) 'title',
      if (_descriptionText.isEmpty) 'description',
      if (_department == null) 'department',
      if (_due == null) 'due date',
    ];
    if (missing.isEmpty) return '';
    return 'Add ${missing.join(', ')} to continue';
  }
}

/// A prominent inline error banner shown at the top of the form for
/// submit-level failures (mirrors the create-ticket form).
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
            child: AppText.subText(context, message, color: scheme.error, fw: 0),
          ),
        ],
      ),
    );
  }
}

/// An informational banner shown when the task is being created linked to a
/// ticket (mirrors [_ErrorBanner] but in the neutral/primary tone).
class _LinkBanner extends StatelessWidget {
  const _LinkBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: AppText.subText(context, message, color: scheme.primary),
          ),
        ],
      ),
    );
  }
}

/// A compact, single-line "settings list" row: a small muted leading icon, the
/// field label, its selected value (or a hint) trailing on the right, and a
/// chevron. Flat and simple — no tinted badge, no stacked value. An [error]
/// paints the value line in the error color. (Mirrors the create-ticket form.)
class _ListRow extends StatelessWidget {
  const _ListRow({
    super.key,
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
