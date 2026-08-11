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
import '../../../widgets/web/detail_fields.dart';
import '../../../widgets/web/panel_header.dart';
import '../../../widgets/web/status_badge.dart';
import '../../../widgets/web/status_pill.dart';
import '../../../res/zebu_status_colors.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';
import '../../../widgets/web/thread_view.dart';

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
          ...zebuThreadItems(_thread),
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
                  ...zebuThreadItems(_thread),
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
          child: ZebuRailToggle(
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
            Expanded(
              child: ZebuPanelTitle(
                id: ticket!.number,
                title: ticket!.subject,
                meta: ticket!.requester,
              ),
            ),
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
      if (sidebar) const ZebuFieldGroupLabel('Assignment', first: true),
      ZebuFieldRow(
        rowKey: assigneeRowKey,
        icon: Icons.person_outline,
        label: 'Assignee',
        sidebar: sidebar,
        onTap: onAssigneeTap,
        value: assignee.isEmpty
            ? const ZebuEmptyValue(label: 'Unassigned')
            : ZebuTextValue(
                text: assignee,
                tone: sidebar ? t.linkSlate : t.accent,
                linked: true,
              ),
      ),
      ZebuFieldRow(
        rowKey: departmentRowKey,
        icon: Icons.business_outlined,
        label: 'Department',
        sidebar: sidebar,
        onTap: onDepartmentTap,
        value: department.isEmpty
            ? const ZebuEmptyValue(label: 'None')
            : ZebuTextValue(
                text: department,
                tone: sidebar ? t.linkSlate : t.accent,
                linked: true,
              ),
      ),
      if (sidebar) const ZebuFieldGroupLabel('Ticket'),
      ZebuFieldRow(
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
      ZebuFieldRow(
        rowKey: priorityRowKey,
        icon: Icons.priority_high,
        label: 'Priority',
        sidebar: sidebar,
        onTap: onPriorityTap,
        // Priority stays a tinted pill rather than a StatusBadge: it is a
        // different vocabulary (Low..Emergency), and giving it the status
        // system's fills would put two solid-red badges in adjacent rows.
        value: priority.isEmpty
            ? const ZebuEmptyValue(label: 'No priority')
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
        const ZebuFieldGroupLabel('Requester'),
      if (requester.isNotEmpty)
        ZebuFieldRow(
          icon: Icons.alternate_email,
          label: 'Requester',
          sidebar: sidebar,
          value: ZebuTextValue(
            text: requester,
            tone: sidebar ? t.textSlate : null,
          ),
        ),
      if (userEmail.isNotEmpty)
        ZebuFieldRow(
          icon: Icons.mail_outline,
          label: 'Email',
          sidebar: sidebar,
          value: ZebuTextValue(
            text: userEmail,
            tone: sidebar ? t.textSlate : null,
          ),
        ),
      if (sidebar) const ZebuFieldGroupLabel('Schedule'),
      if (ticket.due != null)
        ZebuFieldRow(
          icon: Icons.schedule,
          label: 'Due',
          sidebar: sidebar,
          value: ZebuTextValue(
            text: Fmt.dateTime(ticket.due),
            tone: ticket.isOverdue ? t.danger : (sidebar ? t.textSlate : null),
          ),
        ),
      if (sla != null && slaLabel.isNotEmpty)
        ZebuFieldRow(
          icon: Icons.hourglass_bottom,
          label: 'SLA',
          sidebar: sidebar,
          value: sidebar
              ? ZebuTextValue(
                  text: slaLabel,
                  tone: zebuOnTint(
                    sla.isOverdue ? t.danger : ZebuTheme.warning,
                    t,
                  ),
                )
              : ZebuStatusValuePill(
                  label: slaLabel,
                  color: sla.isOverdue ? t.danger : ZebuTheme.warning,
                ),
        ),
      ZebuFieldRow(
        icon: Icons.event_outlined,
        label: 'Created',
        sidebar: sidebar,
        value: ZebuTextValue(
          text: Fmt.dateTime(ticket.created),
          tone: sidebar ? t.textSlate : null,
        ),
      ),
      if (ticket.updated != null)
        ZebuFieldRow(
          icon: Icons.update,
          label: 'Updated',
          sidebar: sidebar,
          value: ZebuTextValue(
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
                      ZebuRailToggle(
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
    // [ZebuTextValue] rows read at 13 px — matching the tighter single-column
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
