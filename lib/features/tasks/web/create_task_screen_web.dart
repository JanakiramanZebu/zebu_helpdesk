import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format.dart';
import '../../../data/tasks_repository.dart';
import '../../../models/meta.dart';
import '../../../models/task.dart';
import '../../../providers.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/web/attachment_list.dart';
import '../../../widgets/web/form_fields.dart';
import '../../../widgets/web/property_menu.dart';
import '../../../widgets/web/property_rows.dart';
import '../../../widgets/web/zebu_dialog.dart';
import '../../../widgets/web/zebu_date_picker.dart';
import '../../../res/zebu_status_style.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

const _kFlatRadius = 8.0;

/// Open the new-task form as a centered modal dialog. Mirrors
/// `showCreateTicketDialog` — called by the sidebar "Create ▾" split's
/// "New task" entry on web. Blocks outside-click dismiss so half-filled
/// form data doesn't disappear on a stray click.
Future<void> showCreateTaskDialog(BuildContext context) {
  return showZebuDialog<void>(
    context,
    barrierLabel: 'New task',
    // Outside-click stays disabled: this form holds enough half-typed work
    // that a stray click on the page behind it must not discard it. `Esc`
    // and the close button both still work.
    dismissible: false,
    child: Builder(
      builder: (ctx) =>
          CreateTaskScreenWeb(onClose: () => Navigator.of(ctx).pop()),
    ),
  );
}

/// Web-only new-task form, styled to match [CreateTicketScreenWeb]:
///   * X-only header, hero title, no back navigation
///   * Scrollable body with sectioned labeled form fields
///   * Sticky footer with Cancel / Create task
///   * Every meta-list field opens an [AppDropdown] anchored under the field
///   * Parent-task uses an in-place Dialog search overlay (not a bottom sheet)
///
/// `POST /tasks` — fields mirror the mobile `CreateTaskScreen`
/// (title, description, department — required, priority, due date, parent).
class CreateTaskScreenWeb extends ConsumerStatefulWidget {
  const CreateTaskScreenWeb({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  ConsumerState<CreateTaskScreenWeb> createState() =>
      _CreateTaskScreenWebState();
}

/// Menu value standing for "clear this field". Meta ids are always positive,
/// so a negative sentinel can never collide with a real one.
const int _kNoValue = -1;

class _CreateTaskScreenWebState extends ConsumerState<CreateTaskScreenWeb> {
  final _title = TextEditingController();
  final _description = TextEditingController();

  MetaItem? _department;
  MetaItem? _priority;
  DateTime? _due;
  Task? _parent;
  final List<PlatformFile> _files = [];

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _toast(String msg, {ToastType type = ToastType.info}) =>
      AppToast.show(context, msg, type: type);

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  /// Drops one field's error as soon as it is being corrected.
  void _clearError(String field) {
    if (!_fieldErrors.containsKey(field)) return;
    setState(() => _fieldErrors = {..._fieldErrors}..remove(field));
  }

  Future<void> _submit() async {
    // Per field, not one banner at the top. A banner names the problem a
    // scroll away from the control that has it, and with three possible
    // causes it cannot say which — so it reported the first failure and hid
    // the rest, one submit at a time.
    final errors = <String, String>{
      if (_title.text.trim().isEmpty) 'title': 'A task needs a title',
      if (_description.text.trim().isEmpty)
        'description': 'Say what needs doing',
      if (_department == null) 'dept_id': 'Pick a department',
    };
    if (errors.isNotEmpty) {
      setState(() {
        _fieldErrors = errors;
        _error = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final task = await ref
          .read(tasksRepositoryProvider)
          .create(
            {
              'dept_id': _department!.id,
              'title': _title.text.trim(),
              'description': _description.text.trim(),
              if (_priority != null) 'priority_id': _priority!.id,
              if (_due != null) 'duedate': Fmt.apiDateTime(_due!),
              if (_parent != null) 'parent_id': _parent!.id,
            },
            files: [
              for (final f in _files)
                if (f.bytes != null)
                  MultipartFile.fromBytes(f.bytes!, filename: f.name),
            ],
          );
      if (!mounted) return;
      _toast('Task #${task.number} created', type: ToastType.success);
      _close();
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
      withData: true,
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

  /// One popover for the whole field — grid, time and Clear on a single
  /// surface, anchored under the value like every other property row. Same
  /// call as the new-ticket dialog's Due date, deliberately: the two forms
  /// should not have different calendars.
  ///
  /// This used to open a two-entry Change / Clear menu first, and then two
  /// stacked Material modals: `showDatePicker` followed by `showTimePicker`.
  /// The intermediate menu existed only because `showDatePicker` has no way to
  /// say "no date"; [showZebuDatePicker] carries Clear in its own footer.
  Future<void> _pickDue(BuildContext anchorContext) async {
    final now = DateTime.now();
    final res = await showZebuDatePicker(
      anchorContext,
      initial: _due,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      // Nothing to clear while the row is empty, and an inert link reads as
      // broken. The row shows "None" in that state anyway.
      clearLabel: _due == null ? null : 'Clear',
    );
    if (res == null || !mounted) return;
    setState(() => _due = res.cleared ? null : res.date);
  }

  /// Fetches a meta list and opens a menu under the tapped control.
  ///
  /// [clearable] adds the muted default entry that empties the field — the
  /// property rows have no X, so clearing lives in the menu. Department is not
  /// clearable: the API rejects a task without one, and offering "None" on a
  /// field the form will refuse to submit is a promise it cannot keep.
  ///
  /// [dotFor] paints an 8 px colour chip before each entry, for Priority.
  Future<void> _pickMeta(
    BuildContext anchorContext,
    String kind,
    ValueChanged<MetaItem?> onPicked, {
    MetaItem? current,
    bool clearable = true,
    String clearLabel = 'None',
    Color Function(String name)? dotFor,

    /// Set for a full-width select, so the menu takes the control's width
    /// rather than the narrow default the property grid wants.
    bool matchAnchorWidth = false,
  }) async {
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(kind);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
      return;
    }
    if (!mounted || !anchorContext.mounted) return;
    final chosen = await showZebuPropertyMenu<int>(
      anchorContext,
      matchAnchorWidth: matchAnchorWidth,
      items: [
        if (clearable)
          ZebuPropertyMenuItem<int>(
            value: _kNoValue,
            label: clearLabel,
            muted: true,
            selected: current == null,
          ),
        for (final m in items)
          ZebuPropertyMenuItem<int>(
            value: m.id,
            label: m.name,
            dotColor: dotFor?.call(m.name),
            selected: m.id == current?.id,
          ),
      ],
    );
    if (chosen == null) return;
    onPicked(
      chosen == _kNoValue ? null : items.firstWhere((m) => m.id == chosen),
    );
  }

  /// Searchable dropdown over open tasks, the same control the new-ticket
  /// dialog uses for its requester.
  ///
  /// Was a centred dialog. A modal on top of a modal to choose one value is
  /// heavy, and it made Parent task the only field on this form that did not
  /// open under itself.
  Future<void> _pickParent(BuildContext anchorContext) async {
    final found = <Task>[];
    final id = await showZebuPropertyMenu<int>(
      anchorContext,
      matchAnchorWidth: true,
      maxHeight: 260,
      searchHint: 'Search tasks by number or title',
      // Floor for the half-width column this row sits in; `matchAnchorWidth`
      // takes the row itself when that is wider.
      minWidth: 260,
      search: (q) async {
        final page = await ref
            .read(tasksRepositoryProvider)
            // `view: 'all'` and a *null* empty query, both as the dialog this
            // replaced had them. `'open'` hid every completed task, and
            // sending `q: ''` filters on an empty string server-side instead
            // of meaning "no filter" — between them the list came back with
            // three rows and nothing to scroll.
            .list(TaskQuery(view: 'all', q: q.isEmpty ? null : q, limit: 25));
        found
          ..clear()
          ..addAll(page.items);
        return [
          ZebuPropertyMenuItem<int>(
            value: _kNoValue,
            label: 'None',
            muted: true,
            selected: _parent == null,
          ),
          for (final t in found)
            ZebuPropertyMenuItem<int>(
              value: t.id,
              label: t.title,
              subtitle: t.departmentName == null
                  ? '#${t.number}'
                  : '#${t.number} · ${t.departmentName}',
              selected: t.id == _parent?.id,
            ),
        ];
      },
    );
    if (id == null || !mounted) return;
    if (id == _kNoValue) {
      setState(() => _parent = null);
      return;
    }
    // `orElse` returning `_parent!` would throw when nothing is set and the
    // row somehow fell out of the last page — keep what we have instead.
    final picked = found.where((t) => t.id == id).firstOrNull;
    if (picked != null) setState(() => _parent = picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    // Same shell as the new-ticket dialog, rather than a hand-rolled frame
    // with its own header and footer bars. Those had already drifted from it
    // — and the footer carried a Cancel button the ticket dialog dropped,
    // since the header's X already dismisses and a modal needs one way out,
    // not two.
    return ZebuDialogShell(
      title: 'New task',
      maxWidth: 640,
      onDismiss: _close,
      onSubmit: _saving ? null : _submit,
      // The action is pinned in a footer, not placed in the body as the short
      // dialogs do: this form scrolls, and a submit button that scrolls out of
      // view is one an agent has to hunt back down for.
      actions: [
        ZebuDialogPrimaryBtn(
          label: 'Create task',
          busyLabel: 'Creating…',
          busy: _saving,
          onTap: _submit,
        ),
      ],
      body: AbsorbPointer(absorbing: _saving, child: _buildBody(t)),
    );
  }

  /// No scroll view and no padding of its own — [ZebuDialogShell] supplies
  /// both, and nesting a second scrollable inside its one made the inner one
  /// dead weight.
  Widget _buildBody(ZebuTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) ...[
          _ErrorBanner(message: _error!),
          const SizedBox(height: ZebuSpacing.s4),
        ],

        // --- TASK DETAILS ----------------------------------------------
        // ZebuSectionTitle('Task details'),
        // const SizedBox(height: ZebuSpacing.s3),
        // Title and Department share the top row 50/50, the way Requester and
        // Collaborators do in the new-ticket dialog. They are the two fields
        // the API refuses a task without, so they belong at the top together
        // rather than with an Attachments block between them.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ZebuLabeledField(
                label: 'Title',
                error: _fieldErrors['title'],
                child: ZebuFormInput(
                  controller: _title,
                  onChanged: (_) => _clearError('title'),
                  hint: 'e.g. Reconcile August partner ledger',
                  hasError: _fieldErrors['title'] != null,
                ),
              ),
            ),
            const SizedBox(width: ZebuSpacing.s3),
            Expanded(
              child: ZebuLabeledField(
                label: 'Department',
                error: _fieldErrors['dept_id'],
                child: Builder(
                  builder: (anchorContext) => ZebuSelectField(
                    icon: Icons.apartment_outlined,
                    value: _department?.name,
                    placeholder: 'Choose a department',
                    hasError: _fieldErrors['dept_id'] != null,
                    onTap: () => _pickMeta(
                      anchorContext,
                      MetaKind.departments,
                      (m) {
                        setState(() => _department = m);
                        _clearError('dept_id');
                      },
                      current: _department,
                      clearable: false,
                      // Full-width select, so the menu takes the control's
                      // width instead of the narrow default meant for the
                      // property grid's short values.
                      matchAnchorWidth: true,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ZebuSpacing.s4),
        ZebuLabeledField(
          label: 'Description',
          error: _fieldErrors['description'],
          child: ZebuFormInput(
            controller: _description,
            onChanged: (_) => _clearError('description'),
            hint: 'What needs doing, by when, and anything the doer will need…',
            minLines: 5,
            maxLines: 12,
            hasError: _fieldErrors['description'] != null,
          ),
        ),
        const SizedBox(height: ZebuSpacing.s4),
        ZebuAttachmentsField(
          files: [
            for (final f in _files)
              ZebuAttachmentSpec(name: f.name, size: Fmt.fileSize(f.size)),
          ],
          onAdd: _pickFiles,
          onRemove: (i) => setState(() => _files.removeAt(i)),
        ),

        const SizedBox(height: ZebuSpacing.s5),

        // --- PROPERTIES ------------------------------------------------
        // The same grid the new-ticket dialog uses: flat label -> value rows
        // instead of a grid of outlined selects, so the optional settings
        // stop carrying the same weight as Title and Description.
        ZebuPropertyGrid(
          rows: [
            ZebuPropertySpec(
              label: 'Priority',
              icon: Icons.priority_high_rounded,
              value: _priority?.name,
              placeholder: 'Normal (default)',
              dotColor: zebuPriorityStyle(_priority?.name, t).dot,
              onTap: (ctx) => _pickMeta(
                ctx,
                MetaKind.taskPriorities,
                (m) => setState(() => _priority = m),
                current: _priority,
                clearLabel: 'Normal (default)',
                dotFor: (n) => zebuPriorityStyle(n, t).dot,
              ),
            ),
            ZebuPropertySpec(
              label: 'Due date',
              icon: Icons.schedule_outlined,
              value: _due == null ? null : Fmt.dateTime(_due),
              onTap: _pickDue,
            ),
            ZebuPropertySpec(
              label: 'Parent task',
              icon: Icons.account_tree_outlined,
              value: _parent == null ? null : '#${_parent!.number}',
              // Its menu carries a search box and two-line rows, so it
              // anchors on the whole row rather than on `#4263`.
              anchorToRow: true,
              onTap: _pickParent,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header — X close + title, with a bottom border.
// ---------------------------------------------------------------------------

class _IconBtn extends StatefulWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.destructive = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool destructive;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final bg = _hover
        ? (widget.destructive ? t.dangerLight : t.bgHover)
        : t.bgElevated;
    final fg = _hover && widget.destructive ? t.danger : t.textPrimary;
    final child = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: t.borderSubtle, width: 1),
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Icon(widget.icon, size: 16, color: fg),
        ),
      ),
    );
    return widget.tooltip == null
        ? child
        : Tooltip(message: widget.tooltip!, child: child);
  }
}

class _SecondaryButton extends StatefulWidget {
  const _SecondaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  State<_SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<_SecondaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s4,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgElevated,
            border: Border.all(color: t.borderDefault, width: 1),
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Text(
            widget.label,
            style: ZebuTextStyles.small(
              context,
            ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onTap == null;
    final effective = disabled
        ? ZebuTheme.accentLight.withValues(alpha: 0.4)
        : ZebuTheme.accentLight;
    return MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s4,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: _hover && !disabled
                ? Color.lerp(effective, Colors.black, 0.08)
                : effective,
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniIcon extends StatefulWidget {
  const _MiniIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_MiniIcon> createState() => _MiniIconState();
}

class _MiniIconState extends State<_MiniIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? t.dangerLight : Colors.transparent,
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Icon(
            widget.icon,
            size: 12,
            color: _hover ? t.danger : t.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: ZebuSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: t.dangerLight,
        border: Border.all(color: t.danger, width: 1),
        borderRadius: BorderRadius.circular(_kFlatRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: t.danger),
          const SizedBox(width: ZebuSpacing.s2),
          Expanded(
            child: Text(
              message,
              style: ZebuTextStyles.small(context).copyWith(color: t.danger),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Parent-task picker — web-styled Dialog with a debounced search field and
// a results list (`GET /tasks?q=`). Replaces the mobile bottom sheet.
// ---------------------------------------------------------------------------
