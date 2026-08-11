import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format.dart';
import '../../../core/router/routes.dart';
import '../../../models/organization.dart';
import '../../../providers.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/paged_list_view.dart';
import '../../../widgets/slide_over_host.dart';
import '../../../widgets/web/list_search_input.dart';
import '../../../widgets/web/list_table_shell.dart';
import '../../../widgets/web/page_header.dart';
import 'org_detail_panel.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

const _kFlatRadius = 8.0;

// Column layout — header and rows share these so the vertical grid lines
// up pixel-for-pixel. Mirrors the tickets table cell API.
const int _kColOrgFlex = 4;
const int _kColDomainFlex = 3;
const double _kColMembersWidth = 120;
const double _kColCreatedWidth = 120;

/// Minimum table width. Below this, the table horizontally scrolls.
const double _kTableMinWidth = 900;

/// Web-only organizations list, styled to match [UsersListScreenWeb] and
/// [TicketsListScreenWeb]: premium hero header, right-aligned search
/// input, and an edge-to-edge table (header strip + one row per org)
/// with hover / select tints.
class OrgsListScreenWeb extends ConsumerStatefulWidget {
  const OrgsListScreenWeb({super.key});

  @override
  ConsumerState<OrgsListScreenWeb> createState() => _OrgsListScreenWebState();
}

class _OrgsListScreenWebState extends ConsumerState<OrgsListScreenWeb> {
  String _search = '';
  Timer? _debounce;
  int _refreshKey = 0;
  int? _total;
  int? _openOrgId;
  bool _fullscreen = false;

  // Shared horizontal scroll controller for the table (header + rows).
  // Mirrors the tickets/users table: when the slide-over panel drops the
  // list area below `_kTableMinWidth`, the whole table scrolls
  // horizontally together under a single controller.
  final ScrollController _tableHScroll = ScrollController();

  void _openOrg(int id) => setState(() => _openOrgId = id);
  // Reset fullscreen on close so re-opening starts in split view.
  void _closeOrg() => setState(() {
    _openOrgId = null;
    _fullscreen = false;
  });
  void _toggleFullscreen() => setState(() => _fullscreen = !_fullscreen);

  /// Invoked by the panel after any mutation (edit / delete / notes /
  /// members) so stale rows in the list refresh without a manual
  /// pull-to-refresh.
  void _onOrgChanged() {
    if (mounted) setState(() => _refreshKey++);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tableHScroll.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final next = value.trim();
      if (next != _search && mounted) {
        setState(() {
          _search = next;
          _refreshKey++;
        });
      }
    });
  }

  Future<void> _openCreate() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreateOrgDialog(),
    );
    if (created == true && mounted) {
      AppToast.show(context, 'Organization created', type: ToastType.success);
      setState(() => _refreshKey++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final repo = ref.watch(orgsRepositoryProvider);

    return SlideOverHost(
      openId: _openOrgId,
      onClose: _closeOrg,
      fullscreen: _fullscreen,
      panelBuilder: (context, id, close) => OrgDetailPanel(
        orgId: id,
        onClose: close,
        onChanged: _onOrgChanged,
        isFullscreen: _fullscreen,
        onToggleFullscreen: _toggleFullscreen,
      ),
      child: ColoredBox(
        color: t.bgPrimary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: 'Organizations',
              subtitle: _total != null ? '$_total total' : null,
              leading: _BackButton(
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(Routes.more);
                  }
                },
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 280,
                    child: ListSearchInput(
                      hintText: 'Search name or domain…',
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  const SizedBox(width: ZebuSpacing.s3),
                  _NewOrgButton(onTap: _openCreate),
                ],
              ),
            ),
            Expanded(
              child: ListTableShell(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final horizontalScroll =
                        constraints.maxWidth <= _kTableMinWidth;
                    final tableWidth = horizontalScroll
                        ? _kTableMinWidth
                        : constraints.maxWidth;
                    return Scrollbar(
                      controller: _tableHScroll,
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      child: SingleChildScrollView(
                        controller: _tableHScroll,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: tableWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _TableHeader(scrollGutter: horizontalScroll),
                              Expanded(
                                child: ColoredBox(
                                  color: t.bgElevated,
                                  child: PagedListView<Organization>(
                                    padding: EdgeInsets.zero,
                                    refreshKey: '$_search|$_refreshKey',
                                    emptyMessage: 'No organizations',
                                    emptyHint: 'Try a different search.',
                                    emptyIcon: Icons.apartment,
                                    onTotalChanged: (v) {
                                      if (mounted && v != _total) {
                                        setState(() => _total = v);
                                      }
                                    },
                                    fetch: (page) => repo.list(
                                      q: _search.isEmpty ? null : _search,
                                      page: page,
                                    ),
                                    itemBuilder: (context, o) => _OrgRow(
                                      org: o,
                                      selected: _openOrgId == o.id,
                                      onTap: () => _openOrg(o.id),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Back button — small ghost square matching top-bar action treatment.
// ---------------------------------------------------------------------------

class _BackButton extends StatefulWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Tooltip(
      message: 'Back',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? t.bgHover : t.bgElevated,
              borderRadius: BorderRadius.circular(ZebuRadius.rSm),
              border: Border.all(color: t.borderSubtle, width: 1),
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: t.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// New-org button — accent-tinted pill with icon + label, replaces the
// mobile FloatingActionButton.
// ---------------------------------------------------------------------------

class _NewOrgButton extends StatefulWidget {
  const _NewOrgButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_NewOrgButton> createState() => _NewOrgButtonState();
}

class _NewOrgButtonState extends State<_NewOrgButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final bg = _hover ? t.accentHover : t.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(ZebuRadius.rSm),
            boxShadow: _hover
                ? const [
                    BoxShadow(
                      color: Color(0x330037B7),
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.add_rounded,
                size: 18,
                color: ZebuTheme.textInverse,
              ),
              const SizedBox(width: 6),
              Text(
                'New organization',
                style: ZebuTextStyles.body(context).copyWith(
                  color: ZebuTheme.textInverse,
                  fontWeight: FontWeight.w600,
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
// Table header — matches the tickets table: edge-to-edge, hairline
// top/bottom borders, and per-column right-border creating the vertical
// grid line that body rows align to pixel-for-pixel.
// ---------------------------------------------------------------------------

class _TableHeader extends StatelessWidget {
  const _TableHeader({this.scrollGutter = false});

  final bool scrollGutter;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(
          top: BorderSide(color: t.borderSubtle, width: 1),
          bottom: BorderSide(color: t.borderSubtle, width: 1),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            const _HeaderCell(flex: _kColOrgFlex, label: 'Organization'),
            const _HeaderCell(flex: _kColDomainFlex, label: 'Domain'),
            const _HeaderCell(
              width: _kColMembersWidth,
              label: 'Members',
              alignRight: true,
            ),
            const _HeaderCell(
              width: _kColCreatedWidth,
              label: 'Created',
              alignRight: true,
              last: true,
            ),
            if (scrollGutter) const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

/// Column header cell — mirrors the tickets `_HeaderCell`.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    this.flex,
    this.width,
    this.last = false,
    this.alignRight = false,
  });
  final String label;
  final int? flex;
  final double? width;
  final bool last;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: ZebuSpacing.s3,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(right: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: ZebuTextStyles.tableHeader(context),
        textAlign: alignRight ? TextAlign.right : TextAlign.left,
      ),
    );
    if (flex != null) return Expanded(flex: flex!, child: content);
    if (width != null) return SizedBox(width: width!, child: content);
    return content;
  }
}

/// Body cell — mirrors the tickets `_BodyCell`.
class _BodyCell extends StatelessWidget {
  const _BodyCell({
    required this.child,
    this.flex,
    this.width,
    this.last = false,
    this.alignRight = false,
  });
  final Widget child;
  final int? flex;
  final double? width;
  final bool last;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(right: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
    if (flex != null) return Expanded(flex: flex!, child: content);
    if (width != null) return SizedBox(width: width!, child: content);
    return content;
  }
}

// ---------------------------------------------------------------------------
// Org row — one single-line row per org, columns aligned with
// [_TableHeader]. Hover tint + selected-accent-tint match the users/tickets
// treatment.
// ---------------------------------------------------------------------------

class _OrgRow extends StatefulWidget {
  const _OrgRow({
    required this.org,
    required this.onTap,
    this.selected = false,
  });
  final Organization org;
  final VoidCallback onTap;
  final bool selected;

  @override
  State<_OrgRow> createState() => _OrgRowState();
}

class _OrgRowState extends State<_OrgRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final o = widget.org;
    final trimmed = o.name.trim();
    final domain = (o.domain ?? '').trim();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            color: widget.selected
                ? t.accentMuted
                : (_hover ? t.bgHover : t.bgElevated),
            border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BodyCell(
                  flex: _kColOrgFlex,
                  child: Text(
                    trimmed.isEmpty ? '(unnamed)' : trimmed,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ZebuTextStyles.body(
                      context,
                    ).copyWith(fontWeight: FontWeight.w500),
                  ),
                ),
                _BodyCell(
                  flex: _kColDomainFlex,
                  child: _TextCell(text: domain),
                ),
                _BodyCell(
                  width: _kColMembersWidth,
                  alignRight: true,
                  child: Text(
                    '${o.userCount}',
                    textAlign: TextAlign.right,
                    style: ZebuTextStyles.small(context)
                        .copyWith(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w500,
                        )
                        .withTabularNums(),
                  ),
                ),
                _BodyCell(
                  width: _kColCreatedWidth,
                  last: true,
                  alignRight: true,
                  child: Text(
                    Fmt.date(o.created),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    textAlign: TextAlign.right,
                    style: ZebuTextStyles.small(context)
                        .copyWith(
                          color: t.textPrimary,
                          fontWeight: FontWeight.w500,
                        )
                        .withTabularNums(),
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

class _TextCell extends StatelessWidget {
  const _TextCell({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final empty = text.trim().isEmpty;
    return Text(
      empty ? '—' : text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ZebuTextStyles.small(context).copyWith(
        color: empty ? t.textSecondary : t.textPrimary,
        fontWeight: empty ? FontWeight.w400 : FontWeight.w500,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create-org dialog — modal counterpart to the mobile bottom-sheet.
// ---------------------------------------------------------------------------

class _CreateOrgDialog extends ConsumerStatefulWidget {
  const _CreateOrgDialog();

  @override
  ConsumerState<_CreateOrgDialog> createState() => _CreateOrgDialogState();
}

class _CreateOrgDialogState extends ConsumerState<_CreateOrgDialog> {
  final _name = TextEditingController();
  final _domain = TextEditingController();
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
      final domain = _domain.text.trim();
      await ref.read(orgsRepositoryProvider).create({
        'name': _name.text.trim(),
        if (domain.isNotEmpty) 'domain': domain,
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
    final t = ZebuTheme.of(context);
    return AlertDialog(
      backgroundColor: t.bgElevated,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZebuRadius.rMd),
        side: BorderSide(color: t.borderSubtle, width: 1),
      ),
      titlePadding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s5,
        ZebuSpacing.s5,
        ZebuSpacing.s5,
        ZebuSpacing.s3,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s5,
        0,
        ZebuSpacing.s5,
        ZebuSpacing.s4,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s5,
        0,
        ZebuSpacing.s5,
        ZebuSpacing.s4,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'New organization',
              style: ZebuTextStyles.pageTitle(context),
            ),
          ),
          _DialogCloseButton(
            onTap: _saving ? null : () => Navigator.pop(context, false),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FieldLabel(text: 'Name'),
            const SizedBox(height: 6),
            _ThemedTextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              hasError: _fieldErrors['name'] != null,
            ),
            if (_fieldErrors['name'] != null) ...[
              const SizedBox(height: 4),
              Text(
                _fieldErrors['name']!,
                style: ZebuTextStyles.small(context).copyWith(color: t.danger),
              ),
            ],
            const SizedBox(height: ZebuSpacing.s3),
            _FieldLabel(text: 'Domain (optional)'),
            const SizedBox(height: 6),
            _ThemedTextField(
              controller: _domain,
              hint: 'example.com',
              hasError: _fieldErrors['domain'] != null,
            ),
            if (_fieldErrors['domain'] != null) ...[
              const SizedBox(height: 4),
              Text(
                _fieldErrors['domain']!,
                style: ZebuTextStyles.small(context).copyWith(color: t.danger),
              ),
            ],
            if (_formError != null) ...[
              const SizedBox(height: ZebuSpacing.s3),
              _CreateErrorBanner(message: _formError!),
            ],
          ],
        ),
      ),
      actions: [
        _DialogSecondaryButton(
          label: 'Cancel',
          onTap: _saving ? null : () => Navigator.pop(context, false),
        ),
        const SizedBox(width: ZebuSpacing.s2),
        _DialogPrimaryButton(
          label: 'Create organization',
          busy: _saving,
          onTap: _saving ? null : _save,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog primitives — inlined so this file stays self-contained but visually
// matches the [_EditProfileDialog] chrome (ZebuTheme colors, flat radius,
// brand-blue primary).
// ---------------------------------------------------------------------------

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Text(
      text,
      style: ZebuTextStyles.small(
        context,
      ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w600),
    );
  }
}

class _ThemedTextField extends StatelessWidget {
  const _ThemedTextField({
    required this.controller,
    this.hint,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.hasError = false,
  });

  final TextEditingController controller;
  final String? hint;
  final bool autofocus;
  final TextCapitalization textCapitalization;
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
      autofocus: autofocus,
      textCapitalization: textCapitalization,
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

class _CreateErrorBanner extends StatelessWidget {
  const _CreateErrorBanner({required this.message});
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

class _DialogCloseButton extends StatefulWidget {
  const _DialogCloseButton({required this.onTap});
  final VoidCallback? onTap;

  @override
  State<_DialogCloseButton> createState() => _DialogCloseButtonState();
}

class _DialogCloseButtonState extends State<_DialogCloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final disabled = widget.onTap == null;
    return Tooltip(
      message: 'Close',
      child: MouseRegion(
        cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
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
              color: _hover && !disabled ? t.bgHover : t.bgTertiary,
              borderRadius: BorderRadius.circular(ZebuRadius.rSm),
            ),
            child: Icon(Icons.close, size: 16, color: t.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _DialogSecondaryButton extends StatefulWidget {
  const _DialogSecondaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  State<_DialogSecondaryButton> createState() => _DialogSecondaryButtonState();
}

class _DialogSecondaryButtonState extends State<_DialogSecondaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final disabled = widget.onTap == null;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
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
            color: _hover && !disabled ? t.bgHover : t.bgElevated,
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

class _DialogPrimaryButton extends StatefulWidget {
  const _DialogPrimaryButton({
    required this.label,
    required this.onTap,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  State<_DialogPrimaryButton> createState() => _DialogPrimaryButtonState();
}

class _DialogPrimaryButtonState extends State<_DialogPrimaryButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final disabled = widget.onTap == null;
    final base = disabled ? t.accent.withValues(alpha: 0.4) : t.accent;
    final fill = _hover && !disabled
        ? Color.lerp(base, Colors.black, 0.08) ?? base
        : base;
    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
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
            color: fill,
            borderRadius: BorderRadius.circular(_kFlatRadius),
          ),
          child: widget.busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
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
