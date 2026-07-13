import 'package:flutter/material.dart';

import '../../../core/theme/app_text.dart';
import '../../../models/ticket.dart';
import '../../../widgets/app_sheet.dart';
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
    final names = widget.fields.map((f) => f.name).toSet();
    for (final key in _text.keys.toList()) {
      if (!names.contains(key)) {
        _text.remove(key)!.dispose();
      }
    }
    // Create controllers for new text/memo fields, seeded from the value map.
    for (final f in widget.fields) {
      if (_isText(f) && !_text.containsKey(f.name)) {
        _text[f.name] = TextEditingController(
          text: (widget.values[f.name] ?? f.value ?? '').toString(),
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

  bool _isText(TicketField f) =>
      f.type == 'text' ||
      f.type == 'memo' ||
      f.type == 'thread' ||
      (f.type != 'choices' && f.type != 'bool');

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
    final error = widget.errors[f.name];
    if (f.type == 'bool') return _boolField(f, error);
    if (f.type == 'choices') return _choiceField(f, error);
    return _textField(f, error);
  }

  // --- Text / memo -----------------------------------------------------------

  Widget _textField(TicketField f, String? error) {
    return TextField(
      controller: _text[f.name],
      minLines: _isMultiline(f) ? 3 : 1,
      maxLines: _isMultiline(f) ? 8 : 1,
      onChanged: (v) => _set(f.name, v.trim()),
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
    final on = widget.values[f.name] == true || widget.values[f.name] == '1';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: on,
          onChanged: (v) => _set(f.name, v),
          title: AppText.subText(context, _label(f), fw: 1),
          subtitle: f.hint == null ? null : AppText.paraText(context, f.hint!),
        ),
        if (error != null) AppText.paraText(context, error, color: scheme.error),
      ],
    );
  }

  // --- Choices ---------------------------------------------------------------

  Widget _choiceField(TicketField f, String? error) {
    final choices = f.choices ?? const {};
    if (f.multiselect) return _multiChoiceField(f, choices, error);

    final scheme = Theme.of(context).colorScheme;
    final selectedKey = widget.values[f.name]?.toString();
    final selectedLabel = selectedKey == null ? null : choices[selectedKey];
    return _FieldShell(
      label: _label(f),
      error: error,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final key = await showAppSheet<String>(
            context: context,
            builder: (_) => AppSheet(
              title: f.label,
              scrollable: false,
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final e in choices.entries)
                    PickerOptionTile(
                      label: e.value,
                      selected: e.key == selectedKey,
                      onTap: () => Navigator.pop(context, e.key),
                    ),
                ],
              ),
            ),
          );
          if (key != null) _set(f.name, key);
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
            fw: selectedLabel != null ? 1 : null,
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
      ...?(widget.values[f.name] as List?)?.map((e) => e.toString()),
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
                _set(f.name, next.toList());
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
