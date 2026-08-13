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
import '../../../widgets/app_toast.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';
import '../../../widgets/web/zebu_dialog.dart';
import '../../../res/zebu_status_style.dart';
import '../../../widgets/web/attachment_list.dart';
import '../../../widgets/web/preview_picker.dart';
import '../../../widgets/web/property_menu.dart';
import '../../../widgets/web/user_card.dart';
import '../../../widgets/web/zebu_avatar.dart';
import '../../../widgets/web/property_rows.dart';
import '../../../widgets/web/form_fields.dart';
import '../../../widgets/web/zebu_text_action.dart';
import '../../../widgets/web/zebu_date_picker.dart';

/// Ticket source options (the `source` param), mirroring the web dropdown.
const _sources = ['Phone', 'Email', 'Web', 'Other'];

const _kFlatRadius = 8.0;

/// Open the new-ticket form as a centered modal dialog. Called by the
/// sidebar's "+ New Ticket" button on web. Blocks outside-click dismiss so
/// half-filled form data doesn't disappear on a stray click.
Future<void> showCreateTicketDialog(BuildContext context) {
  return showZebuDialog<void>(
    context,
    barrierLabel: 'New ticket',
    // Outside-click stays disabled: this form holds enough half-typed work
    // that a stray click on the page behind it must not discard it. `Esc`
    // and the close button both still work.
    dismissible: false,
    child: Builder(
      builder: (ctx) =>
          CreateTicketScreenWeb(onClose: () => Navigator.of(ctx).pop()),
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

/// Menu value standing for "clear this field". Meta ids are always positive,
/// so a negative sentinel can never collide with a real one.
const int _kNoValue = -1;

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

  /// Drops one field's error as soon as it is being corrected.
  void _clearError(String field) {
    if (!_fieldErrors.containsKey(field)) return;
    setState(() => _fieldErrors = {..._fieldErrors}..remove(field));
  }

  Future<void> _submit() async {
    // Per field, not one banner at the top — see the note on the task
    // dialog's submit.
    final errors = <String, String>{
      if (_user == null) 'user_id': 'Pick a requester',
      if (_subject.text.trim().isEmpty) 'subject': 'A ticket needs a subject',
      if (_message.text.trim().isEmpty) 'message': 'Describe the issue',
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
          await repo.assign(ticket.id, staffId: _agent?.id, teamId: _team?.id);
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

  /// One popover for the whole field — grid, time and Clear on a single
  /// surface, anchored under the value like every other property row.
  ///
  /// This used to open a two-entry Change / Clear menu first, and then two
  /// stacked Material modals: `showDatePicker` followed by `showTimePicker`.
  /// The intermediate menu existed only because `showDatePicker` has no way to
  /// say "no date"; [showZebuDatePicker] carries Clear in its own footer, so
  /// the hop is gone and setting a due date is one surface instead of three.
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

  // --- Dropdown pickers (anchored under the field) --------------------------

  Future<void> _pickSource(BuildContext anchorContext) async {
    final chosen = await showZebuPropertyMenu<String>(
      anchorContext,
      items: [
        for (final s in _sources)
          ZebuPropertyMenuItem<String>(
            value: s,
            label: s,
            selected: s == _source,
          ),
      ],
    );
    if (chosen != null) setState(() => _source = chosen);
  }

  /// Fetches a meta list and opens the property menu under the tapped value.
  ///
  /// [dotFor] paints an 8 px colour chip before each entry — passed for
  /// Status and Priority, where the colour carries as much as the word.
  Future<void> _pickMeta(
    BuildContext anchorContext,
    String kind,
    ValueChanged<MetaItem?> onPicked, {
    MetaItem? current,
    String clearLabel = 'None',
    Color Function(String name)? dotFor,
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
      items: [
        // Clearing lives in the menu now that the rows have no X, and it is
        // more discoverable there: the X only appeared once a value was set,
        // so nothing ever told you the field could be emptied again. Muted,
        // because it names the default rather than offering another value.
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

  // --- Dialog pickers (user search / canned response search) ----------------

  /// osTicket stores some names wrapped in apostrophes — `'Amol Mohile'` —
  /// and they are data, not emphasis. Stripped for display only; the value
  /// posted back is untouched.
  static String _clean(String s) {
    var v = s.trim();
    while (v.length > 1 &&
        ((v.startsWith("'") && v.endsWith("'")) ||
            (v.startsWith('"') && v.endsWith('"')))) {
      v = v.substring(1, v.length - 1).trim();
    }
    return v;
  }

  /// Searches the user directory server-side and returns menu rows.
  ///
  /// Shared by Requester and Collaborators — the only difference is what the
  /// caller does with the result.
  Future<List<ZebuPropertyMenuItem<int>>> _searchUsers(
    String q,
    List<AppUser> sink, {
    int? selectedId,
  }) async {
    final page = await ref.read(usersRepositoryProvider).list(q: q, limit: 25);
    sink
      ..clear()
      ..addAll(page.items);
    return [
      for (final u in page.items)
        ZebuPropertyMenuItem<int>(
          value: u.id,
          label: _clean(u.name),
          // Org where the API gives one. The list endpoint omits it today, so
          // this is usually just the address — built conditionally rather
          // than left as an empty separator hanging off the email.
          subtitle: u.org == null
              ? u.email
              : '${u.email} · ${_clean(u.org!.name)}',
          leading: ZebuAvatar.solid(name: _clean(u.name), size: 28),
          selected: u.id == selectedId,
        ),
    ];
  }

  Future<void> _pickRequester(BuildContext anchorContext) async {
    final found = <AppUser>[];
    final id = await showZebuPropertyMenu<int>(
      anchorContext,
      // The menu takes the field's own width. Menus are right-aligned to
      // their trigger, so a fixed 340 under a 294 px field hung 46 px past
      // its left edge — outside the dialog entirely. Matching the width lines
      // both edges up, which is what a select is expected to do anyway.
      matchAnchorWidth: true,
      maxHeight: 260,
      searchHint: 'Search by name or email',
      search: (q) => _searchUsers(q, found, selectedId: _user?.id),
    );
    if (id == null || !mounted) return;
    final picked = found.firstWhere((u) => u.id == id);
    setState(() => _user = picked);
    _clearError('user_id');

    // The list endpoint omits org, so fetch the full record to fill the card's
    // chip. Failure is silent — the chip is a nicety, and a toast about it
    // would be louder than the fact it carries.
    try {
      final full = await ref.read(usersRepositoryProvider).get(id);
      if (mounted && _user?.id == id) setState(() => _user = full);
    } on ApiException {
      // Keep the summary record.
    }
  }

  /// Multi-select, staying open between ticks. The dialog it replaced closed
  /// on every pick, so adding four people meant opening it four times.
  Future<void> _pickCollaborators(BuildContext anchorContext) async {
    final found = <AppUser>[];
    final chosen = await showZebuMultiSelectMenu<int>(
      anchorContext,
      matchAnchorWidth: true,
      maxHeight: 240,
      searchHint: 'Search by name or email',
      selected: {for (final c in _collaborators) c.id},
      search: (q) => _searchUsers(q, found),
    );
    if (chosen == null || !mounted) return;
    // Anyone already chosen is kept even when the last search did not return
    // them — the working set outlives whatever the box was showing.
    final byId = {
      for (final c in _collaborators) c.id: c,
      for (final u in found) u.id: u,
    };
    setState(() {
      _collaborators
        ..clear()
        ..addAll(chosen.map((id) => byId[id]).whereType<AppUser>());
    });
  }

  /// Two-pane popover: titles left, the full reply right, Insert commits.
  ///
  /// Was a centred dialog, which it had to be while there was nowhere to read
  /// the body — choosing a reply you have not read is how the wrong one gets
  /// sent. The preview pane answers that, so the scrim is no longer earning
  /// anything and the picker sits under the link that opened it.
  Future<void> _pickCanned(BuildContext anchorContext) async {
    final List<CannedResponse> items;
    try {
      final page = await ref.read(cannedRepositoryProvider).list(limit: 50);
      items = page.items;
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
      return;
    }
    if (!mounted || !anchorContext.mounted) return;
    if (items.isEmpty) {
      _toast('No canned responses yet');
      return;
    }

    final id = await showZebuPreviewPicker<int>(
      anchorContext,
      searchHint: 'Search canned responses',
      confirmLabel: 'Insert',
      // footnote: 'Appends to your message',
      items: [
        for (final c in items)
          ZebuPreviewItem<int>(
            value: c.id,
            title: c.title,
            // Bodies come back as HTML; the composer is plain text, so the
            // preview shows exactly what will be inserted rather than a
            // rendered version of something else.
            body: Fmt.stripHtml(c.body),
          ),
      ],
    );
    if (id == null || !mounted) return;

    final chosen = items.firstWhere((c) => c.id == id);
    setState(() {
      // One canned response at a time: a new pick replaces the message rather
      // than stacking under the last, so picking twice leaves one response and
      // not two. Anything typed by hand goes with it — chosen deliberately
      // over swapping only the inserted block.
      final text = Fmt.stripHtml(chosen.body);
      _message.value = TextEditingValue(
        text: text,
        // Caret at the end, so the agent carries straight on typing instead of
        // landing at character zero in front of what was just inserted.
        selection: TextSelection.collapsed(offset: text.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return ZebuDialogShell(
      title: 'New ticket',
      // Wider than a confirm — this is a real form with two-up rows — but
      // capped in both axes so the form scrolls inside a fixed frame instead
      // of growing one. Matches the new-task dialog, which was already
      // 640 wide while this one ran to 720 with no height limit at all.
      maxWidth: 640,
      maxHeight: 700,
      onDismiss: _close,
      onSubmit: _saving ? null : _submit,
      // The action is pinned in a footer here, not placed in the body as the
      // short dialogs do: this form scrolls, and a submit button that scrolls
      // out of view is one an agent has to hunt back down for.
      actions: [
        ZebuDialogPrimaryBtn(
          label: 'Create ticket',
          busyLabel: 'Creating\u2026',
          busy: _saving,
          onTap: _submit,
        ),
      ],
      body: AbsorbPointer(absorbing: _saving, child: _buildBody(t)),
    );
  }

  Widget _buildBody(ZebuTheme t) {
    return SingleChildScrollView(
      // padding: const EdgeInsets.fromLTRB(
      //   ZebuSpacing.s6,
      //   ZebuSpacing.s4,
      //   ZebuSpacing.s6,
      //   ZebuSpacing.s5,
      // ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: ZebuSpacing.s4),
          ],

          // --- USER & COLLABORATORS --------------------------------------
          ZebuSectionTitle('User & collaborators'),
          const SizedBox(height: ZebuSpacing.s3),
          // Two-up: both name people, they are read together, and stacking
          // them full-width made the form taller than the dialog for no gain.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ZebuLabeledField(
                  label: 'Requester',
                  error: _fieldErrors['user_id'],
                  child: Builder(
                    builder: (anchorContext) => _user == null
                        ? ZebuPersonPlaceholder(
                            icon: Icons.person_outline,
                            label: 'Select a requester',
                            hint: 'Who the ticket is for',
                            hasError: _fieldErrors['user_id'] != null,
                            onTap: () => _pickRequester(anchorContext),
                          )
                        : ZebuUserCard(
                            name: _clean(_user!.name),
                            email: _user!.email,
                            chips: [
                              if (_user!.org != null)
                                ZebuUserChip(_clean(_user!.org!.name)),
                            ],
                            onChange: () => _pickRequester(anchorContext),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: ZebuSpacing.s3),
              Expanded(
                child: ZebuLabeledField(
                  label: 'Collaborators (Cc)',
                  child: Builder(
                    builder: (anchorContext) => _collaborators.isEmpty
                        ? ZebuPersonPlaceholder(
                            icon: Icons.group_outlined,
                            label: 'Add collaborators',
                            // Not "every reply" — the Note field below this
                            // one is staff-only, and collaborators never see
                            // it. Saying where the line falls is the whole
                            // reason an agent hesitates over adding one.
                            hint: "Cc'd on replies, not internal notes",
                            onTap: () => _pickCollaborators(anchorContext),
                          )
                        : ZebuCollaboratorsCard(
                            names: [
                              for (final c in _collaborators) _clean(c.name),
                            ],
                            onEdit: () => _pickCollaborators(anchorContext),
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ZebuSpacing.s5),

          // --- TICKET DETAILS --------------------------------------------
          ZebuSectionTitle('Ticket details'),
          const SizedBox(height: ZebuSpacing.s3),
          ZebuLabeledField(
            label: 'Subject',
            error: _fieldErrors['subject'],
            child: ZebuFormInput(
              controller: _subject,
              onChanged: (_) => _clearError('subject'),
              // An example, not a description of the field. "Short summary"
              // described what to write and implied prose; this is a one-line
              // title that becomes the row in the list and the email subject,
              // so showing a well-formed one teaches the shape in less space.
              hint: 'e.g. Unable to reset account password',
              hasError: _fieldErrors['subject'] != null,
            ),
          ),
          const SizedBox(height: ZebuSpacing.s4),
          ZebuLabeledField(
            label: 'Message',
            error: _fieldErrors['message'],
            // The canned picker writes into *this* field, so it belongs on
            // this field's label row. Sat between Subject and Message as a
            // full-width outlined box it looked like a third input, and it
            // read as attached to Subject — which it never touches.
            // The `Builder` sits inside the action, not around the field —
            // `findRenderObject()` walks down, so an anchor taken one level up
            // would be the whole label row and the popover would hang off it.
            // Same control as Apply on the date picker — accent label, pill
            // only on hover, no icon. It was a bolt glyph plus text in its own
            // one-off widget; there is no reason a text action on a label row
            // should look different from a text action in a popover footer.
            trailing: Builder(
              builder: (anchorContext) => ZebuTextAction(
                label: 'Canned response',
                onTap: () => _pickCanned(anchorContext),
              ),
            ),
            child: ZebuFormInput(
              controller: _message,
              onChanged: (_) => _clearError('message'),
              // You describe the issue, not the ticket — and naming the three
              // things an agent always has to ask for saves the round trip.
              hint: 'What happened, when, and what you expected instead…',
              minLines: 5,
              maxLines: 12,
              hasError: _fieldErrors['message'] != null,
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
          // The approved mock's treatment: a flat label -> value grid, one
          // hairline per row, no boxes and no leading glyphs. The value is
          // the control. Saying "all optional" once in the eyebrow is what
          // lets every row below drop its own qualifier.
          ZebuPropertyGrid(
            rows: [
              ZebuPropertySpec(
                label: 'Department',
                icon: Icons.business_outlined,
                value: _department?.name,
                onTap: (ctx) => _pickMeta(
                  ctx,
                  MetaKind.departments,
                  (m) => setState(() => _department = m),
                  current: _department,
                ),
              ),
              ZebuPropertySpec(
                label: 'Assign to agent',
                icon: Icons.person_outline,
                value: _agent?.name,
                placeholder: 'Auto-assign',
                onTap: (ctx) => _pickMeta(
                  ctx,
                  MetaKind.agents,
                  (m) => setState(() => _agent = m),
                  current: _agent,
                  clearLabel: 'Auto-assign',
                ),
              ),
              ZebuPropertySpec(
                label: 'Assign to team',
                icon: Icons.groups_outlined,
                value: _team?.name,
                onTap: (ctx) => _pickMeta(
                  ctx,
                  MetaKind.teams,
                  (m) => setState(() => _team = m),
                  current: _team,
                ),
              ),
              ZebuPropertySpec(
                label: 'Help topic',
                icon: Icons.topic_outlined,
                value: _topic?.name,
                onTap: (ctx) => _pickMeta(
                  ctx,
                  MetaKind.topics,
                  (m) => setState(() => _topic = m),
                  current: _topic,
                ),
              ),
              // Status and Priority carry a dot in the status colour. The
              // word alone made two rows of blue text that read as the same
              // kind of fact as Department; the colour is half the meaning.
              ZebuPropertySpec(
                label: 'Status',
                icon: Icons.flag_outlined,
                value: _status?.name,
                placeholder: 'Open (default)',
                dotColor: zebuStatusStyle(_status?.name ?? '', t).dot,
                onTap: (ctx) => _pickMeta(
                  ctx,
                  MetaKind.statuses,
                  (m) => setState(() => _status = m),
                  current: _status,
                  clearLabel: 'Open (default)',
                  dotFor: (n) => zebuStatusStyle(n, t).dot,
                ),
              ),
              ZebuPropertySpec(
                label: 'Priority',
                icon: Icons.priority_high_rounded,
                value: _priority?.name,
                placeholder: 'Normal (default)',
                dotColor: zebuPriorityStyle(_priority?.name, t).dot,
                onTap: (ctx) => _pickMeta(
                  ctx,
                  MetaKind.priorities,
                  (m) => setState(() => _priority = m),
                  current: _priority,
                  clearLabel: 'Normal (default)',
                  dotFor: (n) => zebuPriorityStyle(n, t).dot,
                ),
              ),
              ZebuPropertySpec(
                label: 'Source',
                icon: Icons.podcasts_outlined,
                value: _source,
                onTap: _pickSource,
              ),
              ZebuPropertySpec(
                label: 'Due date',
                icon: Icons.schedule_outlined,
                value: _due == null ? null : Fmt.dateTime(_due),
                onTap: _pickDue,
              ),
            ],
          ),

          const SizedBox(height: ZebuSpacing.s5),

          // --- INTERNAL NOTE ---------------------------------------------
          ZebuSectionTitle('Internal note'),
          const SizedBox(height: ZebuSpacing.s3),
          ZebuLabeledField(
            label: 'Note',
            child: ZebuFormInput(
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

// ---------------------------------------------------------------------------
// Footer — Cancel + Create ticket, right-aligned, top border.
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
// User picker dialog — web-styled Dialog with a search field and list.
// Replaces the mobile pickUser bottom sheet so we don't get a phone-shaped
// modal sliding up over a desktop dialog.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Canned response picker dialog — web-styled Dialog, replaces the mobile
// bottom-sheet variant.
// ---------------------------------------------------------------------------
