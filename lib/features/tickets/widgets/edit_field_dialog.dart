import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../models/ticket.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_snack.dart';
import 'dynamic_fields_section.dart';

/// Edit a **single** ticket field, the way the web's ticket page does it: tap
/// the field on the Details tab, change that one answer, save.
///
/// [fields] is the whole form. It's needed for cascading custom lists: a child
/// list narrows its options by its parent's answer, so editing one alone would
/// leave the picker stuck on "Select the parent first". The dialog therefore
/// renders [field] together with its ancestors, and still posts only what
/// actually changed.
///
/// Returns `true` when something was saved.
Future<bool?> showEditFieldDialog(
  BuildContext context, {
  required int ticketId,
  required TicketField field,
  List<TicketField> fields = const [],
}) => showDialog<bool>(
  context: context,
  builder: (_) =>
      _EditFieldDialog(ticketId: ticketId, field: field, fields: fields),
);

class _EditFieldDialog extends ConsumerStatefulWidget {
  const _EditFieldDialog({
    required this.ticketId,
    required this.field,
    required this.fields,
  });

  final int ticketId;
  final TicketField field;
  final List<TicketField> fields;

  @override
  ConsumerState<_EditFieldDialog> createState() => _EditFieldDialogState();
}

class _EditFieldDialogState extends ConsumerState<_EditFieldDialog> {
  /// The edited field preceded by its cascade ancestors, parents first.
  late final List<TicketField> _chain = _buildChain();

  late Map<String, dynamic> _values = {
    for (final f in _chain)
      if (f.value != null) f.key: f.value,
  };
  late final Map<String, dynamic> _initial = Map.of(_values);

  Map<String, String> _errors = const {};
  bool _saving = false;

  /// Walk up `parent_field` from the tapped field. Bounded, so a form that
  /// somehow points a field at itself can't spin here.
  List<TicketField> _buildChain() {
    final chain = <TicketField>[widget.field];
    final seen = <String>{widget.field.key};
    var current = widget.field;
    for (var depth = 0; depth < 5; depth++) {
      final parentName = current.parentField;
      if (parentName == null || parentName.isEmpty) break;
      TicketField? parent;
      for (final f in widget.fields) {
        if (f.name == parentName || f.key == parentName) {
          parent = f;
          break;
        }
      }
      if (parent == null || !seen.add(parent.key)) break;
      chain.insert(0, parent);
      current = parent;
    }
    return chain;
  }

  /// Null and `''` are the same answer (unanswered), so an untouched blank
  /// field never enters the payload - `Ticket::updateField()` rejects a value
  /// that didn't change ("... is already assigned this value").
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

  Map<String, dynamic> _changed() => {
    for (final f in _chain)
      if (!_same(_values[f.key], _initial[f.key])) f.key: _values[f.key] ?? '',
  };

  bool get _dirty => _changed().isNotEmpty;

  Future<void> _save() async {
    final changed = _changed();
    if (changed.isEmpty) return;
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      await ref
          .read(ticketsRepositoryProvider)
          .editFields(widget.ticketId, changed);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors = _mapErrors(e);
      });
      if (_errors.isEmpty) AppSnack.error(context, e.detail);
    }
  }

  /// Land each validation message on the field it belongs to. A custom field's
  /// error can be keyed by its name **or** its numeric id, and a 422 that names
  /// neither still has to be visible - so anything unrecognised goes on the
  /// field the agent actually tapped.
  Map<String, String> _mapErrors(ApiException e) {
    if (e.fields.isEmpty) return const {};
    final byKey = <String, String>{};
    final orphans = <String>[];
    for (final entry in e.fields.entries) {
      TicketField? match;
      for (final f in _chain) {
        if (f.key == entry.key ||
            f.name == entry.key ||
            (f.id != null && '${f.id}' == entry.key)) {
          match = f;
          break;
        }
      }
      if (match == null) {
        orphans.add(entry.value);
      } else {
        byKey[match.key] = entry.value;
      }
    }
    if (orphans.isNotEmpty) {
      final key = widget.field.key;
      byKey[key] = [
        if (byKey[key] != null) byKey[key]!,
        ...orphans,
      ].join('\n');
    }
    return byKey;
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.field.label,
      actionLabel: 'Save',
      actionEnabled: _dirty,
      actionBusy: _saving,
      onAction: _save,
      child: DynamicFieldsSection(
        fields: _chain,
        values: _values,
        errors: _errors,
        onChanged: (v) => setState(() => _values = v),
      ),
    );
  }
}
