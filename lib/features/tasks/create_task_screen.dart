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
import '../../data/tasks_repository.dart';
import '../../models/meta.dart';
import '../../models/task.dart';
import '../../providers.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/composer_actions.dart';
import '../../widgets/date_picker_sheet.dart';
import '../../widgets/pickers.dart';
import '../../widgets/rich_message_field.dart';
import '../../widgets/states.dart';

/// `POST /tasks` — create a task.
class CreateTaskScreen extends ConsumerStatefulWidget {
  const CreateTaskScreen({super.key, this.ticketId, this.ticketNumber});

  /// When opened from a ticket ("Create task"), the task is linked to it via
  /// `ticket_id`. [ticketNumber] is only for display.
  final int? ticketId;
  final String? ticketNumber;

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
  // Set true once the user first tries to submit, so required-field errors only
  // show after an attempt (not on a pristine form).
  bool _attempted = false;

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;
  String? _descriptionError;

  @override
  void initState() {
    super.initState();
    // Rebuild the submit button's enabled state as the required text changes.
    _title.addListener(_onRequiredChanged);
    _description.addListener(_onRequiredChanged);
  }

  void _onRequiredChanged() => setState(() {
    if (_descriptionError != null && _descriptionText.isNotEmpty) {
      _descriptionError = null;
    }
  });

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

  /// Department, title and description are the required fields.
  bool get _canSubmit =>
      _department != null &&
      _title.text.trim().isNotEmpty &&
      _descriptionText.isNotEmpty;

  Future<void> _submit() async {
    setState(() => _attempted = true);
    final descriptionOk = _descriptionText.isNotEmpty;
    setState(
      () => _descriptionError = descriptionOk ? null : 'Description is required',
    );
    if (_department == null) {
      setState(() => _error = 'Pick a department first');
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }
    if (_title.text.trim().isEmpty || !descriptionOk) return;
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final task = await ref.read(tasksRepositoryProvider).create(
        {
          'dept_id': _department!.id,
          'title': _title.text.trim(),
          'description': parchmentHtml.encode(_description.document),
          if (_priority != null) 'priority_id': _priority!.id,
          if (_due != null) 'duedate': Fmt.apiDateTime(_due!),
          if (_parent != null) 'parent_id': _parent!.id,
          if (widget.ticketId != null) 'ticket_id': widget.ticketId,
        },
        files: [
          for (final f in _files)
            if (f.bytes != null)
              MultipartFile.fromBytes(f.bytes!, filename: f.name),
        ],
      );
      if (!mounted) return;
      _toast('Task #${task.number} created');
      context.pushReplacement(Routes.task(task.id));
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

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await pickDate(
      context,
      initial: _due ?? now,
      first: now.subtract(const Duration(days: 1)),
      last: now.add(const Duration(days: 365 * 3)),
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
      appBar: AppBar(title: AppText.titleText(context, 'New task', fw: 1)),
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

              // --- Task details (Gmail-style compose) ------------------
              _sectionLabel('Task details'),
              _group([
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                  child: TextField(
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
                      errorText: _fieldErrors['title'],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: RichMessageField(
                    controller: _description,
                    hintText: 'Describe the task…',
                    bordered: false,
                    onInsertCanned: _insertCanned,
                    onInsertFaq: _insertFaq,
                    errorText:
                        _descriptionError ?? _fieldErrors['description'],
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
                  icon: Icons.apartment_outlined,
                  label: 'Department',
                  value: _department?.name,
                  hint: 'Required · tap to choose',
                  error:
                      _fieldErrors['dept_id'] ??
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
                  onTap: () async {
                    final t = await showAppSheet<Task>(
                      context: context,
                      builder: (_) => const _ParentTaskSheet(),
                    );
                    if (t != null) setState(() => _parent = t);
                  },
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
                      : const Text('Create task'),
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
      if (_department == null) 'department',
      if (_title.text.trim().isEmpty) 'title',
      if (_descriptionText.isEmpty) 'description',
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

/// Bottom-sheet task search/picker (`GET /tasks?q=`) for choosing a parent task.
class _ParentTaskSheet extends ConsumerStatefulWidget {
  const _ParentTaskSheet();

  @override
  ConsumerState<_ParentTaskSheet> createState() => _ParentTaskSheetState();
}

class _ParentTaskSheetState extends ConsumerState<_ParentTaskSheet> {
  final _ctrl = TextEditingController();
  List<Task> _results = [];
  bool _loading = false;
  Object? _error;
  String _lastQuery = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// Debounce keystrokes so we issue one `GET /tasks?q=` after the user pauses,
  /// not one per character.
  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    _debounce?.cancel();
    _lastQuery = q;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(tasksRepositoryProvider).list(
        TaskQuery(view: 'all', q: q.isEmpty ? null : q, limit: 25),
      );
      if (!mounted) return;
      setState(() {
        _results = page.items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Select parent task',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetSearchField(
            controller: _ctrl,
            autofocus: true,
            hintText: 'Search task by number or title',
            onChanged: _onChanged,
            onSubmitted: _search,
            onClear: () => _search(''),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? ErrorView(
                    error: _error!,
                    compact: true,
                    onRetry: () => _search(_lastQuery),
                  )
                : _results.isEmpty
                ? Center(child: AppText.subText(context, 'No tasks found'))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final t = _results[i];
                      return ListTile(
                        title: AppText.subText(
                          context,
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: AppText.subText(
                          context,
                          '#${t.number} · ${t.statusName}',
                        ),
                        onTap: () => Navigator.pop(context, t),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
