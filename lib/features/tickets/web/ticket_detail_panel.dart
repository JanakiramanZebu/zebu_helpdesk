import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format.dart';
import '../../../models/common.dart';
import '../../../models/meta.dart';
import '../../../models/ticket.dart';
import '../../../providers.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/comment_composer.dart';
import '../../../widgets/states.dart';
import '../../../widgets/web/status_pill.dart';
import '../../dashboard/web/_tokens.dart';

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
const double _kAvatarSize = 32;

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

/// Row height for field rows inside the two-column sidebar. Bumped from
/// the 30 px single-column rhythm so the sidebar reads with more
/// breathing room — 40 px lets labels + values use the larger 14 px body
/// size without crowding the icon column.
const double _kSidebarRowHeight = 40;

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
    final t = WebTokens.of(context);
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

  Widget _buildBody(WebTokens t) {
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

    return Column(
      children: [
        _Header(
          ticket: ticket,
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
              if (wide) return _buildWide(t, ticket);
              return _buildNarrow(t, ticket);
            },
          ),
        ),
        CommentComposer(onSend: _sendReply, disabled: _acting),
      ],
    );
  }

  /// Narrow single-column layout: fields card on top, activity feed below,
  /// composer at the bottom. Same layout the panel shipped with before the
  /// two-column split, kept for the sub-780 px slot the panel gets when the
  /// list underneath is still visible on smaller viewports.
  Widget _buildNarrow(WebTokens t, Ticket ticket) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: WebTokens.s3),
        _FieldsTable(
          ticket: ticket,
          sidebar: false,
          statusRowKey: _statusRowKey,
          priorityRowKey: _priorityRowKey,
          assigneeRowKey: _assigneeRowKey,
          departmentRowKey: _departmentRowKey,
          onStatusTap: _pickTicketStatus,
          onPriorityTap: _pickTicketPriority,
          onAssigneeTap: _pickTicketAssignee,
          onDepartmentTap: _pickTicketDepartment,
        ),
        const SizedBox(height: WebTokens.s2),
        const _ActivityHeader(),
        if (_thread.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WebTokens.s6),
            child: Center(
              child: Text('No messages yet', style: t.bodySm),
            ),
          )
        else ...[
          for (final e in _thread) _ThreadRow(entry: e),
          const SizedBox(height: WebTokens.s3),
        ],
      ],
    );
  }

  /// Two-column layout used at ≥ [_kTwoColumnBreakpoint] px: activity feed
  /// on the left (grows to fill), fields sidebar on the right at
  /// [_kFieldsSidebarWidth]. A hairline seam separates the two columns —
  /// matches the reference layout where the details block sits as a fixed
  /// rail alongside the message thread.
  Widget _buildWide(WebTokens t, Ticket ticket) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (_thread.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: WebTokens.s8),
                  child: Center(
                    child: Text('No messages yet', style: t.bodySm),
                  ),
                )
              else ...[
                const SizedBox(height: WebTokens.s3),
                for (final e in _thread) _ThreadRow(entry: e),
                const SizedBox(height: WebTokens.s3),
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
              padding: const EdgeInsets.symmetric(vertical: WebTokens.s4),
              children: [
                _FieldsTable(
                  ticket: ticket,
                  sidebar: true,
                  statusRowKey: _statusRowKey,
                  priorityRowKey: _priorityRowKey,
                  assigneeRowKey: _assigneeRowKey,
                  departmentRowKey: _departmentRowKey,
                  onStatusTap: _pickTicketStatus,
                  onPriorityTap: _pickTicketPriority,
                  onAssigneeTap: _pickTicketAssignee,
                  onDepartmentTap: _pickTicketDepartment,
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
    required this.onClose,
    required this.onMenu,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });
  final Ticket? ticket;
  final VoidCallback onClose;
  final Future<void> Function(String value)? onMenu;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        WebTokens.s4,
        WebTokens.s3,
        WebTokens.s4,
        WebTokens.s3,
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
            Expanded(child: Text('Loading…', style: t.cardName))
          else ...[
            _NumberChip(number: ticket!.number),
            const SizedBox(width: WebTokens.s3),
            Expanded(
              child: Text(
                ticket!.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.pageTitle,
              ),
            ),
          ],
          const SizedBox(width: WebTokens.s3),
          if (ticket != null && onMenu != null) ...[
            _ActionsBtn(ticket: ticket!, onSelected: onMenu!),
            const SizedBox(width: WebTokens.s2),
          ],
          if (onToggleFullscreen != null) ...[
            _IconBtn(
              icon: isFullscreen
                  ? Icons.close_fullscreen
                  : Icons.open_in_full,
              tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
              onTap: onToggleFullscreen!,
            ),
            const SizedBox(width: WebTokens.s2),
          ],
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

/// Small pill that reads `#12345` — sits next to the title as a breadcrumb
/// prefix, replacing the previous stacked `#number` above the subject.
class _NumberChip extends StatelessWidget {
  const _NumberChip({required this.number});
  final String number;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.bgTertiary,
        borderRadius: BorderRadius.circular(WebTokens.s1),
      ),
      child: Text(
        '#$number',
        style: t.bodySm
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
  const _ActionsBtn({required this.ticket, required this.onSelected});
  final Ticket ticket;
  final Future<void> Function(String value) onSelected;

  @override
  State<_ActionsBtn> createState() => _ActionsBtnState();
}

class _ActionsBtnState extends State<_ActionsBtn> {
  bool _hover = false;

  Future<void> _open() async {
    final ticket = widget.ticket;
    final chosen = await showAppDropdown<String>(
      context,
      entries: [
        const AppDropdownHeader<String>('Ticket actions'),
        const AppDropdownItem(
          value: 'status',
          label: 'Change status',
          icon: Icons.flag_outlined,
        ),
        const AppDropdownItem(
          value: 'priority',
          label: 'Set priority',
          icon: Icons.priority_high,
        ),
        const AppDropdownItem(
          value: 'assign',
          label: 'Assign',
          icon: Icons.person_add_alt_outlined,
        ),
        const AppDropdownItem(
          value: 'transfer',
          label: 'Transfer dept',
          icon: Icons.swap_horiz,
        ),
        const AppDropdownDivider(),
        if ((ticket.assignee ?? '').isEmpty)
          const AppDropdownItem(
            value: 'claim',
            label: 'Claim',
            icon: Icons.pan_tool_outlined,
          )
        else
          const AppDropdownItem(
            value: 'release',
            label: 'Release',
            icon: Icons.logout,
          ),
      ],
    );
    if (chosen != null) await widget.onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
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
              borderRadius: BorderRadius.circular(WebTokens.rSm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Actions',
                  style: t.bodySm.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w600,
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
    this.destructive = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  /// When true, hover tints the button danger-red instead of the neutral
  /// hover fill. Used for close/destroy actions.
  final bool destructive;

  @override
  State<_IconBtn> createState() => _IconBtnState();
}

class _IconBtnState extends State<_IconBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
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
            borderRadius: BorderRadius.circular(WebTokens.rSm),
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

  final ValueChanged<BuildContext> onStatusTap;
  final ValueChanged<BuildContext> onPriorityTap;
  final ValueChanged<BuildContext> onAssigneeTap;
  final ValueChanged<BuildContext> onDepartmentTap;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
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
                tone: t.accent,
                linked: true,
              ),
      ),
      _FieldRow(
        rowKey: statusRowKey,
        icon: Icons.flag_outlined,
        label: 'Status',
        sidebar: sidebar,
        onTap: onStatusTap,
        value: _StatusValuePill(
          label: ticket.statusName,
          color: _statusTone(ticket, t),
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
            : _StatusValuePill(
                label: _titleCase(priority),
                color: _priorityTone(priority, t),
                icon: Icons.flag_rounded,
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
                tone: t.accent,
                linked: true,
              ),
      ),
      if (requester.isNotEmpty)
        _FieldRow(
          icon: Icons.alternate_email,
          label: 'Requester',
          sidebar: sidebar,
          value: _TextValue(text: requester),
        ),
      if (userEmail.isNotEmpty)
        _FieldRow(
          icon: Icons.mail_outline,
          label: 'Email',
          sidebar: sidebar,
          value: _TextValue(text: userEmail),
        ),
      if (ticket.due != null)
        _FieldRow(
          icon: Icons.schedule,
          label: 'Due',
          sidebar: sidebar,
          value: _TextValue(
            text: Fmt.dateTime(ticket.due),
            tone: ticket.isOverdue ? t.danger : null,
          ),
        ),
      if (sla != null && slaLabel.isNotEmpty)
        _FieldRow(
          icon: Icons.hourglass_bottom,
          label: 'SLA',
          sidebar: sidebar,
          value: _StatusValuePill(
            label: slaLabel,
            color: sla.isOverdue ? t.danger : WebTokens.warning,
          ),
        ),
      _FieldRow(
        icon: Icons.event_outlined,
        label: 'Created',
        sidebar: sidebar,
        value: _TextValue(text: Fmt.dateTime(ticket.created)),
      ),
      if (ticket.updated != null)
        _FieldRow(
          icon: Icons.update,
          label: 'Updated',
          sidebar: sidebar,
          value: _TextValue(text: Fmt.dateTime(ticket.updated)),
        ),
    ];

    // Sidebar mode: wrap the field rows in a single elevated card so every
    // row (clickable or not) sits on the same white ground against the
    // panel's warm-paper bg. Subtle shadow lifts the rail off the page.
    if (sidebar) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          WebTokens.s3,
          0,
          WebTokens.s3,
          WebTokens.s3,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.bgElevated,
            borderRadius: BorderRadius.circular(WebTokens.rMd),
            border: Border.all(color: t.borderSubtle, width: 1),
            boxShadow: WebTokens.shadowXs,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WebTokens.s3,
              vertical: WebTokens.s2,
            ),
            child: DefaultTextStyle.merge(
              style: t.bodyBase.copyWith(color: t.textPrimary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: cells,
              ),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: WebTokens.s4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.bgElevated,
          borderRadius: BorderRadius.circular(WebTokens.rMd),
          border: Border.all(color: t.borderSubtle, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s3,
            vertical: WebTokens.s2,
          ),
          child: DefaultTextStyle.merge(
            style: t.bodySm.copyWith(color: t.textPrimary),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: cells,
            ),
          ),
        ),
      ),
    );
  }

  static Color _statusTone(Ticket ticket, WebTokens t) {
    if (ticket.isOverdue) return t.danger;
    if (ticket.isClosed) return t.textSecondary;
    return WebTokens.success;
  }

  static Color _priorityTone(String name, WebTokens t) {
    final n = name.toLowerCase();
    if (n.contains('emergency') || n.contains('urgent')) return t.danger;
    if (n.contains('high')) return WebTokens.warning;
    if (n.contains('low')) return WebTokens.success;
    if (n.contains('normal')) return WebTokens.info;
    return WebTokens.info;
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
    final t = WebTokens.of(context);
    final clickable = widget.onTap != null;
    // Same hover treatment the tickets-list rows use: single outer
    // AnimatedContainer with an 80 ms fade between `bgElevated` (default)
    // and `bgHover`. No accent stripe. Caret tints accent on hover so the
    // click-to-edit affordance stays visible on clickable rows.
    // On clickable rows the value + caret sit inside an outlined pill so
    // the field reads as a proper select input (annotated reference: the
    // "Unassigned" cell drawn as a bordered dropdown trigger). Non-
    // clickable rows keep plain text so the read-only signal is clear.
    final Widget valueSlot;
    if (clickable) {
      // Key on the pill (not the row) — dropdown popups anchor here so
      // they land under the value, aligned with the trigger's left edge
      // and width.
      final Widget pill = KeyedSubtree(
        key: widget.rowKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
      // In sidebar mode the pill flexes to fill remaining row width — the
      // 320 px rail is too narrow for the 280 px fixed pill used in the
      // wider single-column card layout.
      valueSlot = widget.sidebar
          ? Expanded(child: pill)
          : SizedBox(width: _kFieldValueWidth, child: pill);
    } else {
      valueSlot = Expanded(child: widget.value);
    }
    // Sidebar rows sit on a taller [_kSidebarRowHeight] rhythm and bump
    // the label to the 14 px `bodyBase` size so the fields rail reads as
    // its own scannable column, not a squeezed footnote.
    final rowHeight = widget.sidebar ? _kSidebarRowHeight : 30.0;
    final labelStyle = widget.sidebar
        ? t.bodyBase.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w500,
          )
        : t.bodySm.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w500,
          );
    // Leading icons removed — labels alone carry the meaning and the row
    // reads cleaner without the credential glyphs (person / building /
    // flag / bang / calendar).
    final row = SizedBox(
      height: rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WebTokens.s1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _kFieldLabelWidth,
              child: Text(widget.label, style: labelStyle),
            ),
            // Breathing room between the label column and the value.
            // Without it the outlined pill sits flush against the label
            // text, which reads as crowded.
            const SizedBox(width: WebTokens.s3),
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
        // Anchor the popup on the pill (via [rowKey]) rather than this
        // row's outer context, so the dropdown lands directly under the
        // trigger regardless of which part of the row was clicked.
        onTap: () => widget.onTap!(
          widget.rowKey?.currentContext ?? context,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          color: t.bgElevated,
          child: row,
        ),
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
    final t = WebTokens.of(context);
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

/// StatusPill wrapper used inside a field row — same treatment tickets
/// list uses so the value keeps its colored dot indicator.
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
    final t = WebTokens.of(context);
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.bodySm.copyWith(
        color: t.textSecondary,
        fontWeight: FontWeight.w400,
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
    final t = WebTokens.of(context);
    // No divider under the label — each thread entry below sits inside
    // its own card, so a hairline here would double up as visual noise
    // between the header and the first card. Top hairline stays to
    // separate the activity block from the fields grid above.
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WebTokens.s4,
        vertical: WebTokens.s3,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(
          top: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      child: Text(
        'Activity',
        style: t.cardName.copyWith(color: t.textPrimary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Thread entry — actor-avatar column on the left, body indented under the
// poster name so the whole activity feed reads as one column of entries.
// ---------------------------------------------------------------------------

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
    final t = WebTokens.of(context);
    final entry = widget.entry;
    final isNote = entry.isNote;
    final isResponse = entry.isResponse;
    final tone = isNote
        ? WebTokens.warning
        : (isResponse ? t.accent : t.textSecondary);
    final typeLabel = isNote
        ? 'NOTE'
        : (isResponse ? 'REPLY' : 'MESSAGE');
    final html = entry.bodyHtml ?? entry.body ?? '';
    final plain = Fmt.stripHtml(html);

    // Each thread entry is its own card — outer margin gives space
    // between messages, rounded hairline border reads like an email
    // client row. No border between cards (the card edge itself is the
    // divider). Hover slightly deepens the border + adds a whisper-quiet
    // lift so the click affordance stays discoverable.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTokens.s4,
        WebTokens.s3,
        WebTokens.s4,
        0,
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: t.bgElevated,
            borderRadius: BorderRadius.circular(WebTokens.rMd),
            border: Border.all(
              color: _hover ? t.borderDefault : t.borderSubtle,
              width: 1,
            ),
            boxShadow: _hover ? WebTokens.shadowSm : WebTokens.shadowXs,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WebTokens.s4,
            vertical: WebTokens.s3,
          ),
          // Stack lets the timestamp float in the card's top-right corner
          // regardless of the body content beneath it, matching the
          // reference email/thread cards.
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ActorAvatar(name: entry.poster),
                  const SizedBox(width: WebTokens.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                entry.poster,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.cardName
                                    .copyWith(color: t.textPrimary),
                              ),
                            ),
                            const SizedBox(width: WebTokens.s2),
                            _TypeTag(label: typeLabel, tone: tone),
                            // Reserve room for the pinned timestamp so
                            // poster/type never overlap it on long names.
                            const SizedBox(width: 96),
                          ],
                        ),
                        const SizedBox(height: WebTokens.s2),
                        if (plain.trim().isEmpty)
                          Text('(no content)', style: t.bodySm)
                        else if (html.contains('<'))
                          _HtmlBody(html: html)
                        else
                          Text(
                            plain,
                            style: t.bodyBase.copyWith(height: 1.5),
                          ),
                        if (entry.attachments.isNotEmpty) ...[
                          const SizedBox(height: WebTokens.s3),
                          Wrap(
                            spacing: WebTokens.s2,
                            runSpacing: WebTokens.s2,
                            children: [
                              for (final a in entry.attachments)
                                _AttachmentChip(attachment: a),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (entry.created != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Text(Fmt.ago(entry.created), style: t.tinyLabel),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Deterministic color palette for actor avatars — index into this by a
/// stable hash of the poster name. Values picked from the reference feed
/// palette so avatars read as consistent product colors, not random tints.
const _kAvatarPalette = <Color>[
  Color(0xFFF6B93B), // amber
  Color(0xFF5DADE2), // sky
  Color(0xFF58D68D), // green
  Color(0xFFAF7AC5), // lavender
  Color(0xFFF5A623), // orange
  Color(0xFF48C9B0), // teal
  Color(0xFFEC7063), // coral
  Color(0xFF5D6D7E), // slate
];

/// 32-px colored circle with up to two initials — same shape and rhythm as
/// the reference activity feed. Hue is derived deterministically from the
/// name so the same actor keeps the same avatar color across reloads.
class _ActorAvatar extends StatelessWidget {
  const _ActorAvatar({required this.name});
  final String name;

  static String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '·';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  static Color _color(String s) {
    if (s.isEmpty) return _kAvatarPalette[0];
    var hash = 0;
    for (final c in s.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return _kAvatarPalette[hash % _kAvatarPalette.length];
  }

  @override
  Widget build(BuildContext context) {
    final bg = _color(name);
    return Container(
      width: _kAvatarSize,
      height: _kAvatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        _initials(name),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          height: 1.0,
          letterSpacing: 0.2,
        ),
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
    final t = WebTokens.of(context);
    return Text(label, style: t.tinyLabel.copyWith(color: tone));
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
    final t = WebTokens.of(context);
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
            horizontal: WebTokens.s3,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: _hover ? t.accentSoft : t.bgTertiary,
            border: Border.all(
              color: _hover ? t.accent : t.borderSubtle,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _icon,
                size: 14,
                color: _hover ? t.accent : t.textSecondary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySm.copyWith(
                    color: _hover ? t.accent : t.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (a.size != null) ...[
                const SizedBox(width: 6),
                Text(
                  Fmt.fileSize(a.size),
                  style: t.tinyLabel.withTabularNums(),
                ),
              ],
              const SizedBox(width: 6),
              Icon(
                Icons.open_in_new,
                size: 12,
                color: _hover ? t.accent : t.textSecondary,
              ),
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
    final t = WebTokens.of(context);
    return ClipRect(
      child: HtmlWidget(
        html,
        textStyle: t.bodyBase.copyWith(height: 1.5),
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
                'color': '#0037B7', // WebTokens.accent
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
