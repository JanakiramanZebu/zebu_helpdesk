import 'package:flutter/material.dart';

import '../core/theme/app_text.dart';
import '../models/meta.dart';
import 'app_dialog.dart';
import 'app_sheet.dart';

/// The outcome of a [showReassignDialog] — the chosen assignee plus the
/// optional assignment reason and the "maintain referral access" flag, mirroring
/// osTicket's web reassign form. Returned only when the user taps **Assign**;
/// dismissing the dialog yields `null`.
class ReassignResult {
  const ReassignResult({
    required this.assigneeId,
    this.comments,
    this.maintainReferral = false,
  });

  final int assigneeId;

  /// Free-text "Optional reason for the assignment". Null/empty when blank.
  final String? comments;

  /// Whether to keep the current assignee(s) with referral access after the
  /// reassignment (osTicket's `refer` flag).
  final bool maintainReferral;
}

/// osTicket-style **Reassign** dialog: an info banner naming the current
/// assignee, an assignee picker, an optional "maintain referral access"
/// checkbox, and an optional free-text reason. Used by both the ticket and
/// task detail screens so the two flows stay identical.
///
/// [assignees] is the meta pick-list (e.g. `MetaKind.agents` / `MetaKind.teams`).
/// [currentAssignee] drives the banner; pass null to hide it (e.g. first
/// assignment). [showReferral] hides the referral checkbox for flows where it
/// does not apply (team assignment).
Future<ReassignResult?> showReassignDialog(
  BuildContext context, {
  required List<MetaItem> assignees,
  String title = 'Reassign',
  String assigneeLabel = 'Assignee',
  String? currentAssignee,
  int? selectedId,
  bool showReferral = true,
}) {
  return showDialog<ReassignResult>(
    context: context,
    builder: (_) => _ReassignDialog(
      assignees: assignees,
      title: title,
      assigneeLabel: assigneeLabel,
      currentAssignee: currentAssignee,
      selectedId: selectedId,
      showReferral: showReferral,
    ),
  );
}

class _ReassignDialog extends StatefulWidget {
  const _ReassignDialog({
    required this.assignees,
    required this.title,
    required this.assigneeLabel,
    required this.currentAssignee,
    required this.selectedId,
    required this.showReferral,
  });

  final List<MetaItem> assignees;
  final String title;
  final String assigneeLabel;
  final String? currentAssignee;
  final int? selectedId;
  final bool showReferral;

  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  final _reasonCtrl = TextEditingController();
  int? _assigneeId;
  bool _maintainReferral = false;

  @override
  void initState() {
    super.initState();
    _assigneeId = widget.selectedId;
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  MetaItem? get _selected {
    final id = _assigneeId;
    if (id == null) return null;
    for (final item in widget.assignees) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> _pickAssignee() async {
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => _AssigneePickerDialog(
        title: widget.assigneeLabel,
        items: widget.assignees,
        selectedId: _assigneeId,
      ),
    );
    if (chosen != null) setState(() => _assigneeId = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selected;

    return AppDialog(
      title: widget.title,
      actionLabel: 'Assign',
      actionEnabled: _assigneeId != null,
      onAction: () {
        final reason = _reasonCtrl.text.trim();
        Navigator.pop(
          context,
          ReassignResult(
            assigneeId: _assigneeId!,
            comments: reason.isEmpty ? null : reason,
            maintainReferral: _maintainReferral,
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.currentAssignee != null &&
              widget.currentAssignee!.isNotEmpty) ...[
            _CurrentAssigneeBanner(name: widget.currentAssignee!),
            const SizedBox(height: 20),
          ],
          AppText.subText(context, widget.assigneeLabel, fw: 2),
          const SizedBox(height: 8),
          _SelectorField(
            label: selected?.name ?? 'Select assignee',
            placeholder: selected == null,
            onTap: _pickAssignee,
          ),
          if (widget.showReferral) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () =>
                  setState(() => _maintainReferral = !_maintainReferral),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _maintainReferral,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) =>
                            setState(() => _maintainReferral = v ?? false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AppText.subText(
                        context,
                        'Maintain referral access to current assignee',
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          AppText.subText(context, 'Reason', fw: 2),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonCtrl,
            minLines: 3,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            style: AppText.style(context, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Optional reason for the assignment',
              hintStyle: AppText.style(
                context,
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ),
              filled: true,
              fillColor: scheme.onSurface.withValues(alpha: 0.04),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: scheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: scheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: scheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tinted "Currently assigned to `name`" info banner at the top of the
/// dialog, echoing the blue notice on the web form.
class _CurrentAssigneeBanner extends StatelessWidget {
  const _CurrentAssigneeBanner({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: AppText.style(
                  context,
                  fontSize: 14,
                  color: scheme.onSurface,
                ),
                children: [
                  const TextSpan(text: 'Currently assigned to '),
                  TextSpan(
                    text: name,
                    style: AppText.style(
                      context,
                      fontSize: 14,
                      fw: 1,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A dropdown-styled tappable field showing the current selection; opens the
/// assignee picker on tap.
class _SelectorField extends StatelessWidget {
  const _SelectorField({
    required this.label,
    required this.placeholder,
    required this.onTap,
  });

  final String label;
  final bool placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: AppText.subText(
                context,
                label,
                color: placeholder ? scheme.onSurfaceVariant : scheme.onSurface,
                fw: placeholder ? 3 : 2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Searchable single-select picker for the assignee list. Mirrors the meta
/// picker used elsewhere in the detail screens.
class _AssigneePickerDialog extends StatefulWidget {
  const _AssigneePickerDialog({
    required this.title,
    required this.items,
    this.selectedId,
  });

  final String title;
  final List<MetaItem> items;
  final int? selectedId;

  @override
  State<_AssigneePickerDialog> createState() => _AssigneePickerDialogState();
}

class _AssigneePickerDialogState extends State<_AssigneePickerDialog> {
  final _searchCtrl = TextEditingController();
  late List<MetaItem> _filtered = widget.items;

  bool get _searchable => widget.items.length > 8;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_updateFilter);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_updateFilter);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _updateFilter() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = widget.items
          .where((item) => item.name.toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      title: widget.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_searchable) ...[
            SheetSearchField(controller: _searchCtrl, hintText: 'Search'),
            const SizedBox(height: 12),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: _filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: AppText.subText(
                      context,
                      'No results found',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final item in _filtered)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(context, item.id),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: AppText.subText(
                                context,
                                item.name,
                                color: item.id == widget.selectedId
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
                                fw: item.id == widget.selectedId ? 2 : 3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
