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
import '../../../widgets/web/bubble_shape.dart';
import '../../../widgets/web/dots_loader.dart';
import '../../../widgets/web/hatched_card.dart';
import '../../../widgets/web/status_badge.dart';
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
    this.initialTicket,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    this.onChanged,
  });
  final int ticketId;
  final VoidCallback onClose;

  /// The list row's summary of this ticket, when the host has one.
  ///
  /// Purely a first-paint optimisation: the panel still fetches the full
  /// ticket, but with this the header can show the number and subject
  /// immediately rather than the word "Loading…". Every field it carries is
  /// replaced the moment the real fetch lands.
  final Ticket? initialTicket;

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

  /// Whether the right-hand details pane is collapsed to its rail. Panel
  /// state, not persisted: an agent who collapses it for one wide ticket
  /// usually wants it back on the next one.
  bool _detailsCollapsed = false;
  List<ThreadEntry> _thread = const [];
  Object? _error;
  bool _loading = true;
  bool _acting = false;

  // GlobalKeys on the inline-editable field rows. The state CTA in the
  // header + the Actions menu both reuse these keys to anchor their picker
  // dropdown to the field being edited (via `key.currentContext`), keeping
  // the user's eyes on the value that's about to change.
  final GlobalKey _statusRowKey = GlobalKey(debugLabel: 'ticket-status-row');
  final GlobalKey _priorityRowKey = GlobalKey(
    debugLabel: 'ticket-priority-row',
  );
  final GlobalKey _assigneeRowKey = GlobalKey(
    debugLabel: 'ticket-assignee-row',
  );
  final GlobalKey _departmentRowKey = GlobalKey(
    debugLabel: 'ticket-department-row',
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      // Seed from the row's summary so the header has something to draw on
      // the first frame. Null on hosts that don't pass one, which behave
      // exactly as before.
      _ticket ??= widget.initialTicket;
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
            selected:
                current != null &&
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
            // The seeded summary when we have one — the identity of the
            // ticket is not in doubt while its body loads.
            ticket: _ticket,
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
              child: Text(
                'No messages yet',
                style: ZebuTextStyles.small(context),
              ),
            ),
          )
        else ...[
          ..._threadItems(_thread),
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
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          // The thread scrolls on a canvas a hair off white, so an inbound
          // bubble — which is white — reads as an object on a surface rather
          // than dissolving into the page. The sidebar stays pure white, and
          // the one-unit step between them is what separates the two panes
          // without needing a heavier divider.
          child: ColoredBox(
            color: t.threadCanvas,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (_thread.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: ZebuSpacing.s8,
                    ),
                    child: Center(
                      child: Text(
                        'No messages yet',
                        style: ZebuTextStyles.small(context),
                      ),
                    ),
                  )
                else ...[
                  const SizedBox(height: ZebuSpacing.s3),
                  ..._threadItems(_thread),
                  const SizedBox(height: ZebuSpacing.s3),
                ],
              ],
            ),
          ),
        ),
        if (!_detailsCollapsed)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: t.borderSubtle, width: 1)),
            ),
            child: SizedBox(
              width: _kFieldsSidebarWidth,
              child: ListView(
                children: [
                  _FieldsTable(
                    ticket: ticket,
                    sidebar: true,
                    statusRowKey: _statusRowKey,
                    priorityRowKey: _priorityRowKey,
                    assigneeRowKey: _assigneeRowKey,
                    departmentRowKey: _departmentRowKey,
                    onStatusTap: caps.canChangeStatus
                        ? _pickTicketStatus
                        : null,
                    onPriorityTap: caps.canEdit ? _pickTicketPriority : null,
                    onAssigneeTap: caps.canAssign ? _pickTicketAssignee : null,
                    onDepartmentTap: caps.canTransfer
                        ? _pickTicketDepartment
                        : null,
                    onCollapse: () => setState(() => _detailsCollapsed = true),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (!_detailsCollapsed) return row;

    // Collapsed, the pane is gone entirely and only its toggle remains,
    // floated in the corner it vanished from. A persistent rail was cheaper
    // to build but spent 44 px of a column agents read long quoted email in —
    // and the whole point of collapsing was to get that width back.
    return Stack(
      children: [
        row,
        Positioned(
          top: ZebuSpacing.s3,
          right: ZebuSpacing.s3,
          child: _RailToggle(
            icon: Icons.keyboard_double_arrow_left_rounded,
            tooltip: 'Show details',
            onTap: () => setState(() => _detailsCollapsed = false),
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
        border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      // Single-row header — `#chip + title` on the left, `Actions +
      // Fullscreen + Close` cluster on the right. Title truncates instead
      // of wrapping so the row stays at the same height regardless of
      // subject length.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (ticket == null)
            Expanded(
              child: Text(
                'Loading…',
                style: ZebuTextStyles.smallStrong(context),
              ),
            )
          else
            Expanded(child: _TitleBlock(ticket: ticket!)),
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
              icon: isFullscreen ? Icons.close_fullscreen : Icons.open_in_full,
              tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
              onTap: onToggleFullscreen!,
            ),
            const SizedBox(width: ZebuSpacing.s2),
          ],
          // Not `destructive` — that paints a red hover fill, which belongs
          // to actions that lose something (Delete, Ban). Dismissing the
          // panel discards nothing, so it hovers like its neighbours.
          _IconBtn(icon: Icons.close, tooltip: 'Close', onTap: onClose),
        ],
      ),
    );
  }
}

/// Small square chevron button shared by the pane header and its rail.
class _RailToggle extends StatefulWidget {
  const _RailToggle({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_RailToggle> createState() => _RailToggleState();
}

class _RailToggleState extends State<_RailToggle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // Idle is the hover tone at zero alpha, never
              // `Colors.transparent` — that is transparent *black*, and
              // lerping from it drags the fill through a grey flash.
              color: _hover
                  ? t.surfaceMuted
                  : t.surfaceMuted.withValues(alpha: 0),
              border: Border.all(color: t.borderSubtle, width: 1),
              borderRadius: BorderRadius.circular(ZebuRadius.rXs),
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: _hover ? t.textSlate : t.iconMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ticket identity — a quiet meta line over the subject.
///
/// The number and the requester used to share the title's row, which cost the
/// subject ~140 px of the only line it gets. Stacked, the subject runs the
/// full width of the header and truncates far later; the meta line costs no
/// height the header wasn't already reserving.
class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final requester = (ticket.requester ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              '#${ticket.number}',
              // Tabular figures rather than a second typeface: the handoff
              // asks for a monospace ticket id, but the whole point of the
              // one-font rule is that a number needs even columns, not a
              // different family.
              style: ZebuTextStyles.eyebrow(
                context,
                color: t.textSlateMuted,
              ).withTabularNums(),
            ),
            if (requester.isNotEmpty) ...[
              const SizedBox(width: ZebuSpacing.s2),
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: t.borderDefault,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: ZebuSpacing.s2),
              Flexible(
                child: Text(
                  requester,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ZebuTextStyles.eyebrow(
                    context,
                    color: t.textSlateMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 1),
        // Full subject on hover — a truncated subject is the one thing in
        // this header an agent actually needs to read in full, and there is
        // nowhere else on the screen it appears.
        Tooltip(
          message: ticket.subject,
          waitDuration: const Duration(milliseconds: 400),
          child: Text(
            ticket.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: ZebuTextStyles.sectionTitle(
              context,
              color: t.textPrimary,
              fontWeight: ZebuFonts.semiBold,
            ).copyWith(height: 1.25),
          ),
        ),
      ],
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
                  style: ZebuTextStyles.body(
                    context,
                  ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w500),
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
  const _IconBtn({required this.icon, required this.onTap, this.tooltip});
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
    this.onCollapse,
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

  /// Collapses the pane to its rail. Null in the stacked (narrow) layout,
  /// where there is no sidebar to collapse.
  final VoidCallback? onCollapse;

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
        // The badge, not coloured text. Status is the one field here drawn
        // from a fixed vocabulary with a designed fill weight per value, and
        // painting it as plain text threw all of that away.
        //
        // Overdue is deliberately *not* passed here, unlike in the tickets
        // table. This panel has a dedicated SLA row that already reports the
        // breach, and a red Due date above it; letting overdue repaint the
        // Status row too said the same thing three times and — worse — left
        // the badge reading "Re-open" in Overdue's solid red, so its label
        // and its colour disagreed. The table has no SLA column, so there
        // the substitution is the only way to surface a breach.
        value: Align(
          alignment: Alignment.centerLeft,
          child: StatusBadge(
            label: _titleCase(ticket.statusName),
            status: ticket.statusName,
            dense: true,
          ),
        ),
      ),
      _FieldRow(
        rowKey: priorityRowKey,
        icon: Icons.priority_high,
        label: 'Priority',
        sidebar: sidebar,
        onTap: onPriorityTap,
        // Priority stays a tinted pill rather than a StatusBadge: it is a
        // different vocabulary (Low..Emergency), and giving it the status
        // system's fills would put two solid-red badges in adjacent rows.
        value: priority.isEmpty
            ? const _EmptyValue(label: 'No priority')
            : Align(
                alignment: Alignment.centerLeft,
                child: PriorityBadge(
                  label: _titleCase(priority),
                  priority: priority,
                  dense: true,
                ),
              ),
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
            tone: ticket.isOverdue ? t.danger : (sidebar ? t.textSlate : null),
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Ticket Details',
                        style: ZebuTextStyles.sectionTitle(
                          context,
                          color: t.textSlate,
                        ),
                      ),
                    ),
                    if (onCollapse != null)
                      _RailToggle(
                        icon: Icons.keyboard_double_arrow_right_rounded,
                        tooltip: 'Hide details',
                        onTap: onCollapse!,
                      ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: t.dividerSlate),
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
                  style: ZebuTextStyles.small(context, color: t.textSlateMuted),
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
            style: ZebuTextStyles.eyebrow(context, color: t.textSlateMuted),
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
  const _StatusValuePill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: StatusPill(label: label, color: color),
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
      style: ZebuTextStyles.body(
        context,
      ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w500),
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
        border: Border(top: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: Text(
        'Activity',
        style: ZebuTextStyles.smallStrong(
          context,
        ).copyWith(color: t.textPrimary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thread entry — actor-avatar column on the left, body indented under the
// poster name so the whole activity feed reads as one column of entries.
// ---------------------------------------------------------------------------

/// Horizontal space held back from every bubble so the far side always reads
/// as empty gutter — the gutter *is* the directional cue. Deliberately small:
/// the tint and the type tag already say which side an entry is on twice
/// over, and agents read long quoted email in this column, so width is the
/// scarcest thing on the screen.
const double _kBubbleGutter = 160;

/// Inline image preview box. Wide enough that a screenshot of a form or
/// an error dialog is legible without opening it, short enough that a tall
/// portrait image can't push the rest of the thread off-screen.
const double _kPreviewWidth = 280;

/// Attachment chip width. Fixed so a message carrying several files
/// renders a tidy stack rather than a ragged staircase.
const double _kChipWidth = 280;
const double _kPreviewHeight = 180;

/// Avatar diameter plus the gap to the bubble. Reserved on the sender's side
/// even when the avatar is hidden by grouping, so a run of bubbles keeps one
/// straight edge instead of stepping in and out.
const double _kAvatarSize = 32;
const double _kAvatarGap = ZebuSpacing.s3;

/// Consecutive entries by the same author, of the same type, closer together
/// than this collapse into one visual run: avatar and name appear once, and
/// the follow-ups are bare bubbles. Without it a four-reply burst repeats the
/// same name and face four times and reads noisier than a plain list.
const Duration _kGroupWindow = Duration(minutes: 10);

bool _groupsWith(ThreadEntry entry, ThreadEntry? prev) {
  if (prev == null) return false;
  if (prev.poster != entry.poster || prev.type != entry.type) return false;
  final a = prev.created, b = entry.created;
  if (a == null || b == null) return false;
  return b.difference(a).abs() <= _kGroupWindow;
}

/// True when the body says nothing the attachment chips don't already say.
///
/// osTicket fills the body with `Attachment: <filename>` when a file is sent
/// without a message, so the name lands twice — once as body copy and again
/// on the chip directly beneath it.
bool _isAttachmentEcho(String plain, List<Attachment> files) {
  if (files.isEmpty) return false;
  var s = plain.trim();
  final m = RegExp(r'^Attachments?\s*:\s*', caseSensitive: false).firstMatch(s);
  if (m == null) return false;
  s = s.substring(m.end).trim();
  for (final f in files) {
    s = s.replaceFirst(f.name, '').trim();
    s = s.replaceFirst(RegExp(r'^[,;]\s*'), '');
  }
  // Only suppress on an exact echo — a real message that merely opens with
  // the word "Attachment:" must still be shown.
  return s.isEmpty;
}

/// Reveals an entry's exact timestamp on hover. The header only carries a
/// relative time ("a day ago"), and grouped follow-ups have no header at all.
class _Dated extends StatelessWidget {
  const _Dated({required this.created, required this.child});
  final DateTime? created;
  final Widget child;

  @override
  Widget build(BuildContext context) => created == null
      ? child
      : Tooltip(
          message: Fmt.dateTime(created),
          waitDuration: const Duration(milliseconds: 500),
          child: child,
        );
}

/// The thread as a flat widget list, with a [_DateDivider] wherever the day
/// changes. Grouping is suppressed across a divider — a run that straddles
/// midnight would otherwise lose its author to the divider it sits under.
List<Widget> _threadItems(List<ThreadEntry> thread) {
  final out = <Widget>[];
  DateTime? lastDay;
  for (var i = 0; i < thread.length; i++) {
    final e = thread[i];
    var divided = false;
    final d = e.created;
    if (d != null) {
      final day = DateTime(d.year, d.month, d.day);
      if (day != lastDay) {
        out.add(_DateDivider(day: day));
        lastDay = day;
        divided = true;
      }
    }
    out.add(
      _ThreadRow(entry: e, prev: (divided || i == 0) ? null : thread[i - 1]),
    );
  }
  return out;
}

/// A day heading between thread entries — hairlines either side of an
/// uppercase label.
///
/// A ticket can span months. Without this the thread is an undifferentiated
/// run of entries and there is nothing to anchor "when did this go quiet" to,
/// which is exactly the question an agent opens an old ticket to answer.
class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final rule = Expanded(child: Container(height: 1, color: t.borderSubtle));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s4,
        ZebuSpacing.s5,
        ZebuSpacing.s4,
        ZebuSpacing.s1,
      ),
      child: Row(
        children: [
          rule,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s3),
            child: Text(
              Fmt.dayLabel(day).toUpperCase(),
              style: ZebuTextStyles.eyebrow(
                context,
                color: t.textSlateMuted,
              ).copyWith(letterSpacing: 0.6),
            ),
          ),
          rule,
        ],
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.entry, this.prev});
  final ThreadEntry entry;

  /// The entry rendered directly above this one, for grouping. Null for the
  /// first row in the thread and for the first row under a date divider.
  final ThreadEntry? prev;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final isNote = entry.isNote;

    // Side comes from osTicket's own M / R / N: the requester's messages on
    // the left, everything the desk produced — replies and internal notes —
    // on the right. Keying off `type` rather than off the signed-in agent
    // means the thread renders identically for everyone, and a second
    // agent's reply doesn't jump sides depending on who opened the ticket.
    final onRight = !entry.isMessage;
    final grouped = _groupsWith(entry, prev);

    // Body ink per surface: the default body grey goes muddy on the blue
    // reply tint and on the note's warm hatch, so each carries its own.
    final ink = isNote
        ? t.noteBody
        : onRight
        ? t.bubbleOutboundInk
        : t.bubbleInboundInk;

    // The name / label / time strip lives *outside* the surface. Inside, it
    // set the surface's intrinsic width, so a one-word reply rendered as wide
    // as a full paragraph and the layout read as cards-pushed-right rather
    // than as bubbles. Out here the surface shrink-wraps its body, and short
    // messages finally look short.
    // Header parts in reading order for the left side. On the desk's side the
    // whole strip is reversed so the name still lands next to its avatar —
    // otherwise the timestamp sits against the face and the name drifts off
    // toward the middle of the column.
    final headerParts = <Widget>[
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
      // No REPLY / MESSAGE tag: by the time a row is drawn its type has been
      // stated three times over — which side it sits on, which tint it
      // carries, and which way its tail points. A note keeps its label
      // because the hatch is learned, not innate, and because getting a note
      // wrong is the one mistake on this screen that reaches a customer.
      if (isNote)
        Tooltip(
          message: 'Not visible to the requester',
          waitDuration: const Duration(milliseconds: 400),
          child: Text(
            'INTERNAL NOTE',
            style: ZebuTextStyles.eyebrow(
              context,
              color: t.note,
            ).copyWith(letterSpacing: 0.6),
          ),
        ),
    ];
    final ordered = onRight ? headerParts.reversed.toList() : headerParts;

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < ordered.length; i++) ...[
            if (i > 0) const SizedBox(width: ZebuSpacing.s2),
            ordered[i],
          ],
        ],
      ),
    );

    final body = _body(context, t, ink);

    // A note is a hatched, dashed card rather than a filled bubble. It sits
    // on the desk's side like a reply — it *was* written by the desk — but a
    // note that looks like a reply is a note that eventually gets sent as
    // one, so the surface has to stay unmistakable. Hatching is the one
    // texture nothing else in the app uses, which is what makes it survive
    // being seen out of the corner of the eye.
    // Shared by both surfaces: a speech-bubble outline with the tail on the
    // speaker's side. The tail is why the avatar sits at the *bottom* of the
    // row rather than beside the name — a tail that points at empty gutter is
    // worse than no tail at all.
    final shape = BubbleShape(tailOnRight: onRight);

    final surface = isNote
        ? HatchedCard(
            baseColor: t.noteHatchBase,
            stripeColor: t.noteHatchStripe,
            // No edge: every other surface in the thread lost its hairline
            // when both sides gained a fill, and a dashed outline on the one
            // remaining bordered card made it read as a form field. The hatch
            // is doing the warning on its own.
            shape: shape,
            padding: const EdgeInsets.symmetric(
              horizontal: ZebuSpacing.s4,
              vertical: ZebuSpacing.s3,
            ),
            child: body,
          )
        : Container(
            decoration: ShapeDecoration(
              // Fill only, no hairline. Once both sides carry a fill the
              // border is a second edge doing the first one's job, and the
              // pair stops reading as speech and starts reading as boxes.
              color: onRight ? t.bubbleOutbound : t.bubbleInbound,
              shape: shape,
            ),
            // ShapeDecoration already insets by the shape's dimensions, which
            // reserve the tail strip, so this is the copy padding only.
            padding: const EdgeInsets.symmetric(
              horizontal: ZebuSpacing.s4,
              vertical: ZebuSpacing.s3,
            ),
            child: body,
          );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        ZebuSpacing.s4,
        // A run reads as one block: tight between its rows, open before the
        // next speaker.
        grouped ? 3 : ZebuSpacing.s4,
        ZebuSpacing.s4,
        0,
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final gutter = (c.maxWidth * 0.12).clamp(0.0, _kBubbleGutter);
          final maxSurface = (c.maxWidth - gutter - _kAvatarSize - _kAvatarGap)
              .clamp(0.0, c.maxWidth);
          // Always occupied, but only painted once per run. A note's avatar
          // is warm rather than the author's hashed identity colour — on a
          // note, "this is private" outranks "this is Venkat".
          final avatarSlot = SizedBox(
            width: _kAvatarSize,
            child: grouped
                ? null
                : ZebuAvatar(
                    name: entry.poster,
                    fill: isNote ? t.noteAvatarBg : null,
                    ink: isNote ? t.note : null,
                  ),
          );
          return Row(
            // Bottom-aligned so the avatar meets the tail. The name and time
            // still sit above the bubble, so a tall message puts a little air
            // between the two — which is the Telegram / WhatsApp arrangement
            // and reads as the face belonging to the last thing said.
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: onRight
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              if (!onRight) ...[avatarSlot, const SizedBox(width: _kAvatarGap)],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxSurface),
                  child: Column(
                    // The header and the surface hang off the same edge — the
                    // one nearest the avatar — so a run of differently sized
                    // rows still has one straight side.
                    crossAxisAlignment: onRight
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [if (!grouped) header, surface],
                  ),
                ),
              ),
              if (onRight) ...[const SizedBox(width: _kAvatarGap), avatarSlot],
            ],
          );
        },
      ),
    );
  }

  /// Message text plus any attachment chips. Identical inside a bubble and
  /// inside a note card, so it is built once and handed to whichever surface
  /// wins.
  Widget _body(BuildContext context, ZebuTheme t, Color ink) {
    final html = entry.bodyHtml ?? entry.body ?? '';
    final plain = Fmt.stripHtml(html);
    final echo = _isAttachmentEcho(plain, entry.attachments);
    final hasFiles = entry.attachments.isNotEmpty;

    final clockStyle = ZebuTextStyles.small(
      context,
      color: t.textSlateMuted,
    ).withTabularNums();
    final clockText = entry.created == null ? null : Fmt.time(entry.created);

    final bodyStyle = ZebuTextStyles.body(
      context,
      color: ink,
    ).copyWith(height: 1.55);

    // The clock rides the end of the last line when it fits there, and drops
    // to its own line only when it doesn't — the WhatsApp behaviour. It works
    // by appending an invisible spacer the clock's own width to the text, so
    // the layout reserves the room, and then painting the real clock in the
    // corner the spacer just cleared. Only plain-text bodies qualify: an HTML
    // body can't take a trailing span, and a message with attachments has a
    // chip below the text for the clock to sit under anyway.
    final inline =
        clockText != null &&
        !echo &&
        !hasFiles &&
        !html.contains('<') &&
        plain.trim().isNotEmpty;

    if (inline) {
      final gap =
          _measureWidth(context, clockText, clockStyle) + ZebuSpacing.s3;
      return IntrinsicWidth(
        child: _Dated(
          created: entry.created,
          child: Stack(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: plain),
                    WidgetSpan(child: SizedBox(width: gap, height: 1)),
                  ],
                ),
                style: bodyStyle,
              ),
              // Positioned, so it costs the layout nothing beyond the spacer
              // above — the Stack sizes to the text alone.
              Positioned(
                right: 0,
                bottom: 1,
                child: Text(clockText, style: clockStyle),
              ),
            ],
          ),
        ),
      );
    }

    // Sizes the column to its widest child before the clock is right-aligned
    // inside it. Without this the `Align` below takes every pixel it is
    // offered, so a two-letter reply rendered as wide as the width cap. The
    // outer ConstrainedBox still caps it, so long copy wraps as before.
    return IntrinsicWidth(
      child: Column(
        // Body copy stays left-aligned on both sides — ragged-left paragraphs
        // are unreadable, and the row's position already carries direction.
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // osTicket writes "Attachment: <name>" as the body when a file is
          // sent with no message. Rendering that *and* the chip prints the same
          // filename twice, one line apart, which reads as a stutter.
          if (!echo) ...[
            // The exact timestamp hangs off the body text alone, not the whole
            // surface — wrapping the surface meant hovering an attachment
            // popped the date tooltip over the thing you were trying to see.
            _Dated(
              created: entry.created,
              child: plain.trim().isEmpty
                  ? Text('(no content)', style: ZebuTextStyles.small(context))
                  : html.contains('<')
                  ? _HtmlBody(html: html)
                  : Text(plain, style: bodyStyle),
            ),
            if (hasFiles) const SizedBox(height: ZebuSpacing.s3),
          ],
          if (hasFiles)
            Wrap(
              spacing: ZebuSpacing.s2,
              runSpacing: ZebuSpacing.s2,
              children: [
                for (final a in entry.attachments)
                  _AttachmentChip(attachment: a),
              ],
            ),
          if (clockText != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Text(clockText, style: clockStyle),
              ),
            ),
        ],
      ),
    );
  }

  /// Laid-out width of [text] in [style], for reserving space the layout
  /// engine can't be asked for directly.
  static double _measureWidth(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }
}

/// One attachment: an inline preview for images, a compact chip for
/// everything else.
///
/// Images get the preview because a screenshot *is* the message — a customer
/// reporting a bug sends a picture of it, and forcing a round-trip to a new
/// browser tab to see it is the single most expensive interaction in the
/// thread. Non-image types have nothing to show until they're opened, so a
/// chip is the honest representation.
class _AttachmentChip extends StatefulWidget {
  const _AttachmentChip({required this.attachment});
  final Attachment attachment;

  @override
  State<_AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends State<_AttachmentChip> {
  /// Set once [Image.network] fails, so the row falls back to the chip
  /// permanently instead of retrying the broken URL on every rebuild.
  bool _previewFailed = false;

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

  /// Badge tint, keyed off the file type. A red PDF and a green spreadsheet
  /// are findable in a long thread the way a uniformly blue tile is not — the
  /// eye sorts by colour before it reads a filename.
  Color _badgeTone(ZebuTheme t) {
    final m = widget.attachment.type ?? '';
    if (m.contains('pdf')) return t.danger;
    if (m.startsWith('image/')) return t.accent;
    if (m.contains('sheet') || m.contains('excel')) return ZebuTheme.success;
    if (m.contains('word') || m.contains('document')) return t.accent;
    return t.iconMuted;
  }

  /// Short uppercase extension for the badge — PDF, XLSX, PNG. Null when the
  /// filename has none, in which case the glyph stands in.
  String? get _ext {
    final n = widget.attachment.name;
    final dot = n.lastIndexOf('.');
    if (dot <= 0 || n.length - dot > 6) return null;
    return n.substring(dot + 1).toUpperCase();
  }

  Future<void> _open() async {
    final a = widget.attachment;
    final url = a.downloadUrl ?? a.streamUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    // `downloadUrl` is the signed absolute `file.php` URL — it carries its own
    // HMAC, so an <img> can fetch it without our bearer token. `streamUrl`
    // needs an Authorization header and so can't be handed to Image.network.
    final canPreview = a.isImage && a.downloadUrl != null && !_previewFailed;
    return MouseRegion(
      // Cursor only, no hover styling. An attachment sits inside a tinted
      // bubble, so a hover fill would be a third surface colour flickering
      // inside a second one — the pointer is affordance enough.
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _open,
        child: canPreview ? _buildPreview(context) : _buildChip(context),
      ),
    );
  }

  /// Image: a media card — the picture itself, with a caption strip under it
  /// carrying the name, size, and open-externally affordance.
  Widget _buildPreview(BuildContext context) {
    final t = ZebuTheme.of(context);
    final a = widget.attachment;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border.all(color: t.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(ZebuRadius.rSm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _kPreviewWidth,
              maxHeight: _kPreviewHeight,
            ),
            child: Image.network(
              a.downloadUrl!,
              fit: BoxFit.cover,
              width: _kPreviewWidth,
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : Container(
                      width: _kPreviewWidth,
                      height: _kPreviewHeight,
                      color: t.surfaceMuted,
                      alignment: Alignment.center,
                      child: const DotsLoader(),
                    ),
              // A blocked or expired URL must not leave a broken-image box in
              // the thread — drop to the chip, which still opens fine.
              errorBuilder: (context, _, _) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _previewFailed = true);
                });
                return const SizedBox.shrink();
              },
            ),
          ),
          Container(
            width: _kPreviewWidth,
            color: t.surfaceMuted,
            padding: const EdgeInsets.symmetric(
              horizontal: ZebuSpacing.s2,
              vertical: 6,
            ),
            child: _caption(context),
          ),
        ],
      ),
    );
  }

  /// Everything else: icon tile, name, size, open glyph.
  Widget _buildChip(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      width: _kChipWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: ZebuSpacing.s2 + 2,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border.all(color: t.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(ZebuRadius.rSm),
      ),
      child: Row(
        children: [
          _badge(context),
          const SizedBox(width: ZebuSpacing.s3),
          _caption(context),
        ],
      ),
    );
  }

  /// 32x32 type tile: the extension in a tinted square, or the glyph when the
  /// filename has none.
  Widget _badge(BuildContext context) {
    final t = ZebuTheme.of(context);
    final tone = _badgeTone(t);
    final ext = _ext;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(5),
      ),
      child: ext == null
          ? Icon(_icon, size: 17, color: tone)
          : Text(
              // Four characters is the widest that fits without shrinking
              // past legibility.
              ext.length > 4 ? ext.substring(0, 4) : ext,
              style: ZebuTextStyles.caption(
                context,
                color: zebuOnTint(tone, t),
                fontWeight: ZebuFonts.bold,
              ).copyWith(fontSize: ext.length > 3 ? 8 : 9),
            ),
    );
  }

  /// Name over size, with the download affordance trailing. Two lines rather
  /// than one row: at a fixed chip width the filename gets the whole line
  /// instead of competing with the size for it, so far less of it is lost to
  /// the ellipsis.
  Widget _caption(BuildContext context) {
    final t = ZebuTheme.of(context);
    final a = widget.attachment;
    return Expanded(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // One ellipsis, at the end, plus the full name on hover.
                // Shortening the string ourselves *and* letting the layout
                // clip it produced two ellipses in the same filename
                // ("ChatGPT Image...36_32 PM...."), which reads as a bug.
                // Losing the extension costs nothing now that the badge
                // states the type.
                Tooltip(
                  message: a.name,
                  waitDuration: const Duration(milliseconds: 400),
                  child: Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: ZebuTextStyles.small(
                      context,
                      color: t.textPrimary,
                      fontWeight: ZebuFonts.semiBold,
                    ),
                  ),
                ),
                if (a.size != null)
                  Text(
                    Fmt.fileSize(a.size),
                    style: ZebuTextStyles.caption(
                      context,
                      color: t.textSlateMuted,
                    ).withTabularNums(),
                  ),
              ],
            ),
          ),
          const SizedBox(width: ZebuSpacing.s2),
          Icon(Icons.download_outlined, size: 16, color: t.iconMuted),
        ],
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
