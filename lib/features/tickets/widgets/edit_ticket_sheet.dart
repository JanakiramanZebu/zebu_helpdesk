import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_text.dart';
import '../../../models/meta.dart';
import '../../../models/ticket.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_snack.dart';
import '../../../widgets/date_picker_sheet.dart';
import 'dynamic_fields_section.dart';

/// The web's ticket sources (`Ticket::getSources()`), in its order. The backend
/// doesn't publish the list, so it lives here exactly as the create screen
/// keeps it.
const _sources = ['Phone', 'Email', 'Web', 'API', 'Other'];

/// The mobile twin of the web's **Update Ticket** form
/// (`include/staff/ticket-edit.inc.php`): the *Ticket Information* block
/// (Ticket Source, Help Topic, SLA Plan, Due Date) followed by the ticket's own
/// form answers (Subject, Priority, then the topic's custom fields) and an
/// optional internal note.
///
/// Returns `true` when something was saved, so the caller can reload.
Future<bool?> showEditTicketDialog(
  BuildContext context, {
  required Ticket ticket,
  bool dueLocked = false,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _EditTicketSheet(ticket: ticket, dueLocked: dueLocked),
);

class _EditTicketSheet extends ConsumerStatefulWidget {
  const _EditTicketSheet({required this.ticket, required this.dueLocked});

  final Ticket ticket;

  /// An active SLA plan computes the due date; the web renders a padlock in
  /// place of the editor and the API refuses the write.
  final bool dueLocked;

  @override
  ConsumerState<_EditTicketSheet> createState() => _EditTicketSheetState();
}

class _EditTicketSheetState extends ConsumerState<_EditTicketSheet> {
  /// Ticket Source / Help Topic / SLA Plan — the web's "Ticket Information".
  List<TicketField> _info = const [];

  /// Subject / Priority / the topic's custom fields — the web's dynamic forms.
  List<TicketField> _details = const [];

  /// Current answers and the values we loaded, keyed by [TicketField.key].
  /// Anything still equal to its loaded value is left out of the payload:
  /// `Ticket::updateField()` refuses a value that didn't change ("... is
  /// already assigned this value"), so posting the whole form fails outright.
  Map<String, dynamic> _values = {};
  Map<String, dynamic> _initial = const {};

  DateTime? _due;
  bool _dueChanged = false;

  final _note = TextEditingController();

  Map<String, String> _errors = const {};
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  Ticket get _t => widget.ticket;

  @override
  void initState() {
    super.initState();
    _due = _t.due;
    _note.addListener(_onNoteChanged);
    _load();
  }

  @override
  void dispose() {
    _note.removeListener(_onNoteChanged);
    _note.dispose();
    super.dispose();
  }

  /// The Save button enables on the first edit, so keep it in step with the
  /// note as well as the fields.
  void _onNoteChanged() => setState(() {});

  Future<void> _load() async {
    final repo = ref.read(ticketsRepositoryProvider);
    final meta = ref.read(metaRepositoryProvider);
    try {
      // The topic's custom fields (and their current answers). Built-in names
      // are excluded server-side, so they're synthesized below.
      final custom = (await repo.fields(_t.id))
          .where((f) => f.editable)
          .toList();
      // A picker whose option list can't be fetched is simply not offered.
      final topics = await _side(meta.topics);
      final priorities = await _side(meta.priorities);
      final slaPlans = await _side(meta.slaPlans);
      if (!mounted) return;

      final info = <TicketField>[
        _choice(
          'source',
          'Ticket Source',
          {for (final s in _sources) s: s},
          value: _t.source,
          required: true,
        ),
        if (topics.isNotEmpty)
          _choice(
            'topic',
            'Help Topic',
            _byId(topics),
            value: _t.topicId == null ? null : '${_t.topicId}',
            required: true,
          ),
        // Only real plans, like the "Set SLA plan" picker: the web's
        // "— None —" maps to id 0, which this endpoint's SLAField rejects.
        if (slaPlans.isNotEmpty)
          _choice(
            'sla',
            'SLA Plan',
            _byId(slaPlans),
            value: (_t.sla?.id ?? 0) == 0 ? null : '${_t.sla!.id}',
          ),
      ];

      final details = <TicketField>[
        TicketField(
          name: 'subject',
          label: 'Subject',
          type: 'text',
          required: true,
          value: _t.subject,
        ),
        if (priorities.isNotEmpty)
          _choice(
            'priority',
            'Priority',
            _byId(priorities),
            // The payload names the priority without its id, so match on it.
            value: _idOfName(priorities, _t.priority),
          ),
        ...custom,
      ];

      final seeded = <String, dynamic>{
        for (final f in [...info, ...details])
          if (f.value != null) f.key: f.value,
      };
      setState(() {
        _info = info;
        _details = details;
        _values = Map<String, dynamic>.from(seeded);
        _initial = seeded;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  /// A side list that isn't worth failing the whole dialog over.
  Future<List<MetaItem>> _side(Future<List<MetaItem>> Function() op) async {
    try {
      return await op();
    } on ApiException {
      return const [];
    }
  }

  TicketField _choice(
    String name,
    String label,
    Map<String, String> choices, {
    String? value,
    bool required = false,
  }) => TicketField(
    name: name,
    label: label,
    type: 'choices',
    required: required,
    choices: choices,
    value: value,
  );

  Map<String, String> _byId(List<MetaItem> items) => {
    for (final i in items) '${i.id}': i.name,
  };

  String? _idOfName(List<MetaItem> items, String? name) {
    if (name == null || name.isEmpty) return null;
    final lower = name.toLowerCase();
    for (final i in items) {
      if (i.name.toLowerCase() == lower) return '${i.id}';
    }
    return null;
  }

  // --- Dirty tracking --------------------------------------------------------

  /// Null and `''` are the same answer here (an unanswered field), so an
  /// untouched blank field never enters the payload.
  bool _same(dynamic a, dynamic b) {
    if (a is List || b is List) {
      final la = a is List ? a.map((e) => '$e').toList() : <String>[];
      final lb = b is List ? b.map((e) => '$e').toList() : <String>[];
      if (la.length != lb.length) return false;
      for (var i = 0; i < la.length; i++) {
        if (la[i] != lb[i]) return false;
      }
      return true;
    }
    return (a?.toString() ?? '') == (b?.toString() ?? '');
  }

  /// Only what the agent actually changed, in the web's field order. `duedate`
  /// goes last: changing the Help Topic cascades its "New Ticket Options"
  /// (priority / SLA / due date) server-side, so an explicit date must be
  /// applied after that.
  Map<String, dynamic> _changed() {
    final out = <String, dynamic>{};
    for (final f in [..._info, ..._details]) {
      if (!_same(_values[f.key], _initial[f.key])) {
        out[f.key] = _values[f.key] ?? '';
      }
    }
    if (_dueChanged) {
      out['duedate'] = _due == null ? '' : Fmt.apiDateTime(_due!);
    }
    return out;
  }

  bool get _dirty => _changed().isNotEmpty || _note.text.trim().isNotEmpty;

  // --- Save ------------------------------------------------------------------

  Future<void> _save() async {
    final changed = _changed();
    final note = _note.text.trim();
    if (changed.isEmpty && note.isEmpty) return;
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      if (changed.isNotEmpty) await repo.editFields(_t.id, changed);
      // The web logs the reason as an internal note on the ticket. Posting it
      // once here keeps it off every single field's own edit event.
      if (note.isNotEmpty) {
        await repo.note(_t.id, body: note, title: 'Ticket updated');
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

  // --- Due date --------------------------------------------------------------

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    // A ticket may already be overdue; the picker asserts if initialDate is
    // before firstDate, so clamp it up to today.
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
    // Same rule the backend enforces (`future => true`).
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

  void _clearDue() => setState(() {
    _due = null;
    _dueChanged = true;
    _errors = const {};
  });

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // The backend refuses to edit a closed ticket, so say so instead of
    // offering a Save that can only 422.
    final closed = _t.isClosed;
    final ready = !_loading && _loadError == null && !closed;
    final hasFields = _info.isNotEmpty || _details.isNotEmpty;
    return AppDialog(
      title: 'Update Ticket',
      actionLabel: ready && hasFields ? 'Save' : null,
      actionEnabled: _dirty,
      actionBusy: _saving,
      onAction: _save,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : closed
          ? _message('Reopen the ticket to edit it')
          : _loadError != null
          ? _message(_loadError!)
          : !hasFields
          ? _message('No editable fields')
          : _form(),
    );
  }

  Widget _message(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: AppText.subText(context, text),
  );

  Widget _form() {
    void onChanged(Map<String, dynamic> v) => setState(() => _values = v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_info.isNotEmpty) ...[
          _label('Ticket Information'),
          DynamicFieldsSection(
            fields: _info,
            values: _values,
            errors: _errors,
            onChanged: onChanged,
          ),
          const SizedBox(height: 14),
        ],
        _DueDateRow(
          due: _due,
          locked: widget.dueLocked,
          error: _errors['duedate'] ?? _errors['field'],
          onPick: _pickDue,
          onClear: _due == null ? null : _clearDue,
        ),
        if (_details.isNotEmpty) ...[
          const SizedBox(height: 18),
          _label('Ticket Details'),
          DynamicFieldsSection(
            fields: _details,
            values: _values,
            errors: _errors,
            onChanged: onChanged,
          ),
        ],
        const SizedBox(height: 18),
        _label('Internal Note'),
        TextField(
          controller: _note,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Reason for editing the ticket (optional)',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppText.paraText(context, text.toUpperCase(), fw: 1),
  );
}

/// The Due Date row: a tappable date+time value, or a padlock and the reason
/// when an active SLA plan computes it (the web drops its editor in the same
/// case).
class _DueDateRow extends StatelessWidget {
  const _DueDateRow({
    required this.due,
    required this.locked,
    required this.onPick,
    this.onClear,
    this.error,
  });

  final DateTime? due;
  final bool locked;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = due == null ? 'Not set' : Fmt.dateTime(due);
    final body = InputDecorator(
      decoration: InputDecoration(
        errorText: error,
        suffixIcon: Icon(
          locked ? Icons.lock_outline : Icons.event_outlined,
          size: 20,
        ),
      ),
      child: AppText.subText(
        context,
        value,
        color: due == null ? scheme.onSurfaceVariant : scheme.onSurface,
        fw: due == null ? null : 0,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: AppText.paraText(
                context,
                'Due Date',
                fw: 0,
                color: error != null ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
            if (!locked && onClear != null)
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
        if (locked)
          body
        else
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPick,
            child: body,
          ),
        if (locked)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: AppText.paraText(
              context,
              'Computed from the SLA plan',
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
