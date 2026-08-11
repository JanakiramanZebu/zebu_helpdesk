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
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

const _kFlatRadius = 8.0;

/// Open the new-task form as a centered modal dialog. Mirrors
/// `showCreateTicketDialog` — called by the sidebar "Create ▾" split's
/// "New task" entry on web. Blocks outside-click dismiss so half-filled
/// form data doesn't disappear on a stray click.
Future<void> showCreateTaskDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(40),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
        child: CreateTaskScreenWeb(
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
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

  Future<void> _submit() async {
    if (_department == null) {
      setState(() => _error = 'Pick a department first');
      return;
    }
    if (_title.text.trim().isEmpty || _description.text.trim().isEmpty) {
      setState(() => _error = 'Title and description are required');
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

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
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

  /// Fetches a meta list and opens the app-styled dropdown under the field.
  Future<void> _pickMeta(
    BuildContext anchorContext,
    String kind,
    ValueChanged<MetaItem> onPicked,
  ) async {
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(kind);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
      return;
    }
    if (!mounted || !anchorContext.mounted) return;
    final chosen = await showAppDropdown<int>(
      anchorContext,
      entries: [
        for (final m in items) AppDropdownItem<int>(value: m.id, label: m.name),
      ],
    );
    if (chosen == null) return;
    onPicked(items.firstWhere((m) => m.id == chosen));
  }

  Future<void> _pickParent() async {
    final task = await showDialog<Task>(
      context: context,
      builder: (_) => const _TaskPickerDialog(),
    );
    if (task != null) setState(() => _parent = task);
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border.all(color: t.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(ZebuRadius.rMd),
      ),
      child: AbsorbPointer(
        absorbing: _saving,
        child: Column(
          children: [
            _HeaderBar(onClose: _close),
            if (_saving) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _buildBody(t)),
            _FooterBar(saving: _saving, onCancel: _close, onSubmit: _submit),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ZebuTheme t) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s6,
        ZebuSpacing.s4,
        ZebuSpacing.s6,
        ZebuSpacing.s5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: ZebuSpacing.s4),
          ],

          // --- TASK DETAILS ----------------------------------------------
          _SectionTitle('Task details'),
          const SizedBox(height: ZebuSpacing.s3),
          _LabeledField(
            label: 'Title',
            required: true,
            error: _fieldErrors['title'],
            child: _TextInput(
              controller: _title,
              hint: 'Short summary of the task',
              hasError: _fieldErrors['title'] != null,
            ),
          ),
          const SizedBox(height: ZebuSpacing.s4),
          _LabeledField(
            label: 'Description',
            required: true,
            error: _fieldErrors['description'],
            child: _TextInput(
              controller: _description,
              hint: 'Describe the task…',
              minLines: 5,
              maxLines: 12,
              hasError: _fieldErrors['description'] != null,
            ),
          ),
          const SizedBox(height: ZebuSpacing.s4),
          _AttachmentsBlock(
            files: _files,
            onAdd: _pickFiles,
            onRemove: (f) => setState(() => _files.remove(f)),
          ),

          const SizedBox(height: ZebuSpacing.s5),

          // --- OPTIONS ---------------------------------------------------
          _SectionTitle('Options'),
          const SizedBox(height: ZebuSpacing.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _LabeledField(
                  label: 'Department',
                  required: true,
                  error: _fieldErrors['dept_id'],
                  child: Builder(
                    builder: (anchorContext) => _SelectField(
                      icon: Icons.apartment_outlined,
                      value: _department?.name,
                      placeholder: 'Required',
                      hasError: _fieldErrors['dept_id'] != null,
                      onTap: () => _pickMeta(
                        anchorContext,
                        MetaKind.departments,
                        (m) => setState(() => _department = m),
                      ),
                      anchorContext: anchorContext,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: ZebuSpacing.s3),
              Expanded(
                child: _LabeledField(
                  label: 'Priority',
                  child: Builder(
                    builder: (anchorContext) => _SelectField(
                      icon: Icons.flag_outlined,
                      value: _priority?.name,
                      placeholder: 'Not set',
                      onTap: () => _pickMeta(
                        anchorContext,
                        MetaKind.taskPriorities,
                        (m) => setState(() => _priority = m),
                      ),
                      onClear: _priority == null
                          ? null
                          : () => setState(() => _priority = null),
                      anchorContext: anchorContext,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZebuSpacing.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _LabeledField(
                  label: 'Due date',
                  child: _SelectField(
                    icon: Icons.event_outlined,
                    value: _due == null ? null : Fmt.dateTime(_due),
                    placeholder: 'Not set',
                    onTap: _pickDue,
                    onClear: _due == null
                        ? null
                        : () => setState(() => _due = null),
                  ),
                ),
              ),
              const SizedBox(width: ZebuSpacing.s3),
              Expanded(
                child: _LabeledField(
                  label: 'Parent task',
                  child: _SelectField(
                    icon: Icons.account_tree_outlined,
                    value: _parent == null
                        ? null
                        : '#${_parent!.number} · ${_parent!.title}',
                    placeholder: 'Not set',
                    onTap: _pickParent,
                    onClear: _parent == null
                        ? null
                        : () => setState(() => _parent = null),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — X close + title, with a bottom border.
// ---------------------------------------------------------------------------

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s5,
        vertical: ZebuSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: Row(
        children: [
          Text('New task', style: ZebuTextStyles.hero(context)),
          const Spacer(),
          _IconBtn(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            destructive: true,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer — Cancel + Create task, right-aligned, top border.
// ---------------------------------------------------------------------------

class _FooterBar extends StatelessWidget {
  const _FooterBar({
    required this.saving,
    required this.onCancel,
    required this.onSubmit,
  });

  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s5,
        vertical: ZebuSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(top: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _SecondaryButton(label: 'Cancel', onTap: onCancel),
          const SizedBox(width: ZebuSpacing.s2),
          _PrimaryButton(
            label: saving ? 'Creating…' : 'Create task',
            onTap: saving ? null : onSubmit,
          ),
        ],
      ),
    );
  }
}

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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label.toUpperCase(), style: ZebuTextStyles.eyebrow(context));
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.required = false,
    this.error,
  });

  final String label;
  final Widget child;
  final bool required;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: ZebuTextStyles.small(
                context,
              ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w600),
            ),
            if (required) ...[
              const SizedBox(width: 4),
              Text(
                '*',
                style: TextStyle(
                  color: t.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: ZebuTextStyles.small(context).copyWith(color: t.danger),
          ),
        ],
      ],
    );
  }
}

class _SelectField extends StatefulWidget {
  const _SelectField({
    required this.onTap,
    this.icon,
    this.value,
    this.placeholder,
    this.onClear,
    this.anchorContext,
    this.hasError = false,
  });

  final VoidCallback onTap;
  final IconData? icon;
  final String? value;
  final String? placeholder;
  final VoidCallback? onClear;
  final BuildContext? anchorContext;
  final bool hasError;

  @override
  State<_SelectField> createState() => _SelectFieldState();
}

class _SelectFieldState extends State<_SelectField> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final hasValue = widget.value != null && widget.value!.isNotEmpty;
    final borderColor = widget.hasError
        ? t.danger
        : (_hover ? t.accent : t.borderSubtle);
    final textColor = hasValue ? t.textPrimary : t.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s3,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: t.bgElevated,
            border: Border.all(color: borderColor, width: 1),
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 16, color: t.textSecondary),
                const SizedBox(width: ZebuSpacing.s2),
              ],
              Expanded(
                child: Text(
                  hasValue ? widget.value! : (widget.placeholder ?? 'Select…'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZebuTextStyles.body(context).copyWith(
                    color: textColor,
                    fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.onClear != null && hasValue) ...[
                _MiniIcon(icon: Icons.close, onTap: widget.onClear!),
                const SizedBox(width: 2),
              ],
              Icon(Icons.keyboard_arrow_down, size: 18, color: t.textSecondary),
            ],
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

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.controller,
    required this.hint,
    this.minLines,
    this.maxLines = 1,
    this.hasError = false,
  });

  final TextEditingController controller;
  final String hint;
  final int? minLines;
  final int maxLines;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kFlatRadius),
      borderSide: BorderSide(
        color: hasError ? t.danger : t.borderSubtle,
        width: 1,
      ),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kFlatRadius),
      borderSide: BorderSide(color: hasError ? t.danger : t.accent, width: 1.4),
    );
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      style: ZebuTextStyles.body(context),
      decoration: InputDecoration(
        filled: true,
        fillColor: t.bgElevated,
        hoverColor: Colors.transparent,
        border: border,
        enabledBorder: border,
        focusedBorder: focusedBorder,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ZebuSpacing.s3,
          vertical: 12,
        ),
        hintText: hint,
        hintStyle: ZebuTextStyles.body(
          context,
        ).copyWith(color: t.textSecondary),
      ),
    );
  }
}

class _AttachmentsBlock extends StatelessWidget {
  const _AttachmentsBlock({
    required this.files,
    required this.onAdd,
    required this.onRemove,
  });

  final List<PlatformFile> files;
  final VoidCallback onAdd;
  final ValueChanged<PlatformFile> onRemove;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Attachments',
              style: ZebuTextStyles.small(
                context,
              ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            _AddFilesButton(onTap: onAdd),
          ],
        ),
        const SizedBox(height: ZebuSpacing.s2),
        if (files.isEmpty)
          Text('No files added', style: ZebuTextStyles.small(context))
        else
          Wrap(
            spacing: ZebuSpacing.s2,
            runSpacing: ZebuSpacing.s2,
            children: [
              for (final f in files)
                _Chip(
                  icon: Icons.insert_drive_file_outlined,
                  label: '${f.name}  ·  ${Fmt.fileSize(f.size)}',
                  onDelete: () => onRemove(f),
                ),
            ],
          ),
      ],
    );
  }
}

class _AddFilesButton extends StatefulWidget {
  const _AddFilesButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_AddFilesButton> createState() => _AddFilesButtonState();
}

class _AddFilesButtonState extends State<_AddFilesButton> {
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.attach_file,
              size: 14,
              color: _hover ? t.accentHover : t.accent,
            ),
            const SizedBox(width: 4),
            Text(
              'Add files',
              style: TextStyle(
                color: _hover ? t.accentHover : t.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onDelete, this.icon});
  final String label;
  final VoidCallback onDelete;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(ZebuSpacing.s2, 4, 4, 4),
      decoration: BoxDecoration(
        color: t.bgTertiary,
        border: Border.all(color: t.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(_kFlatRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: t.textSecondary),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ZebuTextStyles.small(
                context,
              ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 4),
          _MiniIcon(icon: Icons.close, onTap: onDelete),
        ],
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

class _TaskPickerDialog extends ConsumerStatefulWidget {
  const _TaskPickerDialog();

  @override
  ConsumerState<_TaskPickerDialog> createState() => _TaskPickerDialogState();
}

class _TaskPickerDialogState extends ConsumerState<_TaskPickerDialog> {
  final _ctrl = TextEditingController();
  List<Task> _results = const [];
  bool _loading = false;
  String? _error;
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

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(tasksRepositoryProvider)
          .list(TaskQuery(view: 'all', q: q.isEmpty ? null : q, limit: 25));
      if (!mounted) return;
      setState(() {
        _results = page.items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: t.bgElevated,
            border: Border.all(color: t.borderSubtle, width: 1),
            borderRadius: BorderRadius.circular(ZebuRadius.rMd),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ZebuSpacing.s5,
                  ZebuSpacing.s4,
                  ZebuSpacing.s5,
                  ZebuSpacing.s3,
                ),
                child: Row(
                  children: [
                    Text(
                      'Select parent task',
                      style: ZebuTextStyles.pageTitle(context),
                    ),
                    const Spacer(),
                    _IconBtn(
                      icon: Icons.close_rounded,
                      tooltip: 'Close',
                      destructive: true,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s5),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: _onChanged,
                  style: ZebuTextStyles.body(context),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: t.bgElevated,
                    hoverColor: Colors.transparent,
                    isDense: true,
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: t.textSecondary,
                    ),
                    hintText: 'Search task by number or title',
                    hintStyle: ZebuTextStyles.body(
                      context,
                    ).copyWith(color: t.textSecondary),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(_kFlatRadius),
                      borderSide: BorderSide(color: t.borderSubtle, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(_kFlatRadius),
                      borderSide: BorderSide(color: t.borderSubtle, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(_kFlatRadius),
                      borderSide: BorderSide(color: t.accent, width: 1.4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: ZebuSpacing.s2),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: ZebuTextStyles.small(context),
                        ),
                      )
                    : _results.isEmpty
                    ? Center(
                        child: Text(
                          'No tasks found',
                          style: ZebuTextStyles.small(context),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          vertical: ZebuSpacing.s2,
                        ),
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final task = _results[i];
                          return _TaskPickRow(
                            task: task,
                            onTap: () => Navigator.of(context).pop(task),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskPickRow extends StatefulWidget {
  const _TaskPickRow({required this.task, required this.onTap});
  final Task task;
  final VoidCallback onTap;

  @override
  State<_TaskPickRow> createState() => _TaskPickRowState();
}

class _TaskPickRowState extends State<_TaskPickRow> {
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
          color: _hover ? t.bgHover : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s5,
            vertical: ZebuSpacing.s3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.task.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZebuTextStyles.body(
                  context,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                '#${widget.task.number} · ${widget.task.statusName}',
                style: ZebuTextStyles.small(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
