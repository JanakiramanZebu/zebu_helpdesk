import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format.dart';
import '../../../models/canned.dart';
import '../../../models/meta.dart';
import '../../../models/user.dart';
import '../../../providers.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

/// Ticket source options (the `source` param), mirroring the web dropdown.
const _sources = ['Phone', 'Email', 'Web', 'Other'];

const _kFlatRadius = 8.0;

/// Open the new-ticket form as a centered modal dialog. Called by the
/// sidebar's "+ New Ticket" button on web. Blocks outside-click dismiss so
/// half-filled form data doesn't disappear on a stray click.
Future<void> showCreateTicketDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(40),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
        child: CreateTicketScreenWeb(
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    ),
  );
}

/// Web-only new-ticket form, styled like the other web surfaces:
///   * X-only header, hero title, no back navigation
///   * Scrollable body with sectioned labeled form fields
///   * Sticky footer with Cancel / Create ticket
///   * Every meta-list field opens an [AppDropdown] anchored under the
///     field itself — no mobile bottom sheets on web
///   * Requester / collaborators / canned responses use in-place Dialog
///     search overlays (not bottom sheets) so they read as desktop popups
class CreateTicketScreenWeb extends ConsumerStatefulWidget {
  const CreateTicketScreenWeb({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  ConsumerState<CreateTicketScreenWeb> createState() =>
      _CreateTicketScreenWebState();
}

class _CreateTicketScreenWebState extends ConsumerState<CreateTicketScreenWeb> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _internalNote = TextEditingController();

  AppUser? _user;
  final List<AppUser> _collaborators = [];
  String _source = 'Phone';
  MetaItem? _topic;
  MetaItem? _department;
  MetaItem? _priority;
  MetaItem? _status;
  MetaItem? _agent;
  MetaItem? _team;
  DateTime? _due;
  CannedResponse? _canned;
  final List<PlatformFile> _files = [];

  bool _saving = false;
  Map<String, String> _fieldErrors = const {};
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    _internalNote.dispose();
    super.dispose();
  }

  void _toast(String msg, {ToastType type = ToastType.info}) =>
      AppToast.show(context, msg, type: type);

  /// Dismiss the form. Uses [widget.onClose] when provided (dialog mode);
  /// otherwise pops the router route (full-page mode).
  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      context.pop();
    }
  }

  Future<void> _submit() async {
    if (_user == null) {
      setState(() => _error = 'Pick a requester first');
      return;
    }
    if (_subject.text.trim().isEmpty || _message.text.trim().isEmpty) {
      setState(() => _error = 'Subject and message are required');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      final repo = ref.read(ticketsRepositoryProvider);
      final ticket = await repo.create(
        {
          'user_id': _user!.id,
          'subject': _subject.text.trim(),
          'message': _message.text.trim(),
          'source': _source,
          if (_topic != null) 'topic_id': _topic!.id,
          if (_department != null) 'dept_id': _department!.id,
          if (_priority != null) 'priority_id': _priority!.id,
          if (_due != null) 'duedate': Fmt.apiDateTime(_due!),
        },
        files: [
          for (final f in _files)
            if (f.bytes != null)
              MultipartFile.fromBytes(f.bytes!, filename: f.name),
        ],
      );

      if (_agent != null || _team != null) {
        try {
          await repo.assign(
            ticket.id,
            staffId: _agent?.id,
            teamId: _team?.id,
          );
        } catch (_) {}
      }
      if (_status != null) {
        try {
          await repo.setStatus(ticket.id, _status!.id);
        } catch (_) {}
      }
      for (final c in _collaborators) {
        try {
          await repo.addCollaborator(ticket.id, c.id);
        } catch (_) {}
      }
      if (_internalNote.text.trim().isNotEmpty) {
        try {
          await repo.note(ticket.id, body: _internalNote.text.trim());
        } catch (_) {}
      }

      if (!mounted) return;
      _toast('Ticket #${ticket.number} created', type: ToastType.success);
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

  // --- Dropdown pickers (anchored under the field) --------------------------

  Future<void> _pickSource(BuildContext anchorContext) async {
    final chosen = await showAppDropdown<String>(
      anchorContext,
      entries: [
        for (final s in _sources) AppDropdownItem<String>(value: s, label: s),
      ],
    );
    if (chosen != null) setState(() => _source = chosen);
  }

  /// Fetches a meta list and opens the app-styled dropdown under the field.
  /// Optional fields advertise "clear" via an inline X on the select itself,
  /// so the dropdown here is a plain value list.
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
        for (final m in items)
          AppDropdownItem<int>(value: m.id, label: m.name),
      ],
    );
    if (chosen == null) return;
    onPicked(items.firstWhere((m) => m.id == chosen));
  }

  // --- Dialog pickers (user search / canned response search) ----------------

  Future<void> _pickRequester() async {
    final user = await showDialog<AppUser>(
      context: context,
      builder: (_) => const _UserPickerDialog(title: 'Select requester'),
    );
    if (user != null) setState(() => _user = user);
  }

  Future<void> _pickCollaborator() async {
    final user = await showDialog<AppUser>(
      context: context,
      builder: (_) => const _UserPickerDialog(title: 'Add collaborator'),
    );
    if (user != null && !_collaborators.any((c) => c.id == user.id)) {
      setState(() => _collaborators.add(user));
    }
  }

  Future<void> _pickCanned() async {
    final c = await showDialog<CannedResponse>(
      context: context,
      builder: (_) => const _CannedPickerDialog(),
    );
    if (c == null) return;
    setState(() {
      _canned = c;
      final text = Fmt.stripHtml(c.body);
      final current = _message.text.trim();
      _message.text = current.isEmpty ? text : '$current\n\n$text';
    });
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
            _FooterBar(
              saving: _saving,
              onCancel: _close,
              onSubmit: _submit,
            ),
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

          // --- USER & COLLABORATORS --------------------------------------
          _SectionTitle('User & collaborators'),
          const SizedBox(height: ZebuSpacing.s3),
          _LabeledField(
            label: 'Requester',
            required: true,
            error: _fieldErrors['user_id'],
            child: Builder(
              builder: (anchorContext) => _SelectField(
                icon: Icons.person_outline,
                value: _user?.name,
                placeholder: 'Select a requester',
                onTap: () => _pickRequester(),
                anchorContext: anchorContext,
                hasError: _fieldErrors['user_id'] != null,
              ),
            ),
          ),
          const SizedBox(height: ZebuSpacing.s4),
          _LabeledField(
            label: 'Collaborators (Cc)',
            child: Builder(
              builder: (anchorContext) => _SelectField(
                icon: Icons.group_outlined,
                value: _collaborators.isEmpty
                    ? null
                    : '${_collaborators.length} added',
                placeholder: 'Add collaborators (optional)',
                trailingIcon: Icons.add,
                onTap: () => _pickCollaborator(),
                anchorContext: anchorContext,
              ),
            ),
          ),
          if (_collaborators.isNotEmpty) ...[
            const SizedBox(height: ZebuSpacing.s2),
            Wrap(
              spacing: ZebuSpacing.s2,
              runSpacing: ZebuSpacing.s2,
              children: [
                for (final c in _collaborators)
                  _Chip(
                    label: c.name,
                    onDelete: () =>
                        setState(() => _collaborators.remove(c)),
                  ),
              ],
            ),
          ],

          const SizedBox(height: ZebuSpacing.s5),

          // --- TICKET DETAILS --------------------------------------------
          _SectionTitle('Ticket details'),
          const SizedBox(height: ZebuSpacing.s3),
          _LabeledField(
            label: 'Subject',
            required: true,
            error: _fieldErrors['subject'],
            child: _TextInput(
              controller: _subject,
              hint: 'Short summary of the issue',
              hasError: _fieldErrors['subject'] != null,
            ),
          ),
          const SizedBox(height: ZebuSpacing.s4),
          _OutlinedAction(
            icon: Icons.bolt_outlined,
            label: _canned == null
                ? 'Insert canned response'
                : 'Canned: ${_canned!.title}',
            onTap: _pickCanned,
          ),
          const SizedBox(height: ZebuSpacing.s4),
          _LabeledField(
            label: 'Message',
            required: true,
            error: _fieldErrors['message'],
            child: _TextInput(
              controller: _message,
              hint: 'Describe the ticket…',
              minLines: 5,
              maxLines: 12,
              hasError: _fieldErrors['message'] != null,
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
                  label: 'Source',
                  child: Builder(
                    builder: (anchorContext) => _SelectField(
                      icon: Icons.podcasts_outlined,
                      value: _source,
                      placeholder: 'Source',
                      onTap: () => _pickSource(anchorContext),
                      anchorContext: anchorContext,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: ZebuSpacing.s3),
              Expanded(
                child: _LabeledField(
                  label: 'Help topic',
                  child: Builder(
                    builder: (anchorContext) => _SelectField(
                      icon: Icons.topic_outlined,
                      value: _topic?.name,
                      placeholder: 'Not set',
                      onTap: () => _pickMeta(
                        anchorContext,
                        MetaKind.topics,
                        (m) => setState(() => _topic = m),
                      ),
                      onClear: _topic == null
                          ? null
                          : () => setState(() => _topic = null),
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
                  label: 'Department',
                  child: Builder(
                    builder: (anchorContext) => _SelectField(
                      icon: Icons.apartment_outlined,
                      value: _department?.name,
                      placeholder: 'Not set',
                      onTap: () => _pickMeta(
                        anchorContext,
                        MetaKind.departments,
                        (m) => setState(() => _department = m),
                      ),
                      onClear: _department == null
                          ? null
                          : () => setState(() => _department = null),
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
                        MetaKind.priorities,
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
                  label: 'Status',
                  child: Builder(
                    builder: (anchorContext) => _SelectField(
                      icon: Icons.label_outline,
                      value: _status?.name,
                      placeholder: 'Not set',
                      onTap: () => _pickMeta(
                        anchorContext,
                        MetaKind.statuses,
                        (m) => setState(() => _status = m),
                      ),
                      onClear: _status == null
                          ? null
                          : () => setState(() => _status = null),
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
                  label: 'Assign to agent',
                  child: Builder(
                    builder: (anchorContext) => _SelectField(
                      icon: Icons.assignment_ind_outlined,
                      value: _agent?.name,
                      placeholder: 'Not set',
                      onTap: () => _pickMeta(
                        anchorContext,
                        MetaKind.agents,
                        (m) => setState(() => _agent = m),
                      ),
                      onClear: _agent == null
                          ? null
                          : () => setState(() => _agent = null),
                      anchorContext: anchorContext,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: ZebuSpacing.s3),
              Expanded(
                child: _LabeledField(
                  label: 'Assign to team',
                  child: Builder(
                    builder: (anchorContext) => _SelectField(
                      icon: Icons.groups_outlined,
                      value: _team?.name,
                      placeholder: 'Not set',
                      onTap: () => _pickMeta(
                        anchorContext,
                        MetaKind.teams,
                        (m) => setState(() => _team = m),
                      ),
                      onClear: _team == null
                          ? null
                          : () => setState(() => _team = null),
                      anchorContext: anchorContext,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: ZebuSpacing.s5),

          // --- INTERNAL NOTE ---------------------------------------------
          _SectionTitle('Internal note'),
          const SizedBox(height: ZebuSpacing.s3),
          _LabeledField(
            label: 'Note',
            child: _TextInput(
              controller: _internalNote,
              hint: 'Visible to staff only (optional)',
              minLines: 3,
              maxLines: 8,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — X close + title, with a bottom border. Actions moved to footer.
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
        border: Border(
          bottom: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          Text('New ticket', style: ZebuTextStyles.hero(context)),
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
// Footer — Cancel + Create ticket, right-aligned, top border.
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
        border: Border(
          top: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _SecondaryButton(label: 'Cancel', onTap: onCancel),
          const SizedBox(width: ZebuSpacing.s2),
          _PrimaryButton(
            label: saving ? 'Creating…' : 'Create ticket',
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
    final fg = _hover && widget.destructive
        ? t.danger
        : t.textPrimary;
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
            style: ZebuTextStyles.small(context).copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w600,
            ),
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
    // Filled Create button keeps the Mynt brand blue in both modes.
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

// ---------------------------------------------------------------------------
// Section title
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label.toUpperCase(), style: ZebuTextStyles.eyebrow(context));
  }
}

// ---------------------------------------------------------------------------
// Labeled form field — label above, child input below, optional error line
// ---------------------------------------------------------------------------

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
              style: ZebuTextStyles.small(context).copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w600,
              ),
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
          Text(error!, style: ZebuTextStyles.small(context).copyWith(color: t.danger)),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Select field — bordered box with an optional icon, value/placeholder,
// and a trailing chevron. Tapping calls [onTap]; the field can hand its
// own build context to a caller via [anchorContext] so an [AppDropdown]
// lands under the field, not under the [_SelectField] state.
// ---------------------------------------------------------------------------

class _SelectField extends StatefulWidget {
  const _SelectField({
    required this.onTap,
    this.icon,
    this.value,
    this.placeholder,
    this.trailingIcon,
    this.onClear,
    this.anchorContext,
    this.hasError = false,
  });

  final VoidCallback onTap;
  final IconData? icon;
  final String? value;
  final String? placeholder;

  /// Override the default trailing chevron (e.g. `Icons.add` for the
  /// collaborators field).
  final IconData? trailingIcon;

  /// When non-null and a value is set, a small hover-red X sits after the
  /// value so the user can clear the selection inline.
  final VoidCallback? onClear;

  /// Kept for reference — the caller can attach its own [Builder] context
  /// so a popup dropdown lands under the field. Not read directly here;
  /// [onTap] closes over it.
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
                    fontWeight: hasValue
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.onClear != null && hasValue) ...[
                _MiniIcon(icon: Icons.close, onTap: widget.onClear!),
                const SizedBox(width: 2),
              ],
              Icon(
                widget.trailingIcon ?? Icons.keyboard_arrow_down,
                size: 18,
                color: t.textSecondary,
              ),
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

// ---------------------------------------------------------------------------
// Text input — matches _SearchInput styling used elsewhere
// ---------------------------------------------------------------------------

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
      borderSide: BorderSide(
        color: hasError ? t.danger : t.accent,
        width: 1.4,
      ),
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
        hintStyle: ZebuTextStyles.body(context).copyWith(color: t.textSecondary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Outlined action button (for "Insert canned response")
// ---------------------------------------------------------------------------

class _OutlinedAction extends StatefulWidget {
  const _OutlinedAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_OutlinedAction> createState() => _OutlinedActionState();
}

class _OutlinedActionState extends State<_OutlinedAction> {
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
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s3,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: _hover ? t.accentSoft : t.bgElevated,
            border: Border.all(
              color: _hover ? t.accent : t.borderSubtle,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 16, color: t.accent),
              const SizedBox(width: ZebuSpacing.s2),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZebuTextStyles.small(context).copyWith(
                    color: t.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Attachments block — labeled area with an "Add files" link and file chips
// ---------------------------------------------------------------------------

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
              style: ZebuTextStyles.small(context).copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w600,
              ),
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

// ---------------------------------------------------------------------------
// Chip (collaborators, attachments)
// ---------------------------------------------------------------------------

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
              style: ZebuTextStyles.small(context).copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _MiniIcon(icon: Icons.close, onTap: onDelete),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline error banner
// ---------------------------------------------------------------------------

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
          Icon(
            Icons.error_outline,
            size: 16,
            color: t.danger,
          ),
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
// User picker dialog — web-styled Dialog with a search field and list.
// Replaces the mobile pickUser bottom sheet so we don't get a phone-shaped
// modal sliding up over a desktop dialog.
// ---------------------------------------------------------------------------

class _UserPickerDialog extends ConsumerStatefulWidget {
  const _UserPickerDialog({required this.title});
  final String title;

  @override
  ConsumerState<_UserPickerDialog> createState() => _UserPickerDialogState();
}

class _UserPickerDialogState extends ConsumerState<_UserPickerDialog> {
  final _ctrl = TextEditingController();
  List<AppUser> _results = const [];
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
          .read(usersRepositoryProvider)
          .list(q: q, limit: 25);
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
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZebuSpacing.s4,
                  vertical: ZebuSpacing.s3,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: t.borderSubtle, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: ZebuTextStyles.smallStrong(context).copyWith(fontSize: 15),
                      ),
                    ),
                    _IconBtn(
                      icon: Icons.close,
                      tooltip: 'Close',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(ZebuSpacing.s3),
                child: _TextInput(
                  controller: _ctrl,
                  hint: 'Search by name or email',
                ),
              ),
              // _ctrl doesn't notify listeners, so wire the change here.
              // (Handled via onChanged on the underlying field below.)
              const SizedBox.shrink(),
              Expanded(
                child: _UserResultsList(
                  loading: _loading,
                  error: _error,
                  results: _results,
                  onPick: (u) => Navigator.of(context).pop(u),
                  onSearch: _onChanged,
                  controller: _ctrl,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wraps the search field's onChanged wiring + the results list. Extracted
/// so [_UserPickerDialogState] doesn't juggle two build subtrees for the
/// same controller.
class _UserResultsList extends StatelessWidget {
  const _UserResultsList({
    required this.loading,
    required this.error,
    required this.results,
    required this.onPick,
    required this.onSearch,
    required this.controller,
  });

  final bool loading;
  final String? error;
  final List<AppUser> results;
  final ValueChanged<AppUser> onPick;
  final ValueChanged<String> onSearch;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    if (loading) {
      // Attach the onChanged proxy through a hidden listener widget so we
      // don't build the search field twice.
      return _SearchListener(
        controller: controller,
        onSearch: onSearch,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (error != null) {
      return _SearchListener(
        controller: controller,
        onSearch: onSearch,
        child: Center(
          child: Text(error!, style: ZebuTextStyles.small(context).copyWith(color: t.danger)),
        ),
      );
    }
    if (results.isEmpty) {
      return _SearchListener(
        controller: controller,
        onSearch: onSearch,
        child: Center(child: Text('No users found', style: ZebuTextStyles.small(context))),
      );
    }
    return _SearchListener(
      controller: controller,
      onSearch: onSearch,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: results.length,
        itemBuilder: (_, i) {
          final u = results[i];
          return _UserRow(user: u, onTap: () => onPick(u));
        },
      ),
    );
  }
}

class _SearchListener extends StatefulWidget {
  const _SearchListener({
    required this.controller,
    required this.onSearch,
    required this.child,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final Widget child;

  @override
  State<_SearchListener> createState() => _SearchListenerState();
}

class _SearchListenerState extends State<_SearchListener> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => widget.onSearch(widget.controller.text);

  @override
  Widget build(BuildContext context) => widget.child;
}

class _UserRow extends StatefulWidget {
  const _UserRow({required this.user, required this.onTap});
  final AppUser user;
  final VoidCallback onTap;

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s4,
            vertical: ZebuSpacing.s2,
          ),
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgElevated,
            border: Border(
              bottom: BorderSide(color: t.borderSubtle, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZebuTextStyles.body(context).copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                widget.user.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZebuTextStyles.small(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Canned response picker dialog — web-styled Dialog, replaces the mobile
// bottom-sheet variant.
// ---------------------------------------------------------------------------

class _CannedPickerDialog extends ConsumerStatefulWidget {
  const _CannedPickerDialog();

  @override
  ConsumerState<_CannedPickerDialog> createState() =>
      _CannedPickerDialogState();
}

class _CannedPickerDialogState extends ConsumerState<_CannedPickerDialog> {
  List<CannedResponse> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await ref.read(cannedRepositoryProvider).list(limit: 50);
      if (!mounted) return;
      setState(() {
        _items = page.items;
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
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: t.bgElevated,
            border: Border.all(color: t.borderSubtle, width: 1),
            borderRadius: BorderRadius.circular(ZebuRadius.rMd),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: ZebuSpacing.s4,
                  vertical: ZebuSpacing.s3,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: t.borderSubtle, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Canned responses',
                        style: ZebuTextStyles.smallStrong(context).copyWith(fontSize: 15),
                      ),
                    ),
                    _IconBtn(
                      icon: Icons.close,
                      tooltip: 'Close',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBody(t)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ZebuTheme t) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: ZebuTextStyles.small(context).copyWith(color: t.danger)),
      );
    }
    if (_items.isEmpty) {
      return Center(child: Text('No canned responses', style: ZebuTextStyles.small(context)));
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final c = _items[i];
        return _CannedRow(
          canned: c,
          onTap: () => Navigator.of(context).pop(c),
        );
      },
    );
  }
}

class _CannedRow extends StatefulWidget {
  const _CannedRow({required this.canned, required this.onTap});
  final CannedResponse canned;
  final VoidCallback onTap;

  @override
  State<_CannedRow> createState() => _CannedRowState();
}

class _CannedRowState extends State<_CannedRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final snippet = Fmt.stripHtml(widget.canned.body);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s4,
            vertical: ZebuSpacing.s3,
          ),
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgElevated,
            border: Border(
              bottom: BorderSide(color: t.borderSubtle, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.canned.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZebuTextStyles.body(context).copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ZebuTextStyles.small(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
