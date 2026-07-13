import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format.dart';
import '../../../core/router/routes.dart';
import '../../../models/common.dart';
import '../../../models/organization.dart';
import '../../../models/ticket.dart';
import '../../../models/user.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/comment_composer.dart';
import '../../../widgets/states.dart';
import '../../../widgets/web/status_pill.dart';
import '../../dashboard/web/_tokens.dart';

/// Web-only organization-detail slide-over panel — visual parity with
/// [TicketDetailPanel]:
///   - single-row header with an org avatar + name on the left and
///     Actions + Fullscreen + Close on the right;
///   - fields expressed as a left-labeled table inside one rounded card;
///   - members / tickets / notes rendered as card-per-item rows.
const double _kFieldLabelWidth = 88;
const double _kSidebarRowHeight = 40;
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
const double _kFieldsSidebarWidth = 320;

class OrgDetailPanel extends ConsumerStatefulWidget {
  const OrgDetailPanel({
    super.key,
    required this.orgId,
    required this.onClose,
    this.onChanged,
    this.isFullscreen = false,
    this.onToggleFullscreen,
  });
  final int orgId;
  final VoidCallback onClose;

  /// Called after any mutation the list should reflect (edit, delete,
  /// membership change).
  final VoidCallback? onChanged;

  /// See [TicketDetailPanel.isFullscreen].
  final bool isFullscreen;

  /// See [TicketDetailPanel.onToggleFullscreen].
  final VoidCallback? onToggleFullscreen;

  @override
  ConsumerState<OrgDetailPanel> createState() => _OrgDetailPanelState();
}

class _OrgDetailPanelState extends ConsumerState<OrgDetailPanel> {
  Organization? _org;
  List<AppUser> _members = const [];
  int _membersTotal = 0;
  List<Ticket> _tickets = const [];
  int _ticketsTotal = 0;
  List<StaffNote> _notes = const [];
  Object? _error;
  bool _loading = true;
  bool _acting = false;

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
    final repo = ref.read(orgsRepositoryProvider);
    try {
      final org = await repo.get(widget.orgId);
      final members = await repo.users(widget.orgId, page: 1);
      final tickets = await repo.tickets(widget.orgId, page: 1);
      final notes = await repo.notes(widget.orgId);
      if (!mounted) return;
      setState(() {
        _org = org;
        _members = members.items;
        _membersTotal = members.total;
        _tickets = tickets.items;
        _ticketsTotal = tickets.total;
        _notes = notes;
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

  Future<T?> _runAction<T>(
    Future<T> Function() action, {
    String? success,
  }) async {
    setState(() => _acting = true);
    try {
      final result = await action();
      if (success != null) _toast(success, type: ToastType.success);
      return result;
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
      return null;
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _onMenu(String value) async {
    final o = _org;
    if (o == null) return;
    final repo = ref.read(orgsRepositoryProvider);
    switch (value) {
      case 'edit':
        final saved = await showDialog<bool>(
          context: context,
          builder: (_) => _EditOrgDialog(org: o),
        );
        if (saved == true) {
          _toast('Organization updated', type: ToastType.success);
          widget.onChanged?.call();
          await _load();
        }
        return;
      case 'delete':
        final ok = await showAppConfirmDialog(
          context,
          title: 'Delete organization?',
          message: 'This cannot be undone.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (ok != true) return;
        final done = await _runAction(() async {
          await repo.delete(widget.orgId);
          return true;
        }, success: 'Organization deleted');
        if (done == true) {
          widget.onChanged?.call();
          widget.onClose();
        }
        return;
    }
  }

  Future<bool> _addNote({
    required bool asNote,
    required String bodyHtml,
    required List<MultipartFile> files,
  }) async {
    if (bodyHtml.trim().isEmpty) return false;
    setState(() => _acting = true);
    final repo = ref.read(orgsRepositoryProvider);
    try {
      await repo.addNote(widget.orgId, bodyHtml);
      final notes = await repo.notes(widget.orgId);
      if (!mounted) return true;
      setState(() => _notes = notes);
      _toast('Note added', type: ToastType.success);
      return true;
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
      return false;
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _deleteNote(StaffNote note) async {
    final repo = ref.read(orgsRepositoryProvider);
    try {
      await repo.deleteNote(widget.orgId, note.id);
      final notes = await repo.notes(widget.orgId);
      if (!mounted) return;
      setState(() => _notes = notes);
    } on ApiException catch (e) {
      _toast(e.message, type: ToastType.error);
    }
  }

  Future<void> _removeMember(AppUser u) async {
    final ok = await showAppConfirmDialog(
      context,
      title: 'Remove member?',
      message: 'Remove ${u.name.isEmpty ? u.email : u.name} from this '
          'organization?',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (ok != true) return;
    final repo = ref.read(orgsRepositoryProvider);
    final done = await _runAction(() async {
      await repo.removeUser(widget.orgId, u.id);
      final members = await repo.users(widget.orgId, page: 1);
      if (mounted) {
        setState(() {
          _members = members.items;
          _membersTotal = members.total;
        });
      }
      return true;
    }, success: 'Member removed');
    if (done == true) widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Material(
      // Warm-paper ground so the panel matches the list surface behind it.
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
            org: null,
            onClose: widget.onClose,
            onMenu: null,
            isFullscreen: widget.isFullscreen,
            onToggleFullscreen: widget.onToggleFullscreen,
          ),
          const Expanded(child: LoadingView()),
        ],
      );
    }
    if (_error != null || _org == null) {
      return Column(
        children: [
          _Header(
            org: null,
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
    final o = _org!;
    return Column(
      children: [
        _Header(
          org: o,
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
              if (wide) return _buildWide(t, o);
              return _buildNarrow(t, o);
            },
          ),
        ),
        CommentComposer(
          onSend: _addNote,
          disabled: _acting,
          scope: ComposerScope.noteOnly,
          allowAttachments: false,
        ),
      ],
    );
  }

  /// Narrow single-column layout: fields card on top, custom fields, then
  /// Members / Tickets / Notes sections stacked vertically. Same layout the
  /// panel shipped with before the two-column split.
  Widget _buildNarrow(WebTokens t, Organization o) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: WebTokens.s3),
        _FieldsTable(org: o, sidebar: false),
        if (o.customFields.isNotEmpty) ...[
          const SizedBox(height: WebTokens.s2),
          const _SectionSubheader('Details'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTokens.s4,
              WebTokens.s3,
              WebTokens.s4,
              0,
            ),
            child: _CustomFields(fields: o.customFields),
          ),
        ],
        const SizedBox(height: WebTokens.s2),
        _SectionSubheader(
          'Members',
          trailing: _membersTotal > 0 ? '$_membersTotal' : null,
        ),
        if (_members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WebTokens.s5),
            child: Center(
              child: Text('No members yet', style: t.bodySm),
            ),
          )
        else ...[
          for (final m in _members)
            _MemberRow(
              user: m,
              onTap: () => context.push(Routes.user(m.id)),
              onRemove: () => _removeMember(m),
            ),
          if (_membersTotal > _members.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTokens.s4,
                WebTokens.s3,
                WebTokens.s4,
                0,
              ),
              child: Text(
                '+ ${_membersTotal - _members.length} more',
                style: t.bodySm,
              ),
            ),
        ],
        const SizedBox(height: WebTokens.s2),
        _SectionSubheader(
          'Tickets',
          trailing: _ticketsTotal > 0 ? '$_ticketsTotal' : null,
        ),
        if (_tickets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WebTokens.s5),
            child: Center(
              child: Text(
                'No tickets from this organization',
                style: t.bodySm,
              ),
            ),
          )
        else ...[
          for (final ticket in _tickets)
            _TicketRow(
              ticket: ticket,
              onTap: () => context.push(Routes.ticket(ticket.id)),
            ),
          if (_ticketsTotal > _tickets.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WebTokens.s4,
                WebTokens.s3,
                WebTokens.s4,
                0,
              ),
              child: Text(
                '+ ${_ticketsTotal - _tickets.length} more',
                style: t.bodySm,
              ),
            ),
        ],
        const SizedBox(height: WebTokens.s2),
        const _SectionSubheader('Notes'),
        if (_notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WebTokens.s5),
            child: Center(
              child: Text('No notes yet', style: t.bodySm),
            ),
          )
        else ...[
          for (final n in _notes)
            _NoteRow(note: n, onDelete: () => _deleteNote(n)),
          const SizedBox(height: WebTokens.s3),
        ],
      ],
    );
  }

  /// Two-column layout used at >= [_kTwoColumnBreakpoint] px: primary content
  /// (Members + Tickets + Notes) on the left, fields sidebar on the right at
  /// [_kFieldsSidebarWidth]. A hairline seam separates the two columns.
  Widget _buildWide(WebTokens t, Organization o) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _SectionSubheader(
                'Members',
                trailing: _membersTotal > 0 ? '$_membersTotal' : null,
              ),
              if (_members.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: WebTokens.s5),
                  child: Center(
                    child: Text('No members yet', style: t.bodySm),
                  ),
                )
              else ...[
                for (final m in _members)
                  _MemberRow(
                    user: m,
                    onTap: () => context.push(Routes.user(m.id)),
                    onRemove: () => _removeMember(m),
                  ),
                if (_membersTotal > _members.length)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WebTokens.s4,
                      WebTokens.s3,
                      WebTokens.s4,
                      0,
                    ),
                    child: Text(
                      '+ ${_membersTotal - _members.length} more',
                      style: t.bodySm,
                    ),
                  ),
              ],
              const SizedBox(height: WebTokens.s2),
              _SectionSubheader(
                'Tickets',
                trailing: _ticketsTotal > 0 ? '$_ticketsTotal' : null,
              ),
              if (_tickets.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: WebTokens.s5),
                  child: Center(
                    child: Text(
                      'No tickets from this organization',
                      style: t.bodySm,
                    ),
                  ),
                )
              else ...[
                for (final ticket in _tickets)
                  _TicketRow(
                    ticket: ticket,
                    onTap: () => context.push(Routes.ticket(ticket.id)),
                  ),
                if (_ticketsTotal > _tickets.length)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WebTokens.s4,
                      WebTokens.s3,
                      WebTokens.s4,
                      0,
                    ),
                    child: Text(
                      '+ ${_ticketsTotal - _tickets.length} more',
                      style: t.bodySm,
                    ),
                  ),
              ],
              const SizedBox(height: WebTokens.s2),
              const _SectionSubheader('Notes'),
              if (_notes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: WebTokens.s5),
                  child: Center(
                    child: Text('No notes yet', style: t.bodySm),
                  ),
                )
              else ...[
                for (final n in _notes)
                  _NoteRow(note: n, onDelete: () => _deleteNote(n)),
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
                _FieldsTable(org: o, sidebar: true),
                if (o.customFields.isNotEmpty) ...[
                  const SizedBox(height: WebTokens.s2),
                  const _SectionSubheader('Details'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      WebTokens.s4,
                      WebTokens.s3,
                      WebTokens.s4,
                      0,
                    ),
                    child: _CustomFields(fields: o.customFields),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.org,
    required this.onClose,
    required this.onMenu,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });
  final Organization? org;
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (org == null)
            Expanded(child: Text('Loading…', style: t.cardName))
          else ...[
            const _OrgChip(),
            const SizedBox(width: WebTokens.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    org!.name.isEmpty ? '(unnamed)' : org!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.pageTitle,
                  ),
                  if ((org!.domain ?? '').isNotEmpty)
                    Text(
                      org!.domain!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.tinyLabel,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(width: WebTokens.s3),
          if (org != null && onMenu != null) ...[
            _ActionsBtn(onSelected: onMenu!),
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

/// Square accent-tinted apartment glyph used as the org's leading chip in
/// the header — analogous to a `#{number}` for a resource that has no
/// numeric handle.
class _OrgChip extends StatelessWidget {
  const _OrgChip();

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.accentMuted,
        borderRadius: BorderRadius.circular(WebTokens.rSm),
      ),
      child: Icon(
        Icons.apartment,
        size: 18,
        color: t.accent,
      ),
    );
  }
}

class _ActionsBtn extends StatefulWidget {
  const _ActionsBtn({required this.onSelected});
  final Future<void> Function(String value) onSelected;

  @override
  State<_ActionsBtn> createState() => _ActionsBtnState();
}

class _ActionsBtnState extends State<_ActionsBtn> {
  bool _hover = false;

  Future<void> _open() async {
    final t = WebTokens.of(context);
    final chosen = await showAppDropdown<String>(
      context,
      entries: [
        const AppDropdownHeader<String>('Organization actions'),
        const AppDropdownItem(
          value: 'edit',
          label: 'Edit',
          icon: Icons.edit_outlined,
        ),
        const AppDropdownDivider(),
        AppDropdownItem(
          value: 'delete',
          label: 'Delete organization',
          icon: Icons.delete_outline,
          tone: t.danger,
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
// Fields table
// ---------------------------------------------------------------------------

class _FieldsTable extends StatelessWidget {
  const _FieldsTable({required this.org, required this.sidebar});
  final Organization org;

  /// True when this table is rendered inside the wide-mode right rail —
  /// drops the outer rounded card + horizontal padding so the rows sit
  /// flush inside the sidebar. The sidebar's own left border acts as the
  /// separator instead.
  final bool sidebar;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final manager = org.manager?.name.trim() ?? '';
    final sharing = (org.sharing ?? '').trim();
    final domain = (org.domain ?? '').trim();

    final rows = <Widget>[
      _FieldRow(
        icon: Icons.groups_outlined,
        label: 'Members',
        sidebar: sidebar,
        value: _TextValue(text: '${org.userCount}'),
      ),
      if (domain.isNotEmpty)
        _FieldRow(
          icon: Icons.language,
          label: 'Domain',
          sidebar: sidebar,
          value: _TextValue(text: domain),
        ),
      if (manager.isNotEmpty)
        _FieldRow(
          icon: Icons.badge_outlined,
          label: 'Manager',
          sidebar: sidebar,
          value: _TextValue(text: manager),
        ),
      if (sharing.isNotEmpty)
        _FieldRow(
          icon: Icons.share_outlined,
          label: 'Sharing',
          sidebar: sidebar,
          value: _TextValue(text: sharing),
        ),
      if (_hasFlags(org))
        _FieldRow(
          icon: Icons.local_offer_outlined,
          label: 'Flags',
          sidebar: sidebar,
          value: _FlagsValue(org: org),
        ),
      _FieldRow(
        icon: Icons.event_outlined,
        label: 'Created',
        sidebar: sidebar,
        value: _TextValue(text: Fmt.dateTime(org.created)),
      ),
      _FieldRow(
        icon: Icons.update,
        label: 'Updated',
        sidebar: sidebar,
        value: _TextValue(text: Fmt.dateTime(org.updated)),
      ),
    ];

    // Sidebar mode: wrap the field rows in a single elevated card so every
    // row sits on the same white ground against the panel's warm-paper bg.
    // Subtle shadow lifts the rail off the page.
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
                children: rows,
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WebTokens.s4),
      child: DecoratedBox(
        decoration: BoxDecoration(
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
              children: rows,
            ),
          ),
        ),
      ),
    );
  }

  static bool _hasFlags(Organization o) =>
      o.collabAll || o.collabPrimary || o.autoAssign;
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.sidebar,
  });
  final IconData icon;
  final String label;
  final Widget value;

  /// True when the row is rendered inside the wide-mode right rail. In
  /// sidebar mode the row height, icon, and label style all step up so
  /// the fields column reads as its own scannable rail rather than a
  /// squeezed footnote under the org profile card.
  final bool sidebar;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final rowHeight = sidebar ? _kSidebarRowHeight : 30.0;
    final labelStyle = sidebar
        ? t.bodyBase.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w500,
          )
        : t.bodySm.copyWith(
            color: t.textPrimary,
            fontWeight: FontWeight.w500,
          );
    // Leading icons removed — labels alone carry the meaning and the row
    // reads cleaner without the credential glyphs.
    return SizedBox(
      height: rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WebTokens.s1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _kFieldLabelWidth,
              child: Text(label, style: labelStyle),
            ),
            const SizedBox(width: WebTokens.s3),
            Expanded(child: value),
          ],
        ),
      ),
    );
  }
}

class _TextValue extends StatelessWidget {
  const _TextValue({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final base = DefaultTextStyle.of(context).style;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(
        color: t.textPrimary,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Inline flag list — colored uppercase runs, wrapped for narrow panels.
class _FlagsValue extends StatelessWidget {
  const _FlagsValue({required this.org});
  final Organization org;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final flags = <Widget>[
      if (org.collabAll)
        Text('COLLAB ALL', style: t.tinyLabel.copyWith(color: WebTokens.info)),
      if (org.collabPrimary)
        Text(
          'COLLAB PRIMARY',
          style: t.tinyLabel.copyWith(color: WebTokens.info),
        ),
      if (org.autoAssign)
        Text(
          'AUTO-ASSIGN',
          style: t.tinyLabel.copyWith(color: WebTokens.success),
        ),
    ];
    return Wrap(
      spacing: WebTokens.s3,
      runSpacing: 2,
      children: flags,
    );
  }
}

// ---------------------------------------------------------------------------
// Section subheader
// ---------------------------------------------------------------------------

class _SectionSubheader extends StatelessWidget {
  const _SectionSubheader(this.label, {this.trailing});
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
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
      child: Row(
        children: [
          Text(
            label,
            style: t.cardName.copyWith(color: t.textPrimary),
          ),
          if (trailing != null) ...[
            const SizedBox(width: WebTokens.s2),
            Text(trailing!, style: t.tinyLabel.withTabularNums()),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Custom fields
// ---------------------------------------------------------------------------

class _CustomFields extends StatelessWidget {
  const _CustomFields({required this.fields});
  final Map<String, String> fields;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(WebTokens.rMd),
        border: Border.all(color: t.borderSubtle, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(WebTokens.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in fields.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(e.key, style: t.tinyLabel),
                    ),
                    Expanded(
                      child: Text(
                        e.value,
                        style: t.bodyBase.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Member row — card per item with actor avatar and hover-revealed remove.
// ---------------------------------------------------------------------------

class _MemberRow extends StatefulWidget {
  const _MemberRow({
    required this.user,
    required this.onTap,
    required this.onRemove,
  });
  final AppUser user;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends State<_MemberRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final u = widget.user;
    final trimmed = u.name.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTokens.s4,
        WebTokens.s3,
        WebTokens.s4,
        0,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ActorAvatar(name: trimmed.isEmpty ? '?' : trimmed),
                const SizedBox(width: WebTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        trimmed.isEmpty ? '(unnamed)' : trimmed,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.cardName,
                      ),
                      if (u.email.isNotEmpty)
                        Text(
                          u.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.tinyLabel,
                        ),
                    ],
                  ),
                ),
                if (_hover) ...[
                  const SizedBox(width: WebTokens.s2),
                  _RemoveBtn(onTap: widget.onRemove),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoveBtn extends StatefulWidget {
  const _RemoveBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_RemoveBtn> createState() => _RemoveBtnState();
}

class _RemoveBtnState extends State<_RemoveBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Tooltip(
      message: 'Remove from organization',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? t.dangerLight : Colors.transparent,
              borderRadius: BorderRadius.circular(WebTokens.rXs),
            ),
            child: Icon(
              Icons.person_remove_outlined,
              size: 16,
              color: _hover ? t.danger : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ticket row — same chrome as [UserDetailPanel._TicketRow].
// ---------------------------------------------------------------------------

class _TicketRow extends StatefulWidget {
  const _TicketRow({required this.ticket, required this.onTap});
  final Ticket ticket;
  final VoidCallback onTap;

  @override
  State<_TicketRow> createState() => _TicketRowState();
}

class _TicketRowState extends State<_TicketRow> {
  bool _hover = false;

  Color _statusTone(WebTokens t) {
    final s = widget.ticket.statusName.toLowerCase();
    if (widget.ticket.isOverdue) return t.danger;
    if (s.contains('closed') || s.contains('resolved')) return t.textSecondary;
    if (s.contains('open') || s.contains('new')) return WebTokens.success;
    return WebTokens.info;
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final ticket = widget.ticket;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WebTokens.s4,
        WebTokens.s3,
        WebTokens.s4,
        0,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: t.bgTertiary,
                    borderRadius: BorderRadius.circular(WebTokens.s1),
                  ),
                  child: Text(
                    '#${ticket.number}',
                    style: t.bodySm
                        .copyWith(
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        )
                        .withTabularNums(),
                  ),
                ),
                const SizedBox(width: WebTokens.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ticket.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.cardName,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          StatusPill(
                            label: ticket.statusName,
                            color: _statusTone(t),
                            dense: true,
                          ),
                          const SizedBox(width: WebTokens.s3),
                          Text(Fmt.date(ticket.created), style: t.tinyLabel),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Note row — mirrors [UserDetailPanel._NoteRow].
// ---------------------------------------------------------------------------

class _NoteRow extends StatefulWidget {
  const _NoteRow({required this.note, required this.onDelete});
  final StaffNote note;
  final VoidCallback onDelete;

  @override
  State<_NoteRow> createState() => _NoteRowState();
}

class _NoteRowState extends State<_NoteRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final n = widget.note;
    final poster = n.staff?.name ?? 'Staff';

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
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ActorAvatar(name: poster),
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
                                poster,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.cardName
                                    .copyWith(color: t.textPrimary),
                              ),
                            ),
                            const SizedBox(width: WebTokens.s2),
                            const _TypeTag(
                              label: 'NOTE',
                              tone: WebTokens.warning,
                            ),
                            const SizedBox(width: 96),
                          ],
                        ),
                        const SizedBox(height: WebTokens.s2),
                        _NoteBody(body: n.body),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (n.created != null)
                      Text(Fmt.ago(n.created), style: t.tinyLabel),
                    if (_hover) ...[
                      const SizedBox(width: WebTokens.s2),
                      _DeleteBtn(onTap: widget.onDelete),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteBtn extends StatefulWidget {
  const _DeleteBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_DeleteBtn> createState() => _DeleteBtnState();
}

class _DeleteBtnState extends State<_DeleteBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Tooltip(
      message: 'Delete note',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? t.dangerLight : Colors.transparent,
              borderRadius: BorderRadius.circular(WebTokens.rXs),
            ),
            child: Icon(
              Icons.delete_outline,
              size: 14,
              color: _hover ? t.danger : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteBody extends StatelessWidget {
  const _NoteBody({required this.body});
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return Text('(empty)', style: t.bodySm);
    }
    if (!trimmed.contains('<')) {
      return Text(trimmed, style: t.bodyBase.copyWith(height: 1.5));
    }
    return ClipRect(
      child: HtmlWidget(
        trimmed,
        textStyle: t.bodyBase.copyWith(height: 1.5),
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
              return {
                'color': '#0037B7',
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

// ---------------------------------------------------------------------------
// Shared primitives — actor avatar mirrors ticket panel.
// ---------------------------------------------------------------------------

const _kAvatarPalette = <Color>[
  Color(0xFFF6B93B),
  Color(0xFF5DADE2),
  Color(0xFF58D68D),
  Color(0xFFAF7AC5),
  Color(0xFFF5A623),
  Color(0xFF48C9B0),
  Color(0xFFEC7063),
  Color(0xFF5D6D7E),
];

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
// Edit org dialog — modal form for name/domain
// ---------------------------------------------------------------------------

class _EditOrgDialog extends ConsumerStatefulWidget {
  const _EditOrgDialog({required this.org});
  final Organization org;

  @override
  ConsumerState<_EditOrgDialog> createState() => _EditOrgDialogState();
}

class _EditOrgDialogState extends ConsumerState<_EditOrgDialog> {
  late final _name = TextEditingController(text: widget.org.name);
  late final _domain = TextEditingController(text: widget.org.domain ?? '');
  bool _saving = false;
  String? _formError;
  final _fieldErrors = <String, String>{};

  @override
  void dispose() {
    _name.dispose();
    _domain.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _formError = null;
      _fieldErrors.clear();
    });
    try {
      await ref.read(orgsRepositoryProvider).update(widget.org.id, {
        'name': _name.text.trim(),
        'domain': _domain.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        _formError = e.fields.isEmpty ? e.message : null;
        _fieldErrors.addAll(e.fields);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return Dialog(
      backgroundColor: t.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WebTokens.rMd),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTokens.s5,
            WebTokens.s5,
            WebTokens.s5,
            WebTokens.s4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('EDIT ORGANIZATION', style: t.sectionTitle),
              const SizedBox(height: WebTokens.s3),
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: _fieldErrors['name'],
                ),
              ),
              const SizedBox(height: WebTokens.s3),
              TextField(
                controller: _domain,
                decoration: InputDecoration(
                  labelText: 'Domain',
                  errorText: _fieldErrors['domain'],
                ),
              ),
              if (_formError != null) ...[
                const SizedBox(height: WebTokens.s3),
                Text(
                  _formError!,
                  style: t.bodySm.copyWith(color: t.danger),
                ),
              ],
              const SizedBox(height: WebTokens.s4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: WebTokens.s2),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save changes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
