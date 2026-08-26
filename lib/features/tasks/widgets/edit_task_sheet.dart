import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_text.dart';
import '../../../models/meta.dart';
import '../../../models/task.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_snack.dart';
import '../../../widgets/date_picker_sheet.dart';
import '../../../widgets/pickers.dart';

/// The mobile twin of the web's task edit surfaces
/// (`include/staff/templates/task-edit.tmpl.php`, plus the inline pencils on
/// `task-view.tmpl.php`): *Task Details* (Title, Due Date) then *Priority &
/// Hierarchy* (Priority, Parent Task) and an optional internal note.
///
/// The web hides Due Date on a closed task — that row becomes "Completed" —
/// so [Task.isOpen] gates it here too.
///
/// Description is deliberately absent: its seed flags (`0x650F3`) leave
/// `FLAG_AGENT_EDIT` unset, so osTicket edits it through the thread entry's
/// own pencil, which the thread already offers.
///
/// Returns `true` when something was saved, so the caller can reload.
Future<bool?> showEditTaskDialog(
  BuildContext context, {
  required Task task,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _EditTaskSheet(task: task),
);

class _EditTaskSheet extends ConsumerStatefulWidget {
  const _EditTaskSheet({required this.task});

  final Task task;

  @override
  ConsumerState<_EditTaskSheet> createState() => _EditTaskSheetState();
}

class _EditTaskSheetState extends ConsumerState<_EditTaskSheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();

  DateTime? _due;
  bool _dueChanged = false;

  MetaItem? _priority;
  bool _priorityChanged = false;

  Task? _parent;
  bool _parentChanged = false;
  bool _loadingParent = false;

  Map<String, String> _errors = const {};
  bool _saving = false;

  Task get _t => widget.task;

  @override
  void initState() {
    super.initState();
    _title.text = _t.title;
    _title.addListener(_onEdited);
    _note.addListener(_onEdited);
    _due = _t.duedate;
    final p = _t.priority;
    if (p != null) _priority = MetaItem(id: p.id, name: p.name);
    _loadParent();
  }

  @override
  void dispose() {
    _title.removeListener(_onEdited);
    _note.removeListener(_onEdited);
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Keep the Save button in step with the text fields.
  void _onEdited() => setState(() {});

  /// The payload names the parent by id only, so resolve it to a row the agent
  /// can recognise (`#number — title`, the same string the web's lookup shows).
  /// A parent that can't be fetched simply renders as its number.
  Future<void> _loadParent() async {
    final pid = _t.parentId;
    if (pid == null) return;
    setState(() => _loadingParent = true);
    try {
      final parent = await ref.read(tasksRepositoryProvider).get(pid);
      if (mounted) setState(() => _parent = parent);
    } on ApiException {
      // Not worth failing the dialog over — the row falls back to "#<id>".
    } finally {
      if (mounted) setState(() => _loadingParent = false);
    }
  }

  // --- Dirty tracking --------------------------------------------------------

  bool get _titleChanged => _title.text.trim() != _t.title.trim();

  bool get _dirty =>
      _titleChanged ||
      _dueChanged ||
      _priorityChanged ||
      _parentChanged ||
      _note.text.trim().isNotEmpty;

  // --- Save ------------------------------------------------------------------

  /// One request per changed field, in the web's order.
  ///
  /// `POST /tasks/{id}/edit` only fails the call when *nothing* applied
  /// (`if ($errors && !$applied)`), so a batch that mixes a good field with a
  /// rejected one returns 200 and drops the rejection on the floor. Sending
  /// each field on its own is exactly what the web's inline pencils do, and it
  /// guarantees a refused value always comes back as a 422 we can show.
  Future<void> _save() async {
    if (!_dirty) return;
    final title = _title.text.trim();
    if (_titleChanged && title.isEmpty) {
      setState(() => _errors = const {'title': 'Title is required'});
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final repo = ref.read(tasksRepositoryProvider);
    final id = _t.id;
    try {
      if (_titleChanged) {
        await repo.edit(id, fields: {'title': title});
      }
      if (_dueChanged) {
        await repo.edit(id, fields: {
          'duedate': _due == null ? '' : Fmt.apiDateTime(_due!),
        });
      }
      // Priority and parent are prod columns on the same endpoint, applied in
      // a single save — the web sets them together from one form too. `0`
      // clears either one (`((int)$in[...]) ?: null`).
      if (_priorityChanged || _parentChanged) {
        await repo.edit(
          id,
          priorityId: _priorityChanged ? (_priority?.id ?? 0) : null,
          parentId: _parentChanged ? (_parent?.id ?? 0) : null,
        );
      }
      final note = _note.text.trim();
      if (note.isNotEmpty) {
        await repo.note(id, body: note, title: 'Task Updated');
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors = e.fields;
        if (e.fields.isEmpty) AppSnack.error(context, e.message);
      });
    }
  }

  /// A field error, preferring the API's own message. `field` is what
  /// `Task::updateField()` keys its own failures under, and `columns` is the
  /// endpoint's catch-all for the priority/parent save.
  String? _error(String key) => _errors[key] ?? _errors['field'];

  // --- Field editors ---------------------------------------------------------

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    // An overdue task's date sits before `first`, which the picker asserts on.
    final initial = (_due == null || _due!.isBefore(firstDate))
        ? firstDate
        : _due!;
    final date = await pickDate(
      context,
      initial: initial,
      first: firstDate,
      last: DateTime(now.year + 3, now.month, now.day),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_due ?? now),
    );
    if (!mounted) return;
    final due = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 17,
      time?.minute ?? 0,
    );
    // The same rule the backend enforces (`'future' => true` on the special
    // duedate field), caught here so it doesn't cost a round trip.
    if (due.isBefore(DateTime.now())) {
      AppSnack.error(context, 'Due date must be in the future');
      return;
    }
    setState(() {
      _due = due;
      _dueChanged = true;
      _errors = const {};
    });
  }

  Future<void> _pickPriority() async {
    final m = await pickMeta(
      context,
      ref,
      MetaKind.taskPriorities,
      title: 'Priority',
      selectedId: _priority?.id,
    );
    if (m == null || !mounted) return;
    setState(() {
      _priority = m;
      _priorityChanged = true;
      _errors = const {};
    });
  }

  Future<void> _pickParent() async {
    final picked = await pickTask(
      context,
      title: 'Parent task',
      // The server refuses a task as its own parent (and any cycle); drop the
      // obvious case from the list rather than letting it 422.
      excludeIds: {_t.id},
    );
    if (picked == null || !mounted) return;
    setState(() {
      _parent = picked;
      _parentChanged = true;
      _errors = const {};
    });
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) => AppDialog(
    title: 'Edit Task',
    actionLabel: 'Save',
    actionEnabled: _dirty,
    actionBusy: _saving,
    onAction: _save,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Task Details'),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Title',
            errorText: _errors['title'],
          ),
        ),
        const SizedBox(height: 16),
        // The web swaps this row for a read-only "Completed" date once the
        // task is closed, so there is nothing to edit here either.
        if (_t.isOpen)
          _SheetRow(
            label: 'Due Date',
            value: _due == null ? null : Fmt.dateTime(_due),
            placeholder: 'Not set',
            icon: Icons.event_outlined,
            error: _error('duedate'),
            onTap: _pickDue,
            onClear: _due == null
                ? null
                : () => setState(() {
                    _due = null;
                    _dueChanged = true;
                    _errors = const {};
                  }),
          ),
        const SizedBox(height: 18),
        _label('Priority & Hierarchy'),
        _SheetRow(
          label: 'Priority',
          value: _priority?.name,
          placeholder: '— None —',
          icon: Icons.flag_outlined,
          error: _errors['columns'],
          onTap: _pickPriority,
          onClear: _priority == null
              ? null
              : () => setState(() {
                  _priority = null;
                  _priorityChanged = true;
                  _errors = const {};
                }),
        ),
        const SizedBox(height: 14),
        _SheetRow(
          label: 'Parent Task',
          value: _parentLabel,
          placeholder: 'None — top-level task',
          icon: Icons.account_tree_outlined,
          error: _errors['parent_id'],
          hint: 'Leave blank for a top-level task.',
          onTap: _pickParent,
          onClear: (_parent == null && _t.parentId == null)
              ? null
              : () => setState(() {
                  _parent = null;
                  _parentChanged = true;
                  _errors = const {};
                }),
        ),
        const SizedBox(height: 18),
        _label('Internal Note'),
        TextField(
          controller: _note,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Reason for editing the task (optional)',
            alignLabelWithHint: true,
          ),
        ),
      ],
    ),
  );

  /// `#number — title`, or a bare id while the lookup is still in flight (or
  /// after it failed), so a set parent never renders as "None".
  String? get _parentLabel {
    final p = _parent;
    if (p != null) return '#${p.number} — ${p.title}';
    if (_parentChanged) return null; // cleared by the agent
    final pid = _t.parentId;
    if (pid == null) return null;
    return _loadingParent ? 'Loading…' : '#$pid';
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppText.paraText(context, text.toUpperCase(), fw: 1),
  );
}

/// A labelled, tappable value row with an optional Clear action — the sheet's
/// equivalent of the web's inline pencil.
class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.icon,
    required this.onTap,
    this.onClear,
    this.error,
    this.hint,
  });

  final String label;
  final String? value;
  final String placeholder;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final String? error;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unset = value == null || value!.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AppText.paraText(
                context,
                label,
                fw: 0,
                color: error != null ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
            if (onClear != null)
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: AppText.paraText(context, 'Clear', color: scheme.primary),
              ),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: InputDecorator(
            decoration: InputDecoration(
              errorText: error,
              suffixIcon: Icon(icon, size: 20),
            ),
            child: AppText.subText(
              context,
              unset ? placeholder : value!,
              color: unset ? scheme.onSurfaceVariant : scheme.onSurface,
              fw: unset ? null : 0,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (hint != null && error == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: AppText.paraText(
              context,
              hint!,
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
