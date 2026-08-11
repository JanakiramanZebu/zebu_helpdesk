import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/assets.dart';
import '../../../core/format.dart';
import '../../../models/common.dart';
import '../../../models/me.dart';
import '../../../models/meta.dart';
import '../../../models/ticket.dart';
import '../../../providers.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/comment_composer.dart';
import '../../../widgets/states.dart';
import '../../../widgets/web/status_pill.dart';
import '../../../res/zebu_status_colors.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';
import '../../../widgets/web/zebu_avatar.dart';

/// Web-only ticket-detail slide-over panel.
///
/// Layout borrows from the Asana / ClickUp task-detail treatments referenced
/// in the migration plan:
///   - Header carries a primary state CTA on the left (Change status / Reopen)
///     and a right cluster for Actions + Fullscreen + Close.
///   - `#{number}` chip precedes the title on its own row, keeping the title
///     as the visual anchor.
///   - Fields are laid out as a left-labeled table (icon + label + value)
///     instead of a chip row + wrap grid — every ticket attribute lives in
///     one place, clickable rows keep the existing dropdown anchoring.
///   - Thread rows use an actor-avatar column with a deterministic hue,
///     matching the reference activity feed. Sort toggle sits above the
///     thread and flips Newest ↕ Oldest.
///
/// Data comes from [ticketsRepositoryProvider] — same source the mobile
/// detail screen uses. Advanced surfaces (custom fields editor, tag/
/// collaborator management, attachments upload) are intentionally deferred;
/// the mobile screen keeps them.
const _kFlatRadius = 8.0;

/// Field label column width — inside a half-width grid cell 88 fits
/// "Department" / "Requester" / "Created" without wrapping while leaving
/// enough room for the value on the right.
const double _kFieldLabelWidth = 88;

/// Fixed width of the outlined select pill on clickable rows. Keeps the
/// dropdown-trigger geometry consistent field-to-field instead of the
/// pill stretching across half the panel next to short values like
/// `Normal`.
const double _kFieldValueWidth = 280;

/// Avatar circle diameter — thread rows carry a colored initial avatar so
/// the activity list scans like the reference feed.

/// Panel-body width at (or above) which the panel switches to a two-column
/// layout: activity feed on the left, fields sidebar on the right. Below
/// this breakpoint the body falls back to the vertically stacked layout so
/// narrow panels + phone-sized viewports stay legible.
const double _kTwoColumnBreakpoint = 780;

/// Fixed width of the right-hand fields sidebar in two-column mode. Wide
/// enough to fit the `[icon][label 88][value ...]` row without truncation
/// on the longer field values, tight enough that the activity column keeps
/// the majority of the panel.
const double _kFieldsSidebarWidth = 360;

/// Per-agent action gates for a ticket, ported from osTicket's
/// `Ticket::checkStaffPerm()` (`include/class.ticket.php`). The backend enforces
/// these on every mutating `/tickets/*` endpoint (403 otherwise); mirroring them
/// here hides/disables the affordances an agent can't use — matching the SCP
/// rule that a ticket "cannot be edited by others". Visibility is already
/// granted (the detail loaded), so only the per-department role permission
/// matters.
class _TicketCaps {
  const _TicketCaps({
    this.canEdit = false,
    this.canAssign = false,
    this.canRelease = false,
    this.canTransfer = false,
    this.canClose = false,
    this.canReply = false,
  });

  final bool canEdit; // ticket.edit — priority + field edits
  final bool canAssign; // ticket.assign — assign + claim
  final bool canRelease; // ticket.release — release assignment
  final bool canTransfer; // ticket.transfer — department change
  final bool canClose; // ticket.close
  final bool canReply; // ticket.reply

  /// `/tickets/{id}/status` accepts PERM_CLOSE **or** PERM_EDIT.
  bool get canChangeStatus => canClose || canEdit;

  /// `/tickets/{id}/note` accepts PERM_REPLY **or** PERM_EDIT.
  bool get canNote => canReply || canEdit;

  /// Header actions other than claim/release (which also depend on ticket
  /// assignment state, resolved in [_Header]).
  bool get hasTopAction =>
      canChangeStatus || canEdit || canAssign || canTransfer;

  /// Whether the Actions menu would surface at least one item for a ticket in
  /// the given assignment state. Release only applies to an assigned ticket;
  /// claim (assign perm) is already part of [hasTopAction].
  bool actionsAvailable({required bool assigned}) =>
      hasTopAction || (assigned && canRelease);

  factory _TicketCaps.from(Me? me, Ticket? ticket) {
    if (me == null || ticket == null) return const _TicketCaps();
    final d = ticket.departmentId;
    return _TicketCaps(
      canEdit: me.canOn('ticket.edit', d),
      canAssign: me.canOn('ticket.assign', d),
      canRelease: me.canOn('ticket.release', d),
      canTransfer: me.canOn('ticket.transfer', d),
      canClose: me.canOn('ticket.close', d),
      canReply: me.canOn('ticket.reply', d),
    );
  }
}

class TicketDetailPanel extends ConsumerStatefulWidget {
  const TicketDetailPanel({
    super.key,
    required this.ticketId,
    required this.onClose,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    this.onChanged,
  });
  final int ticketId;
  final VoidCallback onClose;

  /// When true the host is rendering this panel at full viewport width;
  /// the expand button in the header flips its icon accordingly.
  final bool isFullscreen;

  /// Fires when the user taps the header's expand / collapse button. Null
  /// hides the button (useful for hosts that don't opt into fullscreen).
  final VoidCallback? onToggleFullscreen;

  /// Fires after a successful mutation on this ticket (status change,
  /// assign, transfer, priority, claim/release, or reply/note). Hosts
  /// use this to refresh the list underneath so the row reflects the
  /// new value instead of the stale cached one from the last fetch.
  final VoidCallback? onChanged;

  @override
  ConsumerState<TicketDetailPanel> createState() => _TicketDetailPanelState();
}

class _TicketDetailPanelState extends ConsumerState<TicketDetailPanel> {
  Ticket? _ticket;
  List<ThreadEntry> _thread = const [];
  Object? _error;
  bool _loading = true;
  bool _acting = false;

  // GlobalKeys on the inline-editable field rows. The state CTA in the
  // header + the Actions menu both reuse these keys to anchor their picker
  // dropdown to the field being edited (via `key.currentContext`), keeping
  // the user's eyes on the value that's about to change.
  final GlobalKey _statusRowKey = GlobalKey(debugLabel: 'ticket-status-row');
  final GlobalKey _priorityRowKey =
      GlobalKey(debugLabel: 'ticket-priority-row');
  final GlobalKey _assigneeRowKey =
      GlobalKey(debugLabel: 'ticket-assignee-row');
  final GlobalKey _departmentRowKey =
      GlobalKey(debugLabel: 'ticket-department-row');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      final ticket = await repo.get(widget.ticketId);
      final thread = await repo.thread(widget.ticketId, limit: 50);
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _thread = thread.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _toast(String msg, {ToastType type = ToastType.info}) =>
      AppToast.show(context, msg, type: type);

  Future<void> _runAction(
    Future<Ticket> Function() action, {
    String? success,
  }) async {
    setState(() => _acting = true);
    try {
      final updated = await action();
      setState(() => _ticket = updated);
      // Bubble the change up so the host list can refresh — otherwise
      // the row underneath keeps the stale field (e.g. assignee) from
      // the last fetch.
      widget.onChanged?.call();
      if (success != null) _toast(success, type: ToastType.success);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _onMenu(String value) async {
    final repo = ref.read(ticketsRepositoryProvider);
    switch (value) {
      case 'claim':
        await _runAction(
          () => repo.claim(widget.ticketId),
          success: 'Ticket claimed',
        );
      case 'release':
        await _runAction(
          () => repo.release(widget.ticketId),
          success: 'Ticket released',
        );
      // Actions-menu counterparts for the inline fields — reuse the field
      // key so the dropdown lands under the value it's editing, not under
      // the Actions button in the header.
      case 'status':
        final ctx = _statusRowKey.currentContext;
        if (ctx != null) await _pickTicketStatus(ctx);
        return;
      case 'priority':
        final ctx = _priorityRowKey.currentContext;
        if (ctx != null) await _pickTicketPriority(ctx);
        return;
      case 'assign':
        final ctx = _assigneeRowKey.currentContext;
        if (ctx != null) await _pickTicketAssignee(ctx);
        return;
      case 'transfer':
        final ctx = _departmentRowKey.currentContext;
        if (ctx != null) await _pickTicketDepartment(ctx);
        return;
    }
    // Silent thread refresh — actions like status/claim add server-side
    // notes we want to see. Not calling `_load()` because that flips
    // `_loading = true`, which repaints the panel as a spinner and reads
    // as a full "reload flash" to the user.
    await _refreshThread();
  }

  /// Refetches the thread without touching `_loading` — keeps the panel
  /// visible while a background load runs.
  Future<void> _refreshThread() async {
    try {
      final thread = await ref
          .read(ticketsRepositoryProvider)
          .thread(widget.ticketId, limit: 50);
      if (!mounted) return;
      setState(() => _thread = thread.items);
    } catch (_) {
      // Non-fatal — the thread will refresh on the next explicit reload.
    }
  }

  /// Refetches ticket + thread in parallel without flipping `_loading`.
  /// Used after send-reply / send-note so the newly posted entry appears
  /// in place instead of a spinner-flash-full-reload — same "swap
  /// silently" pattern the field pickers use.
  Future<void> _reloadSilent() async {
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      final ticketFuture = repo.get(widget.ticketId);
      final threadFuture = repo.thread(widget.ticketId, limit: 50);
      final ticket = await ticketFuture;
      final thread = await threadFuture;
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _thread = thread.items;
      });
    } catch (_) {
      // Non-fatal — the next explicit action or reload will re-sync.
    }
  }

  /// Loads a meta kind (statuses, priorities, agents, departments) and
  /// opens an app-styled dropdown anchored under [anchorContext]. When
  /// [header] is set the popup gets a small-caps section title; when
  /// [currentName] matches an entry, that row shows a leading check —
  /// the reference Asana-style single-select treatment.
  Future<void> _pickMetaMenu(
    BuildContext anchorContext,
    String kind,
    Future<void> Function(int id) onPick, {
    String? header,
    String? currentName,
  }) async {
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(kind);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
      return;
    }
    if (!mounted || !anchorContext.mounted) return;
    final current = currentName?.trim().toLowerCase();
    final chosen = await showAppDropdown<int>(
      anchorContext,
      entries: [
        if (header != null) AppDropdownHeader<int>(header),
        for (final m in items)
          AppDropdownItem<int>(
            value: m.id,
            label: m.name,
            selected: current != null &&
                current.isNotEmpty &&
                m.name.trim().toLowerCase() == current,
          ),
      ],
    );
    if (chosen != null) await onPick(chosen);
  }

  Future<void> _pickTicketStatus(BuildContext anchorContext) async {
    final repo = ref.read(ticketsRepositoryProvider);
    await _pickMetaMenu(
      anchorContext,
      MetaKind.statuses,
      (id) async {
        await _runAction(
          () => repo.setStatus(widget.ticketId, id),
          success: 'Status updated',
        );
        await _refreshThread();
      },
      header: 'Status',
      currentName: _ticket?.statusName,
    );
  }

  Future<void> _pickTicketPriority(BuildContext anchorContext) async {
    final repo = ref.read(ticketsRepositoryProvider);
    await _pickMetaMenu(
      anchorContext,
      MetaKind.priorities,
      (id) async {
        await _runAction(
          () => repo.setPriority(widget.ticketId, id),
          success: 'Priority updated',
        );
        await _refreshThread();
      },
      header: 'Priority',
      currentName: _ticket?.priority,
    );
  }

  Future<void> _pickTicketAssignee(BuildContext anchorContext) async {
    final repo = ref.read(ticketsRepositoryProvider);
    await _pickMetaMenu(
      anchorContext,
      MetaKind.agents,
      (id) async {
        await _runAction(
          () => repo.assign(widget.ticketId, staffId: id),
          success: 'Assigned',
        );
        await _refreshThread();
      },
      header: 'Assignee',
      currentName: _ticket?.assignee,
    );
  }

  Future<void> _pickTicketDepartment(BuildContext anchorContext) async {
    final repo = ref.read(ticketsRepositoryProvider);
    await _pickMetaMenu(
      anchorContext,
      MetaKind.departments,
      (id) async {
        await _runAction(
          () => repo.transfer(widget.ticketId, id),
          success: 'Transferred',
        );
        await _refreshThread();
      },
      header: 'Department',
      currentName: _ticket?.departmentName,
    );
  }

  Future<bool> _sendReply({
    required bool asNote,
    required String bodyHtml,
    required List<MultipartFile> files,
  }) async {
    if (bodyHtml.trim().isEmpty && files.isEmpty) return false;
    setState(() => _acting = true);
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      if (asNote) {
        await repo.note(widget.ticketId, body: bodyHtml, files: files);
      } else {
        await repo.reply(
          widget.ticketId,
          body: bodyHtml,
          alert: true,
          files: files,
        );
      }
      _toast(asNote ? 'Note added' : 'Reply sent', type: ToastType.success);
      // Reply/note can flip a ticket between Open/Answered buckets on
      // the server — notify the host so the row is refetched.
      widget.onChanged?.call();
      // Silent in-place refresh — no spinner flash, no full panel reload.
      await _reloadSilent();
      return true;
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
      return false;
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    // The left seam (border + shadow) is drawn by [SlideOverHost] so every
    // panel gets an identical divider from the list underneath.
    return Material(
      // Warm-paper ground so the panel matches the list surface behind it.
      // Cards inside (header strip, thread rows, activity header) keep
      // `bgElevated` so they read as elevated on the paper.
      color: t.bgPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      child: _buildBody(t),
    );
  }

  Widget _buildBody(ZebuTheme t) {
    if (_loading) {
      return Column(
        children: [
          _Header(
            ticket: null,
            onClose: widget.onClose,
            onMenu: null,
            isFullscreen: widget.isFullscreen,
            onToggleFullscreen: widget.onToggleFullscreen,
          ),
          const Expanded(child: LoadingView()),
        ],
      );
    }
    if (_error != null || _ticket == null) {
      return Column(
        children: [
          _Header(
            ticket: null,
            onClose: widget.onClose,
            onMenu: null,
            isFullscreen: widget.isFullscreen,
            onToggleFullscreen: widget.onToggleFullscreen,
          ),
          Expanded(
            child: ErrorView(error: _error ?? 'Not found', onRetry: _load),
          ),
        ],
      );
    }
    final ticket = _ticket!;
    // Per-agent action gates (ported from Ticket::checkStaffPerm). `me` is
    // loaded app-wide at startup, so asData is populated by the time this
    // opens; until then caps default to none (safe — the backend 403s anyway).
    final me = ref.watch(meProvider).asData?.value;
    final caps = _TicketCaps.from(me, ticket);

    return Column(
      children: [
        _Header(
          ticket: ticket,
          caps: caps,
          onClose: widget.onClose,
          onMenu: _onMenu,
          isFullscreen: widget.isFullscreen,
          onToggleFullscreen: widget.onToggleFullscreen,
        ),
        if (_acting) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _kTwoColumnBreakpoint;
              if (wide) return _buildWide(t, ticket, caps);
              return _buildNarrow(t, ticket, caps);
            },
          ),
        ),
        // Reply needs ticket.reply; an internal note needs ticket.reply OR
        // ticket.edit (mirrors the /note endpoint). So: full composer when the
        // agent can reply, note-only when they can only edit, disabled when
        // neither.
        CommentComposer(
          onSend: _sendReply,
          scope: caps.canReply
              ? ComposerScope.replyAndNote
              : ComposerScope.noteOnly,
          disabled: _acting || !caps.canNote,
        ),
      ],
    );
  }

  /// Narrow single-column layout: fields card on top, activity feed below,
  /// composer at the bottom. Same layout the panel shipped with before the
  /// two-column split, kept for the sub-780 px slot the panel gets when the
  /// list underneath is still visible on smaller viewports.
  Widget _buildNarrow(ZebuTheme t, Ticket ticket, _TicketCaps caps) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: ZebuSpacing.s3),
        _FieldsTable(
          ticket: ticket,
          sidebar: false,
          statusRowKey: _statusRowKey,
          priorityRowKey: _priorityRowKey,
          assigneeRowKey: _assigneeRowKey,
          departmentRowKey: _departmentRowKey,
          onStatusTap: caps.canChangeStatus ? _pickTicketStatus : null,
          onPriorityTap: caps.canEdit ? _pickTicketPriority : null,
          onAssigneeTap: caps.canAssign ? _pickTicketAssignee : null,
          onDepartmentTap: caps.canTransfer ? _pickTicketDepartment : null,
        ),
        const SizedBox(height: ZebuSpacing.s2),
        const _ActivityHeader(),
        if (_thread.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ZebuSpacing.s6),
            child: Center(
              child: Text('No messages yet', style: ZebuTextStyles.small(context)),
            ),
          )
        else ...[
          for (final e in _thread) _ThreadRow(entry: e),
          const SizedBox(height: ZebuSpacing.s3),
        ],
      ],
    );
  }

  /// Two-column layout used at ≥ [_kTwoColumnBreakpoint] px: activity feed
  /// on the left (grows to fill), fields sidebar on the right at
  /// [_kFieldsSidebarWidth]. A hairline seam separates the two columns —
  /// matches the reference layout where the details block sits as a fixed
  /// rail alongside the message thread.
  Widget _buildWide(ZebuTheme t, Ticket ticket, _TicketCaps caps) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (_thread.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: ZebuSpacing.s8),
                  child: Center(
                    child: Text('No messages yet', style: ZebuTextStyles.small(context)),
                  ),
                )
              else ...[
                const SizedBox(height: ZebuSpacing.s3),
                for (final e in _thread) _ThreadRow(entry: e),
                const SizedBox(height: ZebuSpacing.s3),
              ],
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: t.borderSubtle, width: 1),
            ),
          ),
          child: SizedBox(
            width: _kFieldsSidebarWidth,
            child: ListView(
              // padding: const EdgeInsets.symmetric(vertical: ZebuSpacing.s4),
              children: [
                _FieldsTable(
                  ticket: ticket,
                  sidebar: true,
                  statusRowKey: _statusRowKey,
                  priorityRowKey: _priorityRowKey,
                  assigneeRowKey: _assigneeRowKey,
                  departmentRowKey: _departmentRowKey,
                  onStatusTap: caps.canChangeStatus ? _pickTicketStatus : null,
                  onPriorityTap: caps.canEdit ? _pickTicketPriority : null,
                  onAssigneeTap: caps.canAssign ? _pickTicketAssignee : null,
                  onDepartmentTap: caps.canTransfer ? _pickTicketDepartment : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header — primary state CTA (left), close/fullscreen/actions (right),
// then a title row below with the `#{number}` chip in front of the subject.
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.ticket,
    this.caps = const _TicketCaps(),
    required this.onClose,
    required this.onMenu,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });
  final Ticket? ticket;
  final _TicketCaps caps;
  final VoidCallback onClose;
  final Future<void> Function(String value)? onMenu;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s4,
        ZebuSpacing.s3,
        ZebuSpacing.s4,
        ZebuSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(
          bottom: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      // Single-row header — `#chip + title` on the left, `Actions +
      // Fullscreen + Close` cluster on the right. Title truncates instead
      // of wrapping so the row stays at the same height regardless of
      // subject length.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (ticket == null)
            Expanded(child: Text('Loading…', style: ZebuTextStyles.smallStrong(context)))
          else ...[
            _NumberChip(number: ticket!.number),
            const SizedBox(width: ZebuSpacing.s3),
            Expanded(
              child: Text(
                ticket!.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZebuTextStyles.pageTitle(context),
              ),
            ),
          ],
          const SizedBox(width: ZebuSpacing.s3),
          // Claim needs assign perm (only when unassigned); Release needs
          // release perm (only when assigned). Show the Actions button when the
          // agent has at least one action available for this ticket's state.
          if (ticket != null &&
              onMenu != null &&
              caps.actionsAvailable(
                assigned: (ticket!.assignee ?? '').isNotEmpty,
              )) ...[
            _ActionsBtn(ticket: ticket!, caps: caps, onSelected: onMenu!),
            const SizedBox(width: ZebuSpacing.s2),
          ],
          if (onToggleFullscreen != null) ...[
            _IconBtn(
              icon: isFullscreen
                  ? Icons.close_fullscreen
                  : Icons.open_in_full,
              tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
              onTap: onToggleFullscreen!,
            ),
            const SizedBox(width: ZebuSpacing.s2),
          ],
          // Not `destructive` — that paints a red hover fill, which belongs
          // to actions that lose something (Delete, Ban). Dismissing the
          // panel discards nothing, so it hovers like its neighbours.
          _IconBtn(
            icon: Icons.close,
            tooltip: 'Close',
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

/// Small pill that reads `#12345` — sits next to the title as a breadcrumb
/// prefix, replacing the previous stacked `#number` above the subject.
class _NumberChip extends StatelessWidget {
  const _NumberChip({required this.number});
  final String number;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.bgTertiary,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        '#$number',
        style: ZebuTextStyles.small(context)
            .copyWith(
              fontWeight: FontWeight.w600,
              color: t.textPrimary,
            )
            .withTabularNums(),
      ),
    );
  }
}

/// Actions button — outlined ghost pill with `Actions ⌄` label. Same
/// visual language as the neighbouring [_IconBtn] cluster (subtle border,
/// bgHover fill on hover) instead of the previous solid-accent default,
/// so the header reads as one calm control group.
class _ActionsBtn extends StatefulWidget {
  const _ActionsBtn({
    required this.ticket,
    required this.caps,
    required this.onSelected,
  });
  final Ticket ticket;
  final _TicketCaps caps;
  final Future<void> Function(String value) onSelected;

  @override
  State<_ActionsBtn> createState() => _ActionsBtnState();
}

class _ActionsBtnState extends State<_ActionsBtn> {
  bool _hover = false;

  Future<void> _open() async {
    final ticket = widget.ticket;
    final caps = widget.caps;
    final assigned = (ticket.assignee ?? '').isNotEmpty;
    // Claim (self-assign) needs assign perm and only shows when unassigned;
    // Release needs release perm and only shows when assigned.
    final showClaim = !assigned && caps.canAssign;
    final showRelease = assigned && caps.canRelease;
    // Only surface actions the agent may actually perform — each gated by the
    // same permission the matching /tickets endpoint enforces (checkStaffPerm).
    final chosen = await showAppDropdown<String>(
      context,
      entries: [
        const AppDropdownHeader<String>('Ticket actions'),
        if (caps.canChangeStatus)
          const AppDropdownItem(
            value: 'status',
            label: 'Change status',
            svgAsset: Assets.actStatus,
          ),
        if (caps.canEdit)
          const AppDropdownItem(
            value: 'priority',
            label: 'Set priority',
            svgAsset: Assets.actPriority,
          ),
        if (caps.canAssign)
          const AppDropdownItem(
            value: 'assign',
            label: 'Assign',
            svgAsset: Assets.actAssign,
          ),
        if (caps.canTransfer)
          const AppDropdownItem(
            value: 'transfer',
            label: 'Transfer dept',
            svgAsset: Assets.actTransfer,
          ),
        if (showClaim || showRelease) ...[
          if (caps.hasTopAction) const AppDropdownDivider<String>(),
          if (showClaim)
            const AppDropdownItem(
              value: 'claim',
              label: 'Claim',
              svgAsset: Assets.actClaim,
            )
          else
            const AppDropdownItem(
              value: 'release',
              label: 'Release',
              svgAsset: Assets.actRelease,
            ),
        ],
      ],
    );
    if (chosen != null) await widget.onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Tooltip(
      message: 'Actions',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _hover ? t.bgHover : t.bgElevated,
              border: Border.all(color: t.borderSubtle, width: 1),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Actions',
                  style: ZebuTextStyles.body(context).copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 16, color: t.textPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatefulWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final bg = _hover ? t.bgHover : t.bgElevated;
    final fg = t.textPrimary;
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
            // border: Border.all(color: t.borderSubtle, width: 1),
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Icon(widget.icon, size: 18, color: fg),
        ),
      ),
    );
    return widget.tooltip == null
        ? child
        : Tooltip(message: widget.tooltip!, child: child);
  }
}

// ---------------------------------------------------------------------------
// Fields table — every attribute lives in a two-column grid so the panel
// reads compact instead of a long vertical stack. Clickable cells
// (status / priority / assignee / department) reuse the existing GlobalKey
// anchoring so the picker dropdown lands under the value being edited.
// ---------------------------------------------------------------------------

class _FieldsTable extends StatelessWidget {
  const _FieldsTable({
    required this.ticket,
    required this.sidebar,
    required this.statusRowKey,
    required this.priorityRowKey,
    required this.assigneeRowKey,
    required this.departmentRowKey,
    required this.onStatusTap,
    required this.onPriorityTap,
    required this.onAssigneeTap,
    required this.onDepartmentTap,
  });
  final Ticket ticket;

  /// True when this table is rendered inside the wide-mode right rail —
  /// drops the outer rounded card + horizontal padding so the rows sit
  /// flush inside the sidebar. The sidebar's own left border acts as the
  /// separator instead.
  final bool sidebar;

  final GlobalKey statusRowKey;
  final GlobalKey priorityRowKey;
  final GlobalKey assigneeRowKey;
  final GlobalKey departmentRowKey;

  /// Null when the current agent lacks the permission for that field — the
  /// row then renders as static text (no chevron, no tap), mirroring the
  /// backend's per-action checkStaffPerm gate.
  final ValueChanged<BuildContext>? onStatusTap;
  final ValueChanged<BuildContext>? onPriorityTap;
  final ValueChanged<BuildContext>? onAssigneeTap;
  final ValueChanged<BuildContext>? onDepartmentTap;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final priority = (ticket.priority ?? '').trim();
    final assignee = (ticket.assignee ?? '').trim();
    final department = (ticket.departmentName ?? '').trim();
    final requester = (ticket.requester ?? '').trim();
    final sla = ticket.sla;
    final slaLabel = sla?.label?.trim() ?? '';

    final userEmail = (ticket.userEmail ?? '').trim();

    // Assignee leads: it's the field the operator changes most often and
    // the one they scan for first when triaging. The rest follows the
    // triage-then-metadata rhythm: state (status/priority), routing
    // (department), requester context, deadlines, then timestamps.
    final cells = <Widget>[
      if (sidebar) const _FieldGroupLabel('Assignment', first: true),
      _FieldRow(
        rowKey: assigneeRowKey,
        icon: Icons.person_outline,
        label: 'Assignee',
        sidebar: sidebar,
        onTap: onAssigneeTap,
        value: assignee.isEmpty
            ? const _EmptyValue(label: 'Unassigned')
            : _TextValue(
                text: assignee,
                tone: sidebar ? t.linkSlate : t.accent,
                linked: true,
              ),
      ),
      _FieldRow(
        rowKey: departmentRowKey,
        icon: Icons.business_outlined,
        label: 'Department',
        sidebar: sidebar,
        onTap: onDepartmentTap,
        value: department.isEmpty
            ? const _EmptyValue(label: 'None')
            : _TextValue(
                text: department,
                tone: sidebar ? t.linkSlate : t.accent,
                linked: true,
              ),
      ),
      if (sidebar) const _FieldGroupLabel('Ticket'),
      _FieldRow(
        rowKey: statusRowKey,
        icon: Icons.flag_outlined,
        label: 'Status',
        sidebar: sidebar,
        onTap: onStatusTap,
        value: Builder(
          builder: (_) {
            final c = zebuStatusColor(
              ticket.statusName,
              t,
              overdue: ticket.isOverdue,
            );
            // Sidebar: colour the value itself. A bar or dot before it
            // pushed Status and Priority out of the column every other
            // value lines up in, and the colour is legible without one.
            // `zebuOnTint` because this text sits on white, where the
            // vivid palette tone is harsher still than on a 12 % wash.
            return sidebar
                ? _TextValue(
                    text: ticket.statusName,
                    tone: zebuOnTint(c, t),
                  )
                : _StatusValuePill(label: ticket.statusName, color: c);
          },
        ),
      ),
      _FieldRow(
        rowKey: priorityRowKey,
        icon: Icons.priority_high,
        label: 'Priority',
        sidebar: sidebar,
        onTap: onPriorityTap,
        value: priority.isEmpty
            ? const _EmptyValue(label: 'No priority')
            : (sidebar
                  ? _TextValue(
                      text: _titleCase(priority),
                      tone: zebuOnTint(zebuPriorityColor(priority, t), t),
                    )
                  : _StatusValuePill(
                      label: _titleCase(priority),
                      color: zebuPriorityColor(priority, t),
                      icon: Icons.flag_rounded,
                    )),
      ),
      if (sidebar && (requester.isNotEmpty || userEmail.isNotEmpty))
        const _FieldGroupLabel('Requester'),
      if (requester.isNotEmpty)
        _FieldRow(
          icon: Icons.alternate_email,
          label: 'Requester',
          sidebar: sidebar,
          value: _TextValue(
            text: requester,
            tone: sidebar ? t.textSlate : null,
          ),
        ),
      if (userEmail.isNotEmpty)
        _FieldRow(
          icon: Icons.mail_outline,
          label: 'Email',
          sidebar: sidebar,
          value: _TextValue(
            text: userEmail,
            tone: sidebar ? t.textSlate : null,
          ),
        ),
      if (sidebar) const _FieldGroupLabel('Schedule'),
      if (ticket.due != null)
        _FieldRow(
          icon: Icons.schedule,
          label: 'Due',
          sidebar: sidebar,
          value: _TextValue(
            text: Fmt.dateTime(ticket.due),
            tone: ticket.isOverdue
                ? t.danger
                : (sidebar ? t.textSlate : null),
          ),
        ),
      if (sla != null && slaLabel.isNotEmpty)
        _FieldRow(
          icon: Icons.hourglass_bottom,
          label: 'SLA',
          sidebar: sidebar,
          value: sidebar
              ? _TextValue(
                  text: slaLabel,
                  tone: zebuOnTint(
                    sla.isOverdue ? t.danger : ZebuTheme.warning,
                    t,
                  ),
                )
              : _StatusValuePill(
                  label: slaLabel,
                  color: sla.isOverdue ? t.danger : ZebuTheme.warning,
                ),
        ),
      _FieldRow(
        icon: Icons.event_outlined,
        label: 'Created',
        sidebar: sidebar,
        value: _TextValue(
          text: Fmt.dateTime(ticket.created),
          tone: sidebar ? t.textSlate : null,
        ),
      ),
      if (ticket.updated != null)
        _FieldRow(
          icon: Icons.update,
          label: 'Updated',
          sidebar: sidebar,
          value: _TextValue(
            text: Fmt.dateTime(ticket.updated),
            tone: sidebar ? t.textSlate : null,
          ),
        ),
    ];

    // Sidebar mode: rows sit directly on the panel, no card.
    //
    // They used to be wrapped in a bordered, shadowed card so they'd read as
    // one block against a warm off-white page. The page is white now and the
    // card fill was `bgElevated` — also white — so the card drew a border and
    // a shadow around nothing. The sidebar's own left divider already
    // separates this column from the thread, which is the job the card was
    // duplicating.
    if (sidebar) {
      return Padding(
        // Top matches the bottom so the block sits evenly in the sidebar —
        // the enclosing ListView adds s4 on both edges, and this adds s3 to
        // each, for 28 above and below.
        padding: const EdgeInsets.fromLTRB(
          ZebuSpacing.s4,
          ZebuSpacing.s3,
          ZebuSpacing.s4,
          ZebuSpacing.s3,
        ),
        child: DefaultTextStyle.merge(
          style: ZebuTextStyles.body(context).copyWith(color: t.textPrimary),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Names the rail. The panel header above carries the ticket's
              // number and subject, so without this the column of fields
              // starts with no indication of what it belongs to.
              Padding(
                padding: const EdgeInsets.only(
                  left: ZebuSpacing.s2,
                  bottom: ZebuSpacing.s3,
                ),
                child: Text(
                  'Ticket Details',
                  style: ZebuTextStyles.sectionTitle(
                    context,
                    color: t.textSlate,
                  ),
                ),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: t.dividerSlate,
              ),
              const SizedBox(height: ZebuSpacing.s4),
              ...cells,
            ],
          ),
        ),
      );
    }
    // Narrow single-column: wraps the fields in an email-style card so the
    // metadata block reads as one contained module (rounded hairline
    // border + `bgElevated` fill). Without the fill the card blended into
    // the page bg in dark mode — the border alone wasn't enough separation.
    // The DefaultTextStyle.merge pins the ambient base to `bodySm` so
    // [_TextValue] rows read at 13 px — matching the tighter single-column
    // rhythm.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(ZebuRadius.rMd),
          border: Border.all(color: t.borderSubtle, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s3,
            vertical: ZebuSpacing.s2,
          ),
          child: DefaultTextStyle.merge(
            style: ZebuTextStyles.small(context).copyWith(color: t.textPrimary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: cells,
            ),
          ),
        ),
      ),
    );
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}

/// Single row: `[icon 16] [label 110 muted] [value expanded]`. Clickable
/// rows tint the value on hover so the affordance is discoverable without
/// the row growing a border or shadow.
class _FieldRow extends StatefulWidget {
  const _FieldRow({
    this.rowKey,
    required this.icon,
    required this.label,
    required this.value,
    required this.sidebar,
    this.onTap,
  });

  /// GlobalKey attached to the outlined select pill (not the whole row) so
  /// `rowKey.currentContext` returns the pill's element. Popup anchors
  /// under the pill instead of the row's left edge, keeping the dropdown
  /// visually attached to the value it's editing.
  final GlobalKey? rowKey;
  final IconData icon;
  final String label;
  final Widget value;

  /// True when the row is rendered inside the wide-mode right rail. In
  /// sidebar mode the clickable value slot flexes to fill remaining space
  /// instead of using the fixed [_kFieldValueWidth] pill width — the
  /// sidebar itself is only ~320 px wide, so a 280 px value would clip.
  final bool sidebar;

  /// Non-null makes the row clickable. Receives the pill's build context
  /// so the caller can anchor a popup directly beneath the value.
  final ValueChanged<BuildContext>? onTap;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final clickable = widget.onTap != null;
    return widget.sidebar
        ? _buildSidebar(context, t, clickable)
        : _buildInline(context, t, clickable);
  }

  /// Sidebar rail: a leading glyph, then the label stacked above its value,
  /// with a chevron on rows that open a picker.
  ///
  /// Stacked rather than label-left/value-right because the rail is only
  /// 360 px wide — side by side, a fixed label column ate a quarter of it and
  /// long values (assignee names, timestamps) had nowhere to go. The chevron
  /// is the one thing that separates an editable field from a read-only one,
  /// so it stays.
  Widget _buildSidebar(BuildContext context, ZebuTheme t, bool clickable) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s2,
        vertical: 7,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Glyph sits in a tinted tile, as the design specifies. It gives
          // the rail a consistent left rhythm a bare icon on white doesn't,
          // and keeps narrow glyphs (flag) optically the same size as wide
          // ones (calendar).
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? t.surfaceMutedStrong : t.surfaceMuted,
              borderRadius: BorderRadius.circular(ZebuRadius.rSm),
            ),
            child: Icon(widget.icon, size: 16, color: t.iconMuted),
          ),
          const SizedBox(width: ZebuSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: ZebuTextStyles.small(
                    context,
                    color: t.textSlateMuted,
                  ),
                ),
                const SizedBox(height: 3),
                widget.value,
              ],
            ),
          ),
          if (clickable)
            Icon(
              Icons.expand_more,
              size: 16,
              color: _hover ? t.linkSlate : t.iconMuted,
            ),
        ],
      ),
    );
    if (!clickable) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // The whole row is the dropdown's anchor now that there is no pill
        // to hang it on, so the popup lands under the full-width field.
        onTap: () => widget.onTap!(widget.rowKey?.currentContext ?? context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            color: _hover ? t.bgHover : t.bgElevated,
            borderRadius: BorderRadius.circular(ZebuRadius.rXs),
          ),
          child: KeyedSubtree(key: widget.rowKey, child: row),
        ),
      ),
    );
  }

  /// Narrow single-column card: label left, value right on one line.
  Widget _buildInline(BuildContext context, ZebuTheme t, bool clickable) {
    final Widget valueSlot;
    if (clickable) {
      // Key on the pill (not the row) — dropdown popups anchor here so
      // they land under the value, aligned with the trigger's left edge.
      final Widget pill = KeyedSubtree(
        key: widget.rowKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: widget.value),
              Icon(
                Icons.expand_more,
                size: 16,
                color: _hover ? t.accent : t.textSecondary,
              ),
            ],
          ),
        ),
      );
      valueSlot = SizedBox(width: _kFieldValueWidth, child: pill);
    } else {
      valueSlot = Expanded(child: widget.value);
    }
    final row = SizedBox(
      height: 30,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s1),
        child: Row(
          children: [
            SizedBox(
              width: _kFieldLabelWidth,
              child: Text(
                widget.label,
                style: ZebuTextStyles.body(
                  context,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: ZebuSpacing.s3),
            valueSlot,
          ],
        ),
      ),
    );
    if (!clickable) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap!(widget.rowKey?.currentContext ?? context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          color: t.bgElevated,
          child: row,
        ),
      ),
    );
  }
}

/// Small-caps heading over a run of field rows ("ASSIGNMENT", "SCHEDULE").
///
/// Borrowed from the grouped design: the dividers alone told you fields were
/// related but not why. Rendered without that design's blue rule and tinted
/// icon tiles — at 360 px wide the chrome competed with the values.
class _FieldGroupLabel extends StatelessWidget {
  const _FieldGroupLabel(this.label, {this.first = false});
  final String label;

  /// Skips the top divider on the first group, which would otherwise sit
  /// directly under the panel header.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: ZebuSpacing.s2,
        right: ZebuSpacing.s2,
        top: first ? 0 : ZebuSpacing.s4,
        bottom: ZebuSpacing.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!first) ...[
            Divider(height: 1, thickness: 1, color: t.dividerSlate),
            const SizedBox(height: ZebuSpacing.s4),
          ],
          Text(
            label,
            style: ZebuTextStyles.eyebrow(
              context,
              color: t.textSlateMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Plain text value used by read-only rows and the assignee / department /
/// requester rows when set.
class _TextValue extends StatefulWidget {
  const _TextValue({required this.text, this.tone, this.linked = false});
  final String text;

  /// Optional semantic tone (e.g. red for an overdue due-date, accent
  /// blue for an editable link). Falls back to `textPrimary` when null.
  final Color? tone;

  /// When true, the value tracks its own hover state and underlines the
  /// text under the pointer — same "anchor tag" affordance a form link
  /// would carry. Used on editable text values (Assignee, Department
  /// with real names) to reinforce click-to-edit.
  final bool linked;

  @override
  State<_TextValue> createState() => _TextValueState();
}

class _TextValueState extends State<_TextValue> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final color = widget.tone ?? t.textPrimary;
    // Inherit the ambient DefaultTextStyle base so the sidebar's bumped
    // 14 px wrap propagates into value text — the surrounding column
    // wraps in a DefaultTextStyle.merge with `bodyBase`, and this pulls
    // that size out of the ambient rather than hard-pinning to `bodySm`.
    final base = DefaultTextStyle.of(context).style;
    final child = Text(
      widget.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(
        color: color,
        fontWeight: FontWeight.w500,
        decoration: widget.linked && _hover
            ? TextDecoration.underline
            : TextDecoration.none,
        decorationColor: color,
      ),
    );
    if (!widget.linked) return child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: child,
    );
  }
}



class _StatusValuePill extends StatelessWidget {
  const _StatusValuePill({
    required this.label,
    required this.color,
    this.icon,
  });
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: StatusPill(label: label, color: color, icon: icon),
    );
  }
}

/// Muted placeholder value shown when the field has no data yet. Reads as
/// "click to set" — the parent row's caret already carries the affordance
/// so no extra chrome is needed here.
class _EmptyValue extends StatelessWidget {
  const _EmptyValue({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ZebuTextStyles.body(context).copyWith(
        color: t.textPrimary,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity subheader — sits above the thread. Left label + sort toggle on
// the right, hairline borders top & bottom.
// ---------------------------------------------------------------------------

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader();

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    // No divider under the label — each thread entry below sits inside
    // its own card, so a hairline here would double up as visual noise
    // between the header and the first card. Top hairline stays to
    // separate the activity block from the fields grid above.
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s4,
        vertical: ZebuSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(
          top: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      child: Text(
        'Activity',
        style: ZebuTextStyles.smallStrong(context).copyWith(color: t.textPrimary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thread entry — actor-avatar column on the left, body indented under the
// poster name so the whole activity feed reads as one column of entries.
// ---------------------------------------------------------------------------

/// Width held back from every bubble so the opposite side always reads as
/// empty gutter. Covers the avatar (32) + its gap (12) on the sender's
/// side plus a deliberate ~15% of a typical panel on the far side.
const double _kBubbleGutter = 220;

class _ThreadRow extends StatefulWidget {
  const _ThreadRow({required this.entry});
  final ThreadEntry entry;

  @override
  State<_ThreadRow> createState() => _ThreadRowState();
}

class _ThreadRowState extends State<_ThreadRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final entry = widget.entry;
    final isNote = entry.isNote;
    final isResponse = entry.isResponse;
    final tone = isNote
        ? t.note
        : (isResponse ? t.accent : t.textSecondary);
    final typeLabel = isNote
        ? 'NOTE'
        : (isResponse ? 'REPLY' : 'MESSAGE');
    final html = entry.bodyHtml ?? entry.body ?? '';
    final plain = Fmt.stripHtml(html);

    // Chat-bubble layout: the requester's messages sit on the left, staff
    // replies and internal notes on the right. `type` is osTicket's own
    // M / R / N, so the side is *customer vs staff* rather than
    // *me vs everyone else* — the thread therefore renders identically for
    // every agent looking at the ticket, and a second agent's reply doesn't
    // jump sides depending on who is signed in.
    //
    // Notes have no natural side (they're addressed to nobody), so they
    // follow their author onto the staff side and lean on the violet fill
    // and NOTE tag to say they never left the building.
    final onRight = !entry.isMessage;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s4,
        ZebuSpacing.s3,
        ZebuSpacing.s4,
        0,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          // Cap the bubble well short of the full column so the opposite
          // side always shows as empty gutter — that gutter *is* the
          // directional cue, and a full-width bubble would erase it. Long
          // email bodies still get most of the width.
          //
          // Proportional, capped: a fixed 220 would swallow half a narrow
          // side-panel, and a flat percentage would waste 400 px on a wide
          // monitor where the gutter is already unmistakable.
          final gutter = (c.maxWidth * 0.25).clamp(0.0, _kBubbleGutter);
          final maxBubble = (c.maxWidth - gutter).clamp(0.0, c.maxWidth);
          final avatar = ZebuAvatar(name: entry.poster);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: onRight
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              if (!onRight) ...[avatar, const SizedBox(width: ZebuSpacing.s3)],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubble),
                  child: MouseRegion(
                    onEnter: (_) => setState(() => _hover = true),
                    onExit: (_) => setState(() => _hover = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        // Every bubble is plain white. The side it sits on
                        // and its type tag carry the whole distinction —
                        // tinting the fill as well made the thread read as
                        // three competing colours.
                        color: t.bgTertiary,
                        // The corner nearest the avatar is clipped short —
                        // the standard bubble tail, and the only thing in
                        // the shape that encodes direction.
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(onRight ? 12 : 4),
                          topRight: Radius.circular(onRight ? 4 : 12),
                          bottomLeft: const Radius.circular(12),
                          bottomRight: const Radius.circular(12),
                        ),
                        // border: Border.all(
                        //   color: _hover ? t.borderDefault : t.borderSubtle,
                        //   width: 1,
                        // ),
                        // boxShadow: _hover
                        //     ? ZebuElevation.shadowSm
                        //     : ZebuElevation.shadowXs,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: ZebuSpacing.s4,
                        vertical: ZebuSpacing.s3,
                      ),
                      child: Column(
                        // Body copy stays left-aligned in both bubbles —
                        // ragged-left paragraphs are unreadable, and the
                        // bubble's position already carries the direction.
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  entry.poster,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: ZebuTextStyles.body(
                                    context,
                                    color: t.textPrimary,
                                    fontWeight: ZebuFonts.semiBold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: ZebuSpacing.s2),
                              _TypeTag(label: typeLabel, tone: tone),
                            ],
                          ),
                          const SizedBox(height: ZebuSpacing.s2),
                          if (plain.trim().isEmpty)
                            Text(
                              '(no content)',
                              style: ZebuTextStyles.small(context),
                            )
                          else if (html.contains('<'))
                            _HtmlBody(html: html)
                          else
                            Text(
                              plain,
                              style: ZebuTextStyles.body(
                                context,
                              ).copyWith(height: 1.5),
                            ),
                          if (entry.attachments.isNotEmpty) ...[
                            const SizedBox(height: ZebuSpacing.s3),
                            Wrap(
                              spacing: ZebuSpacing.s2,
                              runSpacing: ZebuSpacing.s2,
                              children: [
                                for (final a in entry.attachments)
                                  _AttachmentChip(attachment: a),
                              ],
                            ),
                          ],
                          if (entry.created != null) ...[
                            const SizedBox(height: ZebuSpacing.s2),
                            // Bottom-right rather than pinned to the card's
                            // top corner: a shrink-wrapped bubble around
                            // "hi" has no top-right corner to spare, and
                            // reserving one would force a minimum width on
                            // every short message.
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                Fmt.ago(entry.created),
                                style: ZebuTextStyles.small(
                                  context,
                                  color: t.textSlateMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (onRight) ...[const SizedBox(width: ZebuSpacing.s3), avatar],
            ],
          );
        },
      ),
    );
  }
}

/// Small colored uppercase label used inside a thread row header (REPLY /
/// NOTE / MESSAGE). Same treatment as the previous `_Tag` primitive.
class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.label, required this.tone});
  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: ZebuTextStyles.label(context).copyWith(color: tone));
  }
}

// ---------------------------------------------------------------------------
// Attachment chip — icon + name + size, opens signed URL in a new tab
// ---------------------------------------------------------------------------

class _AttachmentChip extends StatefulWidget {
  const _AttachmentChip({required this.attachment});
  final Attachment attachment;

  @override
  State<_AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends State<_AttachmentChip> {
  bool _hover = false;

  IconData get _icon {
    final t = widget.attachment.type ?? '';
    if (t.startsWith('image/')) return Icons.image_outlined;
    if (t.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (t.contains('sheet') || t.contains('excel')) {
      return Icons.table_chart_outlined;
    }
    if (t.contains('word') || t.contains('document')) {
      return Icons.description_outlined;
    }
    if (t.contains('zip') || t.contains('rar') || t.contains('compressed')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.attach_file;
  }

  Future<void> _open() async {
    final a = widget.attachment;
    final url = a.downloadUrl ?? a.streamUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final a = widget.attachment;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(
            horizontal: ZebuSpacing.s2,
            vertical: ZebuSpacing.s2,
          ),
          decoration: BoxDecoration(
            // White rather than a grey fill: the chip sits inside a thread
            // card that is already white, and the file-type tile is what
            // gives it presence now.
            color: _hover ? t.accentSoft : t.bgElevated,
            border: Border.all(
              color: _hover ? t.accent : t.borderSubtle,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // File-type glyph in a tinted tile — the same device the
              // ticket sidebar uses for its field icons, so an attachment
              // reads as a proper object rather than an inline label.
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(ZebuRadius.rXs),
                ),
                child: Icon(_icon, size: 17, color: t.accent),
              ),
              const SizedBox(width: ZebuSpacing.s3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZebuTextStyles.body(
                    context,
                    color: t.textSlate,
                    fontWeight: ZebuFonts.medium,
                  ),
                ),
              ),
              if (a.size != null) ...[
                const SizedBox(width: ZebuSpacing.s3),
                Text(
                  Fmt.fileSize(a.size),
                  style: ZebuTextStyles.small(
                    context,
                    color: t.textSlateMuted,
                  ).withTabularNums(),
                ),
              ],
              const SizedBox(width: ZebuSpacing.s3),
              Icon(Icons.open_in_new, size: 16, color: t.accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floors font sizes at 13 px and caps bold weight at 600, and lets the
/// parent's max width wrap long paragraphs naturally.
class _HtmlBody extends StatelessWidget {
  const _HtmlBody({required this.html});
  final String html;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: HtmlWidget(
        html,
        textStyle: ZebuTextStyles.body(context),
        // Anchor taps aren't clickable by default — HtmlWidget hands the
        // URL to us so we can launch it. `mode: externalApplication` on
        // web opens a new browser tab.
        onTapUrl: (url) async {
          final uri = Uri.tryParse(url);
          if (uri == null) return false;
          return launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        customStylesBuilder: (element) {
          switch (element.localName) {
            case 'b':
            case 'strong':
              return {'font-weight': '600'};
            case 'small':
            case 'sub':
            case 'sup':
              return {'font-size': '13px'};
            case 'a':
              // Match the composer's link styling so a link reads the
              // same before and after send.
              return {
                'color': '#0037B7', // ZebuTheme.accent
                'text-decoration': 'underline',
              };
            default:
              return null;
          }
        },
      ),
    );
  }
}
