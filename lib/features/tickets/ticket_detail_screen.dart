import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/assets.dart';
import '../../data/agent_directory.dart';
import '../../core/format.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../models/common.dart';
import '../../models/me.dart';
import '../../models/meta.dart';
import '../../models/ticket.dart';
import '../../providers.dart';
import '../../widgets/action_menu.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/date_picker_sheet.dart';
import '../../widgets/message_composer.dart';
import '../../widgets/pickers.dart';
import '../../widgets/reassign_dialog.dart';
import '../../widgets/states.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/tags_dialog.dart';
import '../../widgets/thread_entry_edit.dart';
import 'widgets/edit_field_dialog.dart';
import 'widgets/edit_ticket_sheet.dart';
import 'widgets/thread_entry_tile.dart';

/// Per-agent action gates for a ticket, ported from osTicket's
/// `Ticket::checkStaffPerm()` (`include/class.ticket.php`). The backend enforces
/// these on every mutating `/tickets/*` endpoint (403 otherwise); mirroring them
/// here hides the affordances an agent can't use — matching the SCP rule that a
/// ticket "cannot be edited by others". Visibility is already granted (the
/// detail loaded), so only the per-department role permission matters.
class _TicketCaps {
  const _TicketCaps({
    this.canEdit = false,
    this.canAssign = false,
    this.canRelease = false,
    this.canTransfer = false,
    this.canRefer = false,
    this.canLink = false,
    this.canMerge = false,
    this.canMarkAnswered = false,
    this.canClose = false,
    this.canReply = false,
    this.canDelete = false,
    this.canBan = false,
    this.canCreateTask = false,
  });

  final bool canEdit; // ticket.edit — priority, owner, topic, due, fields, tags
  final bool canAssign; // ticket.assign — assign, assign-team, claim
  final bool canRelease; // ticket.release
  final bool canTransfer; // ticket.transfer
  final bool canRefer; // ticket.refer
  final bool canLink; // ticket.link
  final bool canMerge; // ticket.merge
  final bool canMarkAnswered; // ticket.markanswered
  final bool canClose; // ticket.close
  final bool canReply; // ticket.reply
  final bool canDelete; // ticket.delete
  final bool canBan; // emails.banlist (global perm, not dept-scoped)
  final bool canCreateTask; // task.create on this ticket's dept

  /// `/tickets/{id}/status` accepts PERM_CLOSE **or** PERM_EDIT.
  bool get canChangeStatus => canClose || canEdit;

  /// `/tickets/{id}/note` accepts PERM_REPLY **or** PERM_EDIT.
  bool get canNote => canReply || canEdit;

  /// `/tickets/{id}/mark` accepts PERM_MARKANSWERED (answered) — the overdue
  /// variant and dept managers fall through to edit-level access.
  bool get canMark => canMarkAnswered || canEdit;

  factory _TicketCaps.from(Me? me, Ticket? ticket) {
    if (me == null || ticket == null) return const _TicketCaps();
    final d = ticket.departmentId;
    return _TicketCaps(
      canEdit: me.canOn('ticket.edit', d),
      canAssign: me.canOn('ticket.assign', d),
      canRelease: me.canOn('ticket.release', d),
      canTransfer: me.canOn('ticket.transfer', d),
      canRefer: me.canOn('ticket.refer', d),
      canLink: me.canOn('ticket.link', d),
      canMerge: me.canOn('ticket.merge', d),
      canMarkAnswered: me.canOn('ticket.markanswered', d),
      canClose: me.canOn('ticket.close', d),
      canReply: me.canOn('ticket.reply', d),
      canDelete: me.canOn('ticket.delete', d),
      canBan: me.can('emails.banlist'),
      canCreateTask: me.canOn('task.create', d),
    );
  }
}

class TicketDetailScreen extends ConsumerStatefulWidget {
  const TicketDetailScreen({
    super.key,
    required this.ticketId,
    this.initialTab = 0,
  });
  final int ticketId;

  /// Tab to open on (0 Conversation, 1 Details, 2 Activity). The inbox's
  /// "View All Activity" link lands straight on the Activity tab.
  final int initialTab;

  @override
  ConsumerState<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends ConsumerState<TicketDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTab,
  );
  // Controls the outer (header) scroll view of the NestedScrollView, so its
  // offset tells us exactly how far the collapsing header has scrolled away.
  final ScrollController _headerScroll = ScrollController();

  Ticket? _ticket;
  List<ThreadEntry> _thread = [];
  List<ThreadEvent> _events = [];
  // Side-data the ticket payload doesn't carry: the web shows both on the
  // ticket page, the API serves them from their own endpoints.
  List<Tag> _tags = [];
  int? _collaborators;
  // The topic's form definition. The ticket payload's `custom_fields` is a flat
  // {label: value} map, so it can't say which answers are *required* - only
  // this endpoint does, and the Details tab needs it to flag the blanks the
  // web marks with a warning triangle.
  List<TicketField> _fields = const [];
  // Set when the server refuses a due-date edit because an SLA plan drives it
  // - a backend that doesn't publish the lock flag still tells us this way.
  bool _dueLockedByServer = false;
  // Whether the ticket's SLA plan is enabled, resolved from the plan list when
  // the payload names a plan but doesn't say. osTicket happily attaches a
  // DISABLED plan, which computes nothing.
  bool? _slaActive;
  Object? _error;
  bool _loading = true;
  // The conversation and the activity log load independently of the ticket, so
  // a slow or failing one no longer holds the whole screen on the spinner -
  // the web's ticket page renders its info panel the same way, without waiting
  // on the thread. Each carries its own spinner + error/Retry.
  Object? _threadError;
  Object? _eventsError;
  bool _threadLoading = false;
  bool _eventsLoading = false;
  bool _acting = false;
  bool _subjectInBar = false;
  // Message the composer is quoting (set from a bubble's long-press → Reply).
  ThreadEntry? _replyTo;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_onTab);
    _headerScroll.addListener(_onHeaderScroll);
    _load();
  }

  void _onTab() {
    if (mounted) setState(() {}); // toggle the composer per active tab
  }

  /// Whether the composer (only shown for the Conversation tab, index 0) should
  /// be visible. Uses the controller's live [animation] value rather than
  /// [index] so the field hides the instant a swipe starts moving away â€” a
  /// small threshold means it disappears as soon as the drag begins, matching
  /// the immediate hide you get when tapping another tab.
  bool get _onConversationTab => (_tabs.animation?.value ?? 0) < 0.05;

  // Show the subject in the app bar once the collapsing header (which holds
  // the subject) has scrolled behind the pinned app bar.
  void _onHeaderScroll() {
    final show = _headerScroll.offset > 28;
    if (show != _subjectInBar && mounted) {
      setState(() => _subjectInBar = show);
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTab);
    _tabs.dispose();
    _headerScroll.dispose();
    super.dispose();
  }

  // [silent] refreshes the data in place without flashing the full-screen
  // loader â€” used after sending a message so the conversation just updates.
  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    final repo = ref.read(ticketsRepositoryProvider);
    // Kicked off first so they overlap the main loads. Each is optional: a
    // failure (no permission, older backend) just drops its row.
    final tagsF = _sideLoad(() => repo.tags(widget.ticketId), const <Tag>[]);
    final collabF = _sideLoad(
      () => repo.collaborators(widget.ticketId),
      const <Collaborator>[],
    );
    final fieldsF = _sideLoad(
      () => repo.fields(widget.ticketId),
      const <TicketField>[],
    );
    final Ticket ticket;
    try {
      ticket = await repo.get(widget.ticketId);
    } catch (e) {
      // Only the ticket itself is fatal to the screen.
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
      return;
    }
    if (!mounted) return;
    // The ticket alone is enough to open the screen, so show it now and let
    // the conversation / activity fill in behind it.
    setState(() {
      _ticket = ticket;
      _slaActive = null;
      _loading = false;
    });
    unawaited(_loadThread());
    unawaited(_loadEvents());
    final tags = await tagsF;
    final collaborators = await collabF;
    final fields = await fieldsF;
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _collaborators = collaborators.length;
      _fields = fields;
    });
    await _resolveSlaActive(ticket);
  }

  /// Loads the conversation on its own, so the Conversation tab can show a
  /// spinner or an error + Retry without blocking the rest of the ticket.
  Future<void> _loadThread() async {
    if (!mounted) return;
    setState(() {
      _threadLoading = true;
      _threadError = null;
    });
    try {
      final thread = await ref
          .read(ticketsRepositoryProvider)
          .thread(widget.ticketId, limit: 50);
      if (!mounted) return;
      setState(() {
        _thread = thread.items;
        _threadLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _threadError = e;
        _threadLoading = false;
      });
    }
  }

  /// Loads the activity log, on the same terms as [_loadThread].
  Future<void> _loadEvents() async {
    if (!mounted) return;
    setState(() {
      _eventsLoading = true;
      _eventsError = null;
    });
    try {
      final events = await ref
          .read(ticketsRepositoryProvider)
          .events(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _events = events;
        _eventsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _eventsError = e;
        _eventsLoading = false;
      });
    }
  }

  /// Runs an optional side-load, swallowing failures so a missing permission
  /// or an older backend never breaks the screen.
  Future<T> _sideLoad<T>(Future<T> Function() op, T fallback) async {
    try {
      return await op();
    } catch (_) {
      return fallback;
    }
  }

  /// Re-reads tags + collaborators after their sheets close.
  ///
  /// The activity log goes with them: adding or removing a collaborator writes
  /// a `collab` thread event server-side (Thread::logCollaboratorEvents), and
  /// this is the one path that doesn't run the full [_load], so without it the
  /// Activity tab stayed on the pre-change list until the screen was rebuilt
  /// from scratch.
  Future<void> _refreshSideData() async {
    final repo = ref.read(ticketsRepositoryProvider);
    final tags = await _sideLoad(() => repo.tags(widget.ticketId), _tags);
    final collabs = await _sideLoad<List<Collaborator>?>(
      () => repo.collaborators(widget.ticketId),
      null,
    );
    if (!mounted) return;
    setState(() {
      _tags = tags;
      if (collabs != null) _collaborators = collabs.length;
    });
    unawaited(_loadEvents());
  }

  /// True when the due date is SLA-driven and must not be hand-edited: either
  /// the payload says so, or the server said so when we last tried. A plan we
  /// know to be disabled overrides the payload's id-based guess - the server
  /// still expects a manual date for those.
  bool get _dueLocked {
    if (_dueLockedByServer) return true;
    if (_slaActive == false) return false;
    return _ticket?.dueDateLocked ?? false;
  }

  /// Resolve the plan's enabled state from `GET /meta/sla` (cached per session)
  /// when the ticket payload names a plan without saying whether it's active.
  Future<void> _resolveSlaActive(Ticket t) async {
    final id = t.sla?.id ?? 0;
    if (id == 0 || t.sla?.locked != null) return;
    final plans = await _sideLoad(
      () => ref.read(metaRepositoryProvider).slaPlans(),
      const <MetaItem>[],
    );
    if (!mounted || plans.isEmpty) return;
    for (final p in plans) {
      if (p.id == id) {
        setState(() => _slaActive = p.active);
        return;
      }
    }
  }

  /// The web's Last Message / Last Response. The payload doesn't carry them
  /// yet, so fall back to the thread already loaded (page 1) - the server's
  /// own values win the moment it publishes them.
  DateTime? get _lastMessageAt =>
      _ticket?.lastMessage ?? _latestEntryAt((e) => e.isMessage);
  DateTime? get _lastResponseAt =>
      _ticket?.lastResponse ?? _latestEntryAt((e) => e.isResponse);

  DateTime? _latestEntryAt(bool Function(ThreadEntry) test) {
    DateTime? best;
    for (final e in _thread) {
      final at = e.created;
      if (at == null || !test(e)) continue;
      if (best == null || at.isAfter(best)) best = at;
    }
    return best;
  }

  /// Rewrites a thread entry (the web's pencil action). The server files the
  /// edit as a new entry and hides the old one, so the whole thread is reloaded
  /// rather than the single bubble patched in place.
  Future<void> _editEntry(ThreadEntry entry) async {
    final html = await showEditEntryDialog(context, entry: entry);
    // Null means dismissed, or saved with nothing actually changed.
    if (html == null || !mounted) return;
    setState(() => _acting = true);
    try {
      await ref
          .read(ticketsRepositoryProvider)
          .editThreadEntry(widget.ticketId, entry.id, body: html);
      await _loadThread();
      _markChanged();
      if (mounted) _toast('Message updated');
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  /// Earlier versions of an edited entry (the web's "View History").
  Future<void> _entryHistory(ThreadEntry entry) => showEntryHistorySheet(
    context,
    load: () => ref
        .read(ticketsRepositoryProvider)
        .threadHistory(widget.ticketId, entry.id),
  );

  /// "To:" options for a public reply, mirroring the web reply form: all
  /// recipients (owner + collaborators) or the ticket owner alone. Values are
  /// osTicket's own `reply-to` values.
  List<ComposerRecipient> _replyRecipients() {
    final collabs = _collaborators ?? 0;
    return [
      ComposerRecipient(
        value: 'all',
        label: 'All recipients (${collabs + 1})',
        detail: collabs > 0
            ? 'Ticket owner + $collabs collaborator${collabs == 1 ? '' : 's'}'
            : null,
      ),
      ComposerRecipient(
        value: 'user',
        label: 'Ticket owner',
        detail: _ticket?.userEmail,
      ),
    ];
  }

  /// Composer transport: post the body (reply or internal note) plus any
  /// attachments, then silently refresh the thread. Returns false on failure so
  /// the composer keeps the draft.
  Future<bool> _sendMessage({
    required bool note,
    required String html,
    required List<MultipartFile> files,
    String? recipient,
  }) async {
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      if (note) {
        await repo.note(widget.ticketId, body: html, files: files);
      } else {
        await repo.reply(
          widget.ticketId,
          body: html,
          alert: true,
          replyTo: recipient,
          files: files,
        );
      }
      await _load(silent: true);
      // A reply can reopen a closed ticket and always bumps last activity, both
      // of which the list reflects (status / thread-activity sort).
      _markChanged();
      return true;
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
      return false;
    }
  }

  void _apply(Ticket updated) {
    _markChanged();
    setState(() => _ticket = updated);
  }

  /// Signal the Tickets list (and any other listener) that this ticket changed,
  /// so it refetches instead of showing a stale row after the user backs out.
  /// The list route stays mounted behind us, so it reloads while we're on top.
  void _markChanged() => ref.read(ticketsChangedProvider.notifier).bump();

  void _toast(String msg) => AppSnack.info(context, msg);

  Future<void> _runAction(
    Future<Ticket> Function() action, {
    String? success,
  }) async {
    setState(() => _acting = true);
    try {
      final updated = await action();
      _apply(updated);
      if (success != null) _toast(success);
    } on ApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  PopupMenuButton<String> _menu(_TicketCaps caps) => PopupMenuButton<String>(
    onSelected: _onMenu,
    shape: AppActionMenu.shape,
    color: Theme.of(context).colorScheme.surface,
    elevation: AppActionMenu.elevation,
    menuPadding: AppActionMenu.menuPadding,
    // Only surface actions the agent may perform — each gated by the same
    // permission the matching /tickets endpoint enforces (checkStaffPerm).
    // Collaborators stays available to everyone: the sheet also *views*
    // collaborators, and its add/remove are enforced server-side.
    itemBuilder: (context) => joinMenuGroups([
      // Workflow / status.
      [
        if (caps.canChangeStatus)
          appMenuItem(value: 'status', asset: Assets.actStatus, label: 'Change status'),
        if (caps.canMark)
          appMenuItem(value: 'mark', asset: Assets.actMark, label: 'Mark answered/overdue'),
      ],
      // Assignment.
      [
        if (caps.canAssign)
          appMenuItem(value: 'assign', asset: Assets.actAssign, label: 'Assign'),
        if (caps.canAssign)
          appMenuItem(value: 'assign_team', asset: Assets.actCollaborators, label: 'Assign to team'),
        if (caps.canAssign)
          appMenuItem(value: 'claim', asset: Assets.actClaim, label: 'Claim'),
        if (caps.canRelease)
          appMenuItem(value: 'release', asset: Assets.actRelease, label: 'Release'),
        if (caps.canEdit)
          appMenuItem(value: 'owner', asset: Assets.actOwner, label: 'Change owner'),
        if (caps.canRefer)
          appMenuItem(value: 'refer', asset: Assets.actRefer, label: 'Refer'),
      ],
      // Attributes.
      [
        if (caps.canTransfer)
          appMenuItem(value: 'transfer', asset: Assets.actTransfer, label: 'Transfer dept'),
        if (caps.canEdit)
          appMenuItem(value: 'priority', asset: Assets.actPriority, label: 'Set priority'),
        if (caps.canEdit)
          appMenuItem(value: 'topic', asset: Assets.actTopic, label: 'Change topic'),
        if (caps.canEdit)
          appMenuItem(value: 'sla', asset: Assets.actDuedate, label: 'Set SLA plan'),
        // Hidden when an SLA plan computes the due date - the web drops its
        // inline editor for a padlock in exactly the same case.
        if (caps.canEdit && !_dueLocked)
          appMenuItem(value: 'duedate', asset: Assets.actDuedate, label: 'Set due date'),
        if (caps.canEdit)
          appMenuItem(value: 'fields', asset: Assets.actEdit, label: 'Edit ticket'),
        if (caps.canEdit)
          appMenuItem(value: 'tags', asset: Assets.actTag, label: 'Tags'),
      ],
      // Relations.
      [
        if (caps.canLink)
          appMenuItem(value: 'link', asset: Assets.actLink, label: 'Link tickets'),
        if (caps.canMerge)
          appMenuItem(value: 'merge', asset: Assets.actMerge, label: 'Merge tickets'),
        if (caps.canCreateTask)
          appMenuItem(value: 'newtask', asset: Assets.actEdit, label: 'Create task'),
      ],
      // Metadata.
      [
        appMenuItem(value: 'collaborators', asset: Assets.actCollaborators, label: 'Collaborators'),
        if (caps.canBan)
          appMenuItem(value: 'ban', asset: Assets.actBan, label: 'Ban / unban email'),
      ],
      [
        if (caps.canDelete)
          appMenuItem(value: 'delete', asset: Assets.actDelete, label: 'Delete', destructive: true),
      ],
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket')),
        body: const LoadingView(),
      );
    }
    if (_error != null || t == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ticket')),
        body: ErrorView(error: _error ?? 'Not found', onRetry: _load),
      );
    }

    // Per-agent action gates (ported from Ticket::checkStaffPerm). `me` is
    // loaded app-wide at startup, so asData is populated by the time this opens;
    // until then caps default to none (safe — the backend would 403 anyway).
    final me = ref.watch(meProvider).asData?.value;
    final caps = _TicketCaps.from(me, t);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: NestedScrollView(
              controller: _headerScroll,
              headerSliverBuilder: (context, _) => [
                SliverAppBar(
                  pinned: true,
                  title: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('#${t.number}'),
                      if (_subjectInBar)
                        AppText.paraText(
                          context,
                          t.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          color: Theme.of(context)
                              .appBarTheme
                              .foregroundColor
                              ?.withValues(alpha: 0.8),
                        ),
                    ],
                  ),
                  actions: [_menu(caps)],
                ),
                SliverToBoxAdapter(child: _CollapsingHeader(ticket: t)),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _SliverTabBarDelegate(
                    TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorPadding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 2,
                      ),
                      tabs: const [
                        Tab(text: 'Conversation'),
                        Tab(text: 'Details'),
                        Tab(text: 'Activity'),
                      ],
                    ),
                  ),
                ),
              ],
              body: Column(
                children: [
                  if (_acting) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _ConversationTab(
                          thread: _thread,
                          loading: _threadLoading,
                          error: _threadError,
                          onRetry: _loadThread,
                          onReply: (e) => setState(() => _replyTo = e),
                          canEdit: (e) =>
                              me?.canEditThreadEntry(
                                e,
                                _ticket?.departmentId,
                              ) ??
                              false,
                          onEdit: _editEntry,
                          onHistory: _entryHistory,
                          headerController: _headerScroll,
                        ),
                        _DetailsTab(
                          ticket: t,
                          caps: caps,
                          onEdit: _onMenu,
                          dueLocked: _dueLocked,
                          fields: _fields,
                          onEditField: _editField,
                          tags: _tags,
                          collaborators: _collaborators,
                          lastMessage: _lastMessageAt,
                          lastResponse: _lastResponseAt,
                        ),
                        _ActivityTab(
                          events: _events,
                          loading: _eventsLoading,
                          error: _eventsError,
                          onRetry: _loadEvents,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The composer floats over the bottom of the conversation (frosted
          // glass), so messages scroll behind it. Rebuild on every swipe frame
          // (the controller's own listener only fires on settled index changes)
          // so the composer hides the instant the user drags off Conversation.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ListenableBuilder(
              listenable: _tabs.animation!,
              // The composer's primary action is a public reply (ticket.reply);
              // its note toggle also needs reply access on this build. Gate the
              // whole composer on canReply so an agent who can't reply doesn't
              // land on a reply box that 403s.
              builder: (context, _) => _onConversationTab && caps.canReply
                  ? MessageComposer(
                      hintReply: 'Reply to this ticket...',
                      replyTo: _replyTo,
                      onClearReply: () => setState(() => _replyTo = null),
                      recipients: _replyRecipients(),
                      // With no collaborators both options reach the same
                      // mailbox, so start on the narrower one.
                      initialRecipient: (_collaborators ?? 0) > 0
                          ? 'all'
                          : 'user',
                      expandCanned: (c) async {
                        final exp = await ref
                            .read(cannedRepositoryProvider)
                            .expand(c.id, ticketId: widget.ticketId);
                        return exp.expanded;
                      },
                      onSend:
                          ({
                            required note,
                            required html,
                            required files,
                            recipient,
                          }) => _sendMessage(
                            note: note,
                            html: html,
                            files: files,
                            recipient: recipient,
                          ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(String value) async {
    final repo = ref.read(ticketsRepositoryProvider);
    switch (value) {
      case 'claim':
        await _runAction(
          () => repo.claim(widget.ticketId),
          success: 'Ticket claimed',
        );
        await _load();
      case 'release':
        await _runAction(
          () => repo.release(widget.ticketId),
          success: 'Ticket released',
        );
        await _load();
      case 'status':
        await _pickMeta(MetaKind.statuses, title: 'Change status', (id) async {
          await _runAction(
            () => repo.setStatus(widget.ticketId, id),
            success: 'Status updated',
          );
          await _load();
        });
      case 'priority':
        await _pickMeta(MetaKind.priorities, title: 'Set priority', (id) async {
          await _runAction(
            () => repo.setPriority(widget.ticketId, id),
            success: 'Priority updated',
          );
        });
      case 'transfer':
        await _pickMeta(MetaKind.departments, title: 'Transfer department',
            selectedId: _ticket?.departmentId, (id) async {
          await _runAction(
            () => repo.transfer(widget.ticketId, id),
            success: 'Transferred',
          );
          await _load();
        });
      case 'assign':
        await _reassign();
      case 'assign_team':
        await _pickMeta(MetaKind.teams, title: 'Assign to team', (id) async {
          await _runAction(
            () => repo.assign(widget.ticketId, teamId: id),
            success: 'Assigned to team',
          );
          await _load();
        });
      case 'topic':
        await _pickMeta(MetaKind.topics, title: 'Change topic', (id) async {
          await _runAction(
            () => repo.setTopic(widget.ticketId, id),
            success: 'Topic updated',
          );
          await _load();
        });
      case 'owner':
        final user = await pickUser(context, ref);
        if (user != null) {
          await _runAction(
            () => repo.setOwner(widget.ticketId, user.id),
            success: 'Owner changed',
          );
          await _load();
        }
      case 'sla':
        await _setSla();
      case 'duedate':
        await _setDueDate();
      case 'fields':
        await _editTicket();
      case 'tags':
        await _manageTags();
      case 'refer':
        await _manageReferrals();
      case 'link':
        await _linkOrMerge(merge: false);
      case 'merge':
        await _linkOrMerge(merge: true);
      case 'ban':
        await _banEmail();
      case 'mark':
        await _markState();
      case 'collaborators':
        await _manageCollaborators();
      case 'newtask':
        // Open the task-create form pre-linked to this ticket (backend accepts
        // `ticket_id`). Pass id + number so the form can show the link.
        final t = _ticket;
        if (t != null) {
          context.push(
            Routes.taskNew,
            extra: (id: widget.ticketId, number: t.number),
          );
        }
      case 'delete':
        await _confirmDelete();
    }
  }

  /// Change the SLA plan, like the web's inline "SLA Plan" editor. The server
  /// recomputes the due date from the new plan (restarting the grace clock at
  /// now), so reload afterwards - and forget any lock we learned from a
  /// refused write, since the new plan may hand the date back to the agent.
  Future<void> _setSla() async {
    await _pickMeta(
      MetaKind.slaPlans,
      title: 'SLA plan',
      selectedId: _ticket?.sla?.id,
      (id) async {
        await _runAction(
          () => ref.read(ticketsRepositoryProvider).setSla(widget.ticketId, id),
          success: 'SLA plan updated',
        );
        _dueLockedByServer = false;
        await _load();
      },
    );
  }

  Future<void> _setDueDate() async {
    // An active SLA plan computes the due date: the web shows a padlock in
    // place of the editor and the API refuses the write, so never open the
    // calendar for it.
    if (_dueLocked) {
      _toast('Due date is computed from the SLA plan');
      return;
    }
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day); // today
    // A ticket may already carry a due date in the past; the picker asserts if
    // initialDate is before firstDate, so clamp it up to today.
    final existingDue = _ticket?.due;
    final initialDate = (existingDue == null || existingDue.isBefore(firstDate))
        ? firstDate
        : existingDue;
    final date = await pickDate(
      context,
      initial: initialDate,
      first: firstDate,
      last: DateTime(now.year + 3, now.month, now.day),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_ticket?.due ?? now),
    );
    final due = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? 17,
      time?.minute ?? 0,
    );
    // Reject a due time already in the past (e.g. today at an earlier hour).
    if (due.isBefore(DateTime.now())) {
      _toast('Due date must be in the future');
      return;
    }
    setState(() => _acting = true);
    try {
      final updated = await ref
          .read(ticketsRepositoryProvider)
          .setDueDate(widget.ticketId, duedate: Fmt.apiDateTime(due));
      _apply(updated);
      _toast('Due date set');
    } on ApiException catch (e) {
      // The SLA refusal arrives as a field error; the envelope message is only
      // "Could not set due date", so show the field text and remember the lock
      // so neither the row nor the menu offers the calendar again.
      final detail = e.fields['field'] ?? e.fields['duedate'] ?? e.message;
      if (detail.toLowerCase().contains('sla')) _dueLockedByServer = true;
      _toast(detail);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
    await _load();
  }

  Future<void> _markState() async {
    const states = {
      'answered': 'Answered',
      'unanswered': 'Unanswered',
      'overdue': 'Overdue',
      'notoverdue': 'Not overdue',
    };
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Mark as'),
        children: [
          for (final e in states.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(e.value),
              ),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await _runAction(
      () => ref.read(ticketsRepositoryProvider).mark(widget.ticketId, chosen),
      success: 'Marked ${states[chosen]!.toLowerCase()}',
    );
    await _load();
  }

  Future<void> _manageCollaborators() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CollaboratorsSheet(ticketId: widget.ticketId),
    );
    await _refreshSideData();
  }

  /// Open the mobile twin of the web's "Update Ticket" form - Ticket Source,
  /// Help Topic, SLA Plan, Due Date, Subject, Priority and the topic's custom
  /// fields - and reload on a successful save.
  Future<void> _editTicket() async {
    final t = _ticket;
    if (t == null) return;
    final saved = await showEditTicketDialog(
      context,
      ticket: t,
      dueLocked: _dueLocked,
    );
    if (saved == true) {
      _markChanged();
      await _load();
    }
  }

  /// Edit one custom field on its own, the way the web's ticket page does -
  /// tap the field, change that answer, save. The full "Update Ticket" form
  /// stays on the menu for editing several at once.
  Future<void> _editField(TicketField field) async {
    final t = _ticket;
    if (t == null) return;
    // Same refusal the backend gives, said up front rather than as a 422.
    if (t.isClosed) {
      _toast('Reopen the ticket to edit it');
      return;
    }
    final saved = await showEditFieldDialog(
      context,
      ticketId: widget.ticketId,
      field: field,
      fields: _fields,
    );
    if (saved == true) {
      _markChanged();
      await _load();
    }
  }

  Future<void> _manageTags() async {
    final repo = ref.read(ticketsRepositoryProvider);
    final meta = ref.read(metaRepositoryProvider);
    final saved = await showTagsDialog(
      context,
      loadApplied: () => repo.tags(widget.ticketId),
      loadShared: () => meta.get(MetaKind.tags),
      addTag: (tagId) => repo.addTag(widget.ticketId, tagId: tagId),
      removeTag: (tagId) => repo.removeTag(widget.ticketId, tagId),
    );
    if (!mounted) return;
    if (saved != null) {
      setState(() => _tags = saved);
      _markChanged();
      AppSnack.success(context, 'Tags updated');
    }
    await _refreshSideData();
  }

  Future<void> _manageReferrals() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ReferralsSheet(ticketId: widget.ticketId),
    );
  }

  Future<void> _linkOrMerge({required bool merge}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _LinkMergeDialog(ticketId: widget.ticketId, merge: merge),
    );
    if (changed == true) {
      _markChanged();
      await _load();
    }
  }

  /// Ban or unban the requester's email address. Both operations are exposed
  /// (the ticket carries no ban flag) via a small chooser sheet.
  Future<void> _banEmail() async {
    final choice = await showAppSheet<String>(
      context: context,
      builder: (_) => AppSheet(
        title: 'Ban list',
        subtitle: _ticket?.userEmail,
        scrollable: false,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PickerOptionTile(
              label: 'Ban this email address',
              selected: false,
              onTap: () => Navigator.pop(context, 'ban'),
            ),
            PickerOptionTile(
              label: 'Remove from ban list',
              selected: false,
              onTap: () => Navigator.pop(context, 'unban'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final repo = ref.read(ticketsRepositoryProvider);
    try {
      final banned = choice == 'ban'
          ? await repo.banEmail(widget.ticketId)
          : await repo.unbanEmail(widget.ticketId);
      if (mounted) _toast(banned ? 'Email banned' : 'Email removed from ban list');
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  /// osTicket-style reassign flow: pick a new assignee and, optionally, record
  /// a reason and keep the current assignee's referral access. Mirrors the web
  /// reassign form rather than the bare agent picker.
  Future<void> _reassign() async {
    // Scoped to the ticket's department: the server only accepts an assignee that
    // department allows (Dept::canAssign), so the whole roster would offer
    // picks that come back 422.
    final AgentPickList agents;
    setState(() => _acting = true);
    try {
      agents = await ref
          .read(agentDirectoryProvider)
          .assignable(
            departmentName: _ticket?.departmentName,
            departmentId: _ticket?.departmentId,
          );
    } on ApiException catch (e) {
      _toast(e.message);
      return;
    } finally {
      if (mounted) setState(() => _acting = false);
    }
    if (!mounted) return;
    final current = _ticket?.assignee;
    final result = await showReassignDialog(
      context,
      assignees: agents.agents,
      allAssignees: agents.scoped ? agents.all : null,
      scopeDepartment: agents.departmentName,
      title: (current != null && current.isNotEmpty) ? 'Reassign' : 'Assign',
      assigneeLabel: 'Assignee',
      currentAssignee: current,
    );
    if (result == null) return;
    await _runAction(
      () => ref.read(ticketsRepositoryProvider).assign(
            widget.ticketId,
            staffId: result.assigneeId,
            comments: result.comments,
            refer: result.maintainReferral,
          ),
      success: 'Assigned',
    );
    await _load();
  }

  Future<void> _pickMeta(
    String kind,
    Future<void> Function(int id) onPick, {
    String title = 'Select',
    int? selectedId,
  }) async {
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(kind);
    } on ApiException catch (e) {
      _toast(e.message);
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => _MetaPickerDialog(
        title: title,
        items: items,
        selectedId: selectedId,
      ),
    );
    if (chosen != null) await onPick(chosen);
  }

  Future<void> _confirmDelete() async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Delete ticket?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok != true) return;
    try {
      await ref.read(ticketsRepositoryProvider).delete(widget.ticketId);
      if (mounted) {
        _toast('Ticket deleted');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }
}

// --- Collapsing header (status + SLA; scrolls away under the app bar) --------

class _CollapsingHeader extends StatelessWidget {
  const _CollapsingHeader({required this.ticket});
  final Ticket ticket;

  /// "SLA: High - 8h" once the backend names the plan, otherwise just the
  /// remaining-time label it has always shown.
  static String _slaLine(Sla sla) {
    final parts = [
      if (sla.name != null) sla.name!,
      if (sla.label != null) sla.label!,
    ];
    return 'SLA: ${parts.isEmpty ? '-' : parts.join(' - ')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.titleText(context, ticket.subject, fw: 2),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusChip.status(ticket.statusName, dense: true),
              if (ticket.priority != null)
                StatusChip.priority(ticket.priority!, dense: true),
              if (ticket.isOverdue)
                const StatusChip(
                  label: 'Overdue',
                  color: Color(0xFFD32F2F),
                  icon: Icons.warning_amber_rounded,
                  dense: true,
                ),
            ],
          ),
          if (ticket.sla != null && ticket.sla!.frac != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ticket.sla!.frac!.clamp(0, 1),
                minHeight: 6,
                color: ticket.sla!.isOverdue
                    ? const Color(0xFFD32F2F)
                    : theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            AppText.paraText(context, _slaLine(ticket.sla!)),
          ],
        ],
      ),
    );
  }
}

/// Pins the tab bar below the (collapsing) header.
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverTabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate old) => old.tabBar != tabBar;
}

// --- Tabs -------------------------------------------------------------------

class _ConversationTab extends StatelessWidget {
  const _ConversationTab({
    required this.thread,
    this.onReply,
    this.onEdit,
    this.canEdit,
    this.onHistory,
    this.headerController,
    this.loading = false,
    this.error,
    this.onRetry,
  });
  final List<ThreadEntry> thread;
  final ValueChanged<ThreadEntry>? onReply;
  final ValueChanged<ThreadEntry>? onEdit;
  final bool Function(ThreadEntry entry)? canEdit;
  final ValueChanged<ThreadEntry>? onHistory;
  final ScrollController? headerController;

  /// The thread arrives after the ticket, so the tab owns its load state.
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // Messages already on screen stay put through a refresh; the spinner and
    // the error state only stand in when there is nothing to show.
    if (thread.isEmpty) {
      if (error != null) {
        return ErrorView(error: error!, onRetry: onRetry, compact: true);
      }
      if (loading) return const LoadingView();
      return const EmptyView(message: 'No messages yet');
    }
    // Reserve room for the floating composer so the newest message clears it.
    return ConversationList(
      thread: thread,
      onReply: onReply,
      onEdit: onEdit,
      canEdit: canEdit,
      onHistory: onHistory,
      headerController: headerController,
      bottomReserve: 104 + MediaQuery.of(context).padding.bottom,
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.ticket,
    required this.caps,
    required this.onEdit,
    required this.dueLocked,
    this.fields = const [],
    required this.onEditField,
    this.tags = const [],
    this.collaborators,
    this.lastMessage,
    this.lastResponse,
  });
  final Ticket ticket;

  /// The topic's form definition (`GET /tickets/{id}/fields`), when it loaded.
  /// Empty on an older backend or a refused read - the flat `custom_fields`
  /// map then stands in, without the required flags.
  final List<TicketField> fields;

  /// An SLA plan computes the due date, so the row is read-only (padlock).
  final bool dueLocked;

  /// Side-data loaded alongside the ticket (own endpoints).
  final List<Tag> tags;
  final int? collaborators;

  /// Last inbound message / last agent response, served by the API when it
  /// publishes them, otherwise derived from the loaded thread.
  final DateTime? lastMessage;
  final DateTime? lastResponse;

  /// Per-agent action gates — a null onTap below renders the row read-only when
  /// the agent lacks the matching permission.
  final _TicketCaps caps;

  /// Opens one custom field's own edit dialog (the web's per-field edit).
  final ValueChanged<TicketField> onEditField;

  /// Routes an edit intent (matching the â‹®-menu action keys) back to the host.
  final ValueChanged<String> onEdit;

  /// The topic's answers in form order, marked up for display. Built from
  /// [fields] whenever the form loaded, since only that carries the required
  /// flag; the ticket payload's flat map is the fallback.
  List<TicketFieldRow> get _customRows =>
      ticketFieldRows(ticket.customFields, fields);

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Pad the bottom past the system gesture bar / home indicator so the last
      // row isn't tucked under it.
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        // Editable attributes â€” tap to open the matching picker. The order
        // follows the web's ticket page (status/priority/department, then
        // topic/source, assignment, SLA and due date).
        _DetailSection(
          title: 'Attributes',
          children: [
            _DetailRow(
              icon: Icons.published_with_changes,
              label: 'Status',
              value: ticket.statusName,
              onTap: caps.canChangeStatus ? () => onEdit('status') : null,
            ),
            _DetailRow(
              icon: Icons.flag_outlined,
              label: 'Priority',
              value: ticket.priority,
              placeholder: 'Set priority',
              onTap: caps.canEdit ? () => onEdit('priority') : null,
            ),
            _DetailRow(
              icon: Icons.apartment_outlined,
              label: 'Department',
              value: ticket.departmentName,
              placeholder: 'Transfer',
              onTap: caps.canTransfer ? () => onEdit('transfer') : null,
            ),
            // Help topic and source only exist on backends that publish them;
            // the row stays out rather than showing an empty placeholder for
            // a value we can't read. "Change topic" remains in the menu.
            if (ticket.topicName != null)
              _DetailRow(
                icon: Icons.topic_outlined,
                label: 'Help topic',
                value: ticket.topicName,
                onTap: caps.canEdit ? () => onEdit('topic') : null,
              ),
            if (ticket.source != null)
              _DetailRow(
                icon: Icons.input,
                label: 'Source',
                value: ticket.source,
              ),
            _DetailRow(
              icon: Icons.assignment_ind_outlined,
              label: 'Assignee',
              value: ticket.assignee,
              placeholder: 'Assign',
              onTap: caps.canAssign ? () => onEdit('assign') : null,
            ),
            // Tappable like the web's inline SLA editor. The name shows once
            // the payload carries it; until then the row is the action only,
            // so it never claims a plan we can't read.
            if (ticket.sla?.name != null || caps.canEdit)
              _DetailRow(
                icon: Icons.timer_outlined,
                label: 'SLA plan',
                value: ticket.sla?.name,
                placeholder: 'Change SLA plan',
                onTap: caps.canEdit ? () => onEdit('sla') : null,
              ),
            // Padlocked, not tappable, when the plan drives the date - same
            // treatment as the web's ticket page.
            _DetailRow(
              icon: Icons.event_outlined,
              label: 'Due date',
              value: ticket.due == null ? null : Fmt.dateTime(ticket.due),
              placeholder: 'Set due date',
              note: dueLocked ? 'Computed from SLA plan' : null,
              trailingIcon: dueLocked ? Icons.lock_outline : null,
              onTap: (caps.canEdit && !dueLocked)
                  ? () => onEdit('duedate')
                  : null,
            ),
            _DetailRow(
              icon: Icons.local_offer_outlined,
              label: 'Tags',
              value: tags.isEmpty ? null : tags.map((t) => t.name).join(', '),
              placeholder: 'No tags',
              onTap: caps.canEdit ? () => onEdit('tags') : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Requester side of the ticket.
        _DetailSection(
          title: 'People',
          children: [
            _DetailRow(
              icon: Icons.person_outline,
              label: 'Requester',
              value: ticket.requester,
            ),
            _DetailRow(
              icon: Icons.mail_outline,
              label: 'Email',
              value: ticket.userEmail,
            ),
            if (ticket.organization != null)
              _DetailRow(
                icon: Icons.business_outlined,
                label: 'Organization',
                value: ticket.organization,
              ),
            _DetailRow(
              icon: Icons.group_outlined,
              label: 'Collaborators',
              value: collaborators == null
                  ? null
                  : (collaborators == 0 ? 'None' : '$collaborators'),
              placeholder: 'Manage',
              onTap: () => onEdit('collaborators'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // The web's date column: create / last message / last response /
        // last update, plus the close date once the ticket is closed.
        _DetailSection(
          title: 'Dates',
          children: [
            _DetailRow(
              icon: Icons.schedule,
              label: 'Created',
              value: Fmt.dateTime(ticket.created),
            ),
            if (lastMessage != null)
              _DetailRow(
                icon: Icons.forum_outlined,
                label: 'Last message',
                value: Fmt.dateTime(lastMessage),
              ),
            if (lastResponse != null)
              _DetailRow(
                icon: Icons.reply_outlined,
                label: 'Last response',
                value: Fmt.dateTime(lastResponse),
              ),
            _DetailRow(
              icon: Icons.update,
              label: 'Last update',
              value: Fmt.dateTime(ticket.updated),
            ),
            if (ticket.closedAt != null)
              _DetailRow(
                icon: Icons.check_circle_outline,
                label: 'Closed',
                value: Fmt.dateTime(ticket.closedAt),
              ),
          ],
        ),
        // The topic's own form answers. The payload carries every answered
        // field, blanks included, so an all-empty form used to render this
        // section as a bare heading over an empty card. The web instead lists
        // each field and marks the unset ones with a faded "—Empty—", keeping
        // them tappable while the agent may edit (ticket-view.inc.php:736) —
        // here that tap opens the same "Edit fields" sheet as the menu item.
        if (_customRows.isNotEmpty) ...[
          const SizedBox(height: 16),
          _DetailSection(
            title: 'Ticket details',
            children: [
              for (final r in _customRows)
                _DetailRow(
                  icon: Icons.list_alt_outlined,
                  label: r.label,
                  value: r.value,
                  placeholder: '—Empty—',
                  alwaysShow: true,
                  // A required answer left blank gets the web's warning
                  // triangle: osTicket refuses to close (or delete) the ticket
                  // until it's filled in, so the agent has to be able to see
                  // which one is holding it up.
                  warn: r.missing,
                  // The field's own dialog when we know its definition;
                  // otherwise the whole form, which is all an older backend
                  // gives us to work with.
                  onTap: !caps.canEdit
                      ? null
                      : (r.field == null
                            ? () => onEdit('fields')
                            : () => onEditField(r.field!)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A titled card grouping a set of [_DetailRow]s.
class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: AppText.captionText(
            context,
            title.toUpperCase(),
            fw: 2,
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < _visible.length; i++) ...[
                if (i != 0) const Divider(height: 1, indent: 52),
                _visible[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Rows that actually render. A static row with nothing to show collapses to
  /// an empty box, so it has to be dropped here too — otherwise it leaves its
  /// divider behind as a stray hairline.
  List<Widget> get _visible => [
    for (final c in children)
      if (c is! _DetailRow || c.isVisible) c,
  ];
}

/// A single detail row. When [onTap] is set it renders as tappable (chevron +
/// ripple); otherwise it's static. A null/empty [value] shows [placeholder]
/// in a muted style.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.placeholder,
    this.note,
    this.trailingIcon,
    this.onTap,
    this.alwaysShow = false,
    this.warn = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? placeholder;

  /// Render the row even with nothing to show. Custom fields set this: the web
  /// lists every field on the ticket's form and marks the unanswered ones with
  /// a faded "—Empty—" rather than dropping them, so the agent can see which
  /// ones still need filling in.
  final bool alwaysShow;

  /// Secondary line under the value (why a row is read-only, typically).
  final String? note;

  /// Replaces the chevron - a padlock on an SLA-driven due date.
  final IconData? trailingIcon;
  final VoidCallback? onTap;

  /// Draws a warning triangle beside the value: a required answer that's still
  /// missing, the way the web marks one.
  final bool warn;

  /// Whether the row carries a real value. [Fmt.dateTime] and friends render a
  /// bare em dash for a null date, which is a placeholder, not a value.
  bool get _has => value != null && value!.isNotEmpty && value != '—';

  /// Whether this row renders anything at all. Static rows with nothing to say
  /// collapse; [_DetailSection] reads this so it can drop their dividers too.
  bool get isVisible => _has || onTap != null || note != null || alwaysShow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final has = _has;
    if (!isVisible) return const SizedBox.shrink();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 16),
            SizedBox(
              width: 96,
              child: AppText.subText(
                context,
                label,
                color: scheme.onSurfaceVariant,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: AppText.subText(
                          context,
                          has ? value! : (placeholder ?? '—'),
                          fw: has ? 1 : 3,
                          color: has
                              ? scheme.onSurface
                              : (onTap == null
                                    ? scheme.onSurfaceVariant
                                    : scheme.primary),
                        ),
                      ),
                      if (warn) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: AppTheme.warning,
                        ),
                      ],
                    ],
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    AppText.captionText(
                      context,
                      note!,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
            if (trailingIcon != null)
              Icon(trailingIcon, size: 18, color: scheme.onSurfaceVariant)
            else if (onTap != null)
              Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({
    required this.events,
    this.loading = false,
    this.error,
    this.onRetry,
  });
  final List<ThreadEvent> events;

  /// The activity log loads separately from the ticket - same deal as the
  /// conversation tab.
  final bool loading;
  final Object? error;
  final VoidCallback? onRetry;

  /// (icon, colour) for an event, derived from its state slug.
  static (IconData, Color) _style(String state) {
    final s = state.toLowerCase();
    if (s.contains('close') || s.contains('resolved')) {
      return (Icons.check_circle_outline, AppTheme.closed);
    }
    if (s.contains('open') || s.contains('reopen')) {
      return (Icons.play_circle_outline, AppTheme.open);
    }
    if (s.contains('assign') || s.contains('claim') || s.contains('owner')) {
      return (Icons.person_outline, AppTheme.brand);
    }
    if (s.contains('transfer')) {
      return (Icons.swap_horiz, AppTheme.warning);
    }
    if (s.contains('overdue')) {
      return (Icons.warning_amber_rounded, AppTheme.overdue);
    }
    if (s.contains('note')) {
      return (Icons.sticky_note_2_outlined, AppTheme.brandLight);
    }
    if (s.contains('reply') || s.contains('message')) {
      return (Icons.reply, AppTheme.open);
    }
    // Server state is the bare slug 'collab' for both add and remove; the
    // description says which. Matches the Collaborators row's icon.
    if (s.contains('collab')) {
      return (Icons.group_outlined, AppTheme.brand);
    }
    return (Icons.fiber_manual_record, AppTheme.brand);
  }

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      if (error != null) {
        return ErrorView(error: error!, onRetry: onRetry, compact: true);
      }
      if (loading) return const LoadingView();
      return const EmptyView(message: 'No activity');
    }
    final scheme = Theme.of(context).colorScheme;
    // Newest first, "Created" last — the API's `order_by('timestamp')`
    // (v2controller.php:128) leaves same-second ties to the database, so the
    // list is re-sorted on (timestamp, id) before it's reversed.
    final display = ThreadEvent.newestFirst(events);
    return SafeArea(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: display.length,
        itemBuilder: (context, i) {
          final e = display[i];
          final (icon, color) = _style(e.state);
          final isLast = i == display.length - 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timeline rail: a coloured icon node with a connector below.
                Column(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 17, color: color),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: scheme.outlineVariant,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 18, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText.subText(
                          context,
                          e.description ?? e.state,
                          fw: 1,
                          lineHeight: 1.3,
                        ),
                        const SizedBox(height: 2),
                        AppText.paraText(
                          context,
                          [
                            if ((e.actor ?? '').isNotEmpty) e.actor!,
                            Fmt.ago(e.created),
                          ].join(' Â· '),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// --- Collaborators sheet ----------------------------------------------------

class _CollaboratorsSheet extends ConsumerStatefulWidget {
  const _CollaboratorsSheet({required this.ticketId});
  final int ticketId;

  @override
  ConsumerState<_CollaboratorsSheet> createState() =>
      _CollaboratorsSheetState();
}

class _CollaboratorsSheetState extends ConsumerState<_CollaboratorsSheet> {
  List<Collaborator> _collabs = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await ref
          .read(ticketsRepositoryProvider)
          .collaborators(widget.ticketId);
      if (mounted) {
        setState(() {
          _collabs = c;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppSnack.error(context, e.message);
      }
    }
  }

  Future<void> _add() async {
    final user = await pickUser(context, ref);
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ticketsRepositoryProvider)
          .addCollaborator(widget.ticketId, user.id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        AppSnack.error(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(int cid) async {
    setState(() => _busy = true);
    try {
      final c = await ref
          .read(ticketsRepositoryProvider)
          .removeCollaborator(widget.ticketId, cid);
      if (mounted) setState(() => _collabs = c);
    } on ApiException catch (e) {
      if (mounted) {
        AppSnack.error(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Collaborators',
      actionLabel: 'Add collaborator',
      onAction: _busy ? null : _add,
      actionEnabled: !_busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _collabs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: AppText.subText(context, 'No collaborators'),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in _collabs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.name),
                          subtitle: c.email != null ? Text(c.email!) : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _busy ? null : () => _remove(c.id),
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

// --- Referrals sheet --------------------------------------------------------

/// Lists a ticket's referrals and lets the agent refer it to an agent, team or
/// department, or remove a referral (`GET/POST/DELETE /tickets/{id}/referrals`).
class _ReferralsSheet extends ConsumerStatefulWidget {
  const _ReferralsSheet({required this.ticketId});
  final int ticketId;

  @override
  ConsumerState<_ReferralsSheet> createState() => _ReferralsSheetState();
}

class _ReferralsSheetState extends ConsumerState<_ReferralsSheet> {
  List<Referral> _refs = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ref
          .read(ticketsRepositoryProvider)
          .referrals(widget.ticketId);
      if (mounted) {
        setState(() {
          _refs = r;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        AppSnack.error(context, e.message);
      }
    }
  }

  Future<void> _add() async {
    final target = await showAppSheet<String>(
      context: context,
      builder: (_) => AppSheet(
        title: 'Refer to',
        scrollable: false,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PickerOptionTile(
              label: 'Agent',
              selected: false,
              onTap: () => Navigator.pop(context, 'agent'),
            ),
            PickerOptionTile(
              label: 'Team',
              selected: false,
              onTap: () => Navigator.pop(context, 'team'),
            ),
            PickerOptionTile(
              label: 'Department',
              selected: false,
              onTap: () => Navigator.pop(context, 'dept'),
            ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    final kind = target == 'agent'
        ? MetaKind.agents
        : target == 'team'
        ? MetaKind.teams
        : MetaKind.departments;
    final List<MetaItem> items;
    try {
      items = await ref.read(metaRepositoryProvider).get(kind);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => _MetaPickerDialog(title: 'Refer to', items: items),
    );
    if (chosen == null) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(ticketsRepositoryProvider).addReferral(
        widget.ticketId,
        staffId: target == 'agent' ? chosen : null,
        teamId: target == 'team' ? chosen : null,
        deptId: target == 'dept' ? chosen : null,
      );
      if (mounted) setState(() => _refs = r);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(int rid) async {
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(ticketsRepositoryProvider)
          .removeReferral(widget.ticketId, rid);
      if (mounted) setState(() => _refs = r);
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Referrals',
      actionLabel: 'Add referral',
      onAction: _busy ? null : _add,
      actionEnabled: !_busy,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : _refs.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AppText.subText(context, 'No referrals'),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in _refs)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r.name),
                      subtitle: Text(r.type),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _busy ? null : () => _remove(r.id),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// --- Link / merge dialog ----------------------------------------------------

/// Links or merges other tickets into this one by their ticket numbers, showing
/// any existing relations and offering to undo. Pops `true` when something
/// changed so the caller reloads.
class _LinkMergeDialog extends ConsumerStatefulWidget {
  const _LinkMergeDialog({required this.ticketId, required this.merge});
  final int ticketId;
  final bool merge;

  @override
  ConsumerState<_LinkMergeDialog> createState() => _LinkMergeDialogState();
}

class _LinkMergeDialogState extends ConsumerState<_LinkMergeDialog> {
  final _numbers = TextEditingController();
  TicketRelations? _relations;
  bool _loading = true;
  bool _busy = false;
  bool _combine = true;
  String? _numError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _numbers.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await ref
          .read(ticketsRepositoryProvider)
          .relations(widget.ticketId);
      if (mounted) {
        setState(() {
          _relations = r;
          _loading = false;
        });
      }
    } on ApiException catch (_) {
      // Relations are informational only; a failure just hides the summary.
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _parsed => _numbers.text
      .split(RegExp(r'[,\s]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  bool get _hasRelations {
    final r = _relations;
    return r != null && (r.parent != null || r.children.isNotEmpty);
  }

  Future<void> _submit() async {
    final nums = _parsed;
    if (nums.isEmpty) {
      setState(() => _numError = 'Enter at least one ticket number');
      return;
    }
    setState(() {
      _numError = null;
      _busy = true;
    });
    try {
      final repo = ref.read(ticketsRepositoryProvider);
      if (widget.merge) {
        await repo.merge(widget.ticketId, nums, combine: _combine ? 1 : 0);
      } else {
        await repo.link(widget.ticketId, nums);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnack.error(context, e.message);
      }
    }
  }

  Future<void> _undo() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(ticketsRepositoryProvider);
      if (widget.merge) {
        await repo.unmerge(widget.ticketId);
      } else {
        await repo.unlink(widget.ticketId);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        AppSnack.error(context, e.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppDialog(
      title: widget.merge ? 'Merge tickets' : 'Link tickets',
      actionLabel: widget.merge ? 'Merge' : 'Link',
      actionBusy: _busy,
      onAction: _submit,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_hasRelations) ...[
                  AppText.subText(
                    context,
                    () {
                      final r = _relations!;
                      if (r.children.isNotEmpty) {
                        final nums = r.children.map((c) => '#${c.number}').join(', ');
                        return 'Currently ${r.children.length} linked: $nums';
                      }
                      return 'Linked to #${r.parent!.number}';
                    }(),
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : _undo,
                      icon: const Icon(Icons.link_off, size: 18),
                      label: Text(widget.merge ? 'Unmerge' : 'Unlink'),
                    ),
                  ),
                  const Divider(height: 20),
                ],
                TextField(
                  controller: _numbers,
                  keyboardType: TextInputType.text,
                  onChanged: (_) {
                    if (_numError != null) setState(() => _numError = null);
                  },
                  decoration: InputDecoration(
                    labelText: 'Ticket numbers',
                    hintText: 'e.g. 100234, 100235',
                    errorText: _numError,
                  ),
                ),
                if (widget.merge)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _combine,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _combine = v),
                    title: AppText.subText(context, 'Combine threads', fw: 1),
                    subtitle: AppText.paraText(
                      context,
                      'Merge conversations into one thread',
                    ),
                  ),
              ],
            ),
    );
  }
}

// --- Meta picker dialog (with search) ----------------------------------------

class _MetaPickerDialog extends StatefulWidget {
  const _MetaPickerDialog({
    required this.title,
    required this.items,
    this.selectedId,
  });

  final String title;
  final List<MetaItem> items;
  final int? selectedId;

  @override
  State<_MetaPickerDialog> createState() => _MetaPickerDialogState();
}

class _MetaPickerDialogState extends State<_MetaPickerDialog> {
  final _searchCtrl = TextEditingController();
  late List<MetaItem> _filtered = widget.items;

  /// Only show the search field for lists long enough to warrant it; short
  /// pick-lists (priorities, statuses, â€¦) don't need one.
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
            SheetSearchField(
              controller: _searchCtrl,
              hintText: 'Search',
            ),
            const SizedBox(height: 12),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: _filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: AppText.subText(context, 'No results found'),
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
                                fw: item.id == widget.selectedId ? 2 : 3,
                                color: item.id == widget.selectedId
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurface,
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
