import 'package:flutter/material.dart';

import '../../../core/theme/app_text.dart';
import '../../../models/ticket.dart';
import '../../../widgets/pickers.dart';

/// Renders a topic's dynamic custom form ([TicketField]s, the `GET
/// /tickets/{id}/fields` shape) as editable inputs and reports the collected
/// answers as a `{fieldName: value}` map — exactly the shape `POST /tickets`
/// wants under `custom_fields`.
///
/// Field-type handling mirrors osTicket's form field kinds:
///  * `text` / (default) → single-line text
///  * `memo` / `thread` → multi-line text
///  * `choices` → a tappable row opening a bottom-sheet picker (single), or a
///    wrap of filter chips (multiselect)
///  * `bool` → a switch
///
/// The parent owns the value map: pass the current [values] and handle
/// [onChanged] (called with the full updated map on every edit). [errors] maps
/// a field name to an inline error message (e.g. from a `422` response).
class DynamicFieldsSection extends StatefulWidget {
  const DynamicFieldsSection({
    super.key,
    required this.fields,
    required this.values,
    required this.onChanged,
    this.errors = const {},
  });

  final List<TicketField> fields;
  final Map<String, dynamic> values;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final Map<String, String> errors;

  @override
  State<DynamicFieldsSection> createState() => _DynamicFieldsSectionState();
}

class _DynamicFieldsSectionState extends State<DynamicFieldsSection> {
  /// One controller per text/memo field, keyed by field name.
  final Map<String, TextEditingController> _text = {};

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(DynamicFieldsSection old) {
    super.didUpdateWidget(old);
    // Field set can change when the help topic changes.
    if (!_sameFieldNames(old.fields, widget.fields)) _syncControllers();
  }

  bool _sameFieldNames(List<TicketField> a, List<TicketField> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name) return false;
    }
    return true;
  }

  void _syncControllers() {
    // Dispose controllers for fields that are gone.
    final names = widget.fields.map((f) => f.key).toSet();
    for (final key in _text.keys.toList()) {
      if (!names.contains(key)) {
        _text.remove(key)!.dispose();
      }
    }
    // Create controllers for new text/memo fields, seeded from the value map.
    for (final f in widget.fields) {
      if (_isText(f) && !_text.containsKey(f.key)) {
        _text[f.key] = TextEditingController(
          text: (widget.values[f.key] ?? f.value ?? '').toString(),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Anything that isn't a picker or a switch renders as text. Choice-ness is
  /// decided by [TicketField.isChoice] (i.e. the server sent `choices`), so
  /// custom lists — typed `list-2`, `list-4`, … — don't fall through to here.
  bool _isText(TicketField f) => !f.isChoice && f.type != 'bool';

  bool _isMultiline(TicketField f) => f.type == 'memo' || f.type == 'thread';

  /// Emit a copy of the value map with [name] set to [value] (or removed when
  /// null/empty), so the parent always holds the current answers.
  void _set(String name, dynamic value) {
    final next = Map<String, dynamic>.from(widget.values);
    final isEmpty =
        value == null ||
        (value is String && value.isEmpty) ||
        (value is List && value.isEmpty);
    if (isEmpty) {
      next.remove(name);
    } else {
      next[name] = value;
    }
    // Cascading lists: a new parent selection can invalidate child answers.
    _pruneCascade(next, name);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final f in widget.fields) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
      rows.add(_field(f));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }

  Widget _field(TicketField f) {
    final error = widget.errors[f.key];
    if (f.isChoice) return _choiceField(f, error);
    if (f.type == 'bool') return _boolField(f, error);
    return _textField(f, error);
  }

  /// The field [f] cascades from. `parent_field` names the parent, but answers
  /// are stored under [TicketField.key], so resolve the field itself rather
  /// than indexing the value map by the raw name.
  TicketField? _parentOf(TicketField f) {
    final parent = f.parentField;
    if (parent == null) return null;
    for (final p in widget.fields) {
      if (p.name == parent || p.key == parent) return p;
    }
    return null;
  }

  /// The parent's current answer, or null while it's unset.
  dynamic _parentValue(TicketField f, [Map<String, dynamic>? values]) {
    final p = _parentOf(f);
    return p == null ? null : (values ?? widget.values)[p.key];
  }

  /// The label of [f]'s parent field, for the "choose X first" hint.
  String? _parentLabel(TicketField f) => _parentOf(f)?.label;

  /// After [changedName] changes, drop any descendant answers that the new
  /// parent selection no longer allows. Loops so multi-level chains settle.
  void _pruneCascade(Map<String, dynamic> next, String changedName) {
    var changed = {changedName};
    for (var depth = 0; depth < 5 && changed.isNotEmpty; depth++) {
      final touched = <String>{};
      for (final f in widget.fields) {
        final parent = _parentOf(f);
        if (parent == null || !changed.contains(parent.key)) continue;
        final current = next[f.key];
        if (current == null) continue;
        final allowed = f.choicesFor(next[parent.key]);
        if (current is List) {
          final kept = current
              .map((e) => e.toString())
              .where(allowed.containsKey)
              .toList();
          if (kept.length != current.length) {
            if (kept.isEmpty) {
              next.remove(f.key);
            } else {
              next[f.key] = kept;
            }
            touched.add(f.key);
          }
        } else if (!allowed.containsKey(current.toString())) {
          next.remove(f.key);
          touched.add(f.key);
        }
      }
      changed = touched;
    }
  }

  // --- Text / memo -----------------------------------------------------------

  Widget _textField(TicketField f, String? error) {
    return TextField(
      controller: _text[f.key],
      minLines: _isMultiline(f) ? 3 : 1,
      maxLines: _isMultiline(f) ? 8 : 1,
      onChanged: (v) => _set(f.key, v.trim()),
      decoration: InputDecoration(
        labelText: _label(f),
        hintText: f.hint,
        alignLabelWithHint: _isMultiline(f),
        errorText: error,
      ),
    );
  }

  // --- Boolean ---------------------------------------------------------------

  Widget _boolField(TicketField f, String? error) {
    final scheme = Theme.of(context).colorScheme;
    final on = widget.values[f.key] == true || widget.values[f.key] == '1';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: on,
          onChanged: (v) => _set(f.key, v),
          title: AppText.subText(context, _label(f), fw: 0),
          subtitle: f.hint == null ? null : AppText.paraText(context, f.hint!),
        ),
        if (error != null) AppText.paraText(context, error, color: scheme.error),
      ],
    );
  }

  // --- Choices ---------------------------------------------------------------

  Widget _choiceField(TicketField f, String? error) {
    // Cascading child: only the options its parent's selection allows.
    final choices = f.parentField == null
        ? (f.choices ?? const {})
        : f.choicesFor(_parentValue(f));
    if (f.multiselect) return _multiChoiceField(f, choices, error);

    final scheme = Theme.of(context).colorScheme;
    final selectedKey = widget.values[f.key]?.toString();
    final selectedLabel = selectedKey == null ? null : choices[selectedKey];
    // Waiting on the parent — show why it's not selectable yet.
    final blockedBy = f.parentField != null && choices.isEmpty
        ? (_parentLabel(f) ?? 'the previous field')
        : null;
    if (blockedBy != null) {
      return _FieldShell(
        label: _label(f),
        error: error,
        child: InputDecorator(
          decoration: InputDecoration(
            errorText: error,
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          child: AppText.subText(
            context,
            'Select $blockedBy first',
            color: scheme.onSurfaceVariant,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return _FieldShell(
      label: _label(f),
      error: error,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final key = await pickChoice(
            context,
            title: f.label,
            choices: choices,
            selectedValue: selectedKey,
          );
          if (key != null) _set(f.key, key);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            hintText: f.hint ?? 'Select',
            errorText: error,
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          child: AppText.subText(
            context,
            selectedLabel ?? (f.hint ?? 'Select'),
            color: selectedLabel != null
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
            fw: selectedLabel != null ? 0 : null,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _multiChoiceField(
    TicketField f,
    Map<String, String> choices,
    String? error,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final selected = <String>{
      ...?(widget.values[f.key] as List?)?.map((e) => e.toString()),
    };
    return _FieldShell(
      label: _label(f),
      error: error,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final e in choices.entries)
            FilterChip(
              label: Text(e.value),
              selected: selected.contains(e.key),
              onSelected: (on) {
                final next = Set<String>.from(selected);
                if (on) {
                  next.add(e.key);
                } else {
                  next.remove(e.key);
                }
                _set(f.key, next.toList());
              },
            ),
          if (error != null)
            AppText.paraText(context, error, color: scheme.error),
        ],
      ),
    );
  }

  /// A field's label with a trailing asterisk when required.
  String _label(TicketField f) => f.required ? '${f.label} *' : f.label;
}

/// A label above an arbitrary input child, for field kinds that aren't a bare
/// [TextField] (which draws its own label).
class _FieldShell extends StatelessWidget {
  const _FieldShell({required this.label, required this.child, this.error});
  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText.paraText(
          context,
          label,
          fw: 0,
          color: error != null ? scheme.error : scheme.onSurfaceVariant,
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
