import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/format.dart';
import '../../../models/canned.dart';
import '../../../models/common.dart';
import '../../../providers.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/attachment_tile.dart';
import '../../../widgets/states.dart';
import '../../../widgets/web/status_pill.dart';
import '../../dashboard/web/_tokens.dart';
import 'canned_editor_dialog.dart';

/// Web-only canned-response detail panel — visual parity with
/// [TicketDetailPanel]:
///   - single-row header with a `#id` chip + title on the left and Actions
///     + Fullscreen + Close on the right;
///   - fields expressed as a left-labeled table inside one rounded card;
///   - body / notes / attachments follow.
const _kFlatRadius = 8.0;
const double _kFieldLabelWidth = 88;
const double _kSidebarRowHeight = 40;

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

class CannedDetailPanel extends ConsumerStatefulWidget {
  const CannedDetailPanel({
    super.key,
    required this.cannedId,
    required this.onClose,
    this.onChanged,
    this.isFullscreen = false,
    this.onToggleFullscreen,
  });
  final int cannedId;
  final VoidCallback onClose;
  final VoidCallback? onChanged;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  ConsumerState<CannedDetailPanel> createState() => _CannedDetailPanelState();
}

class _CannedDetailPanelState extends ConsumerState<CannedDetailPanel> {
  CannedResponse? _canned;
  List<Attachment> _attachments = const [];
  Object? _error;
  bool _loading = true;

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
    final repo = ref.read(cannedRepositoryProvider);
    try {
      final canned = await repo.get(widget.cannedId);
      final attachments = await repo.attachments(widget.cannedId);
      if (!mounted) return;
      setState(() {
        _canned = canned;
        _attachments = attachments;
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

  Future<void> _onMenu(String value) async {
    final c = _canned;
    if (c == null) return;
    final repo = ref.read(cannedRepositoryProvider);
    switch (value) {
      case 'edit':
        final saved = await showDialog<bool>(
          context: context,
          builder: (_) => CannedEditorDialog(existing: c),
        );
        if (saved == true) {
          _toast('Response updated', type: ToastType.success);
          widget.onChanged?.call();
          await _load();
        }
        return;
      case 'copy':
        await Clipboard.setData(
          ClipboardData(text: Fmt.stripHtml(c.body)),
        );
        _toast('Copied', type: ToastType.success);
        return;
      case 'delete':
        final ok = await showAppConfirmDialog(
          context,
          title: 'Delete response?',
          message: 'Delete "${c.title}"? This cannot be undone.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (ok != true) return;
        try {
          await repo.delete(widget.cannedId);
          _toast('Response deleted', type: ToastType.success);
          widget.onChanged?.call();
          widget.onClose();
        } on ApiException catch (e) {
          _toast(e.message, type: ToastType.error);
        }
        return;
    }
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
            canned: null,
            onClose: widget.onClose,
            onMenu: null,
            isFullscreen: widget.isFullscreen,
            onToggleFullscreen: widget.onToggleFullscreen,
          ),
          const Expanded(child: LoadingView()),
        ],
      );
    }
    if (_error != null || _canned == null) {
      return Column(
        children: [
          _Header(
            canned: null,
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
    final c = _canned!;
    return Column(
      children: [
        _Header(
          canned: c,
          onClose: widget.onClose,
          onMenu: _onMenu,
          isFullscreen: widget.isFullscreen,
          onToggleFullscreen: widget.onToggleFullscreen,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _kTwoColumnBreakpoint;
              if (wide) return _buildWide(t, c);
              return _buildNarrow(t, c);
            },
          ),
        ),
      ],
    );
  }

  /// Narrow single-column layout: fields card on top, then Response / Notes /
  /// Attachments stacked below. Kept for the sub-780 px slot the panel gets
  /// when the list underneath is still visible on smaller viewports.
  Widget _buildNarrow(WebTokens t, CannedResponse c) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: WebTokens.s3),
        _FieldsTable(canned: c, sidebar: false),
        const SizedBox(height: WebTokens.s2),
        const _SectionSubheader('Response'),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTokens.s4,
            WebTokens.s3,
            WebTokens.s4,
            0,
          ),
          child: _BodyCard(text: Fmt.stripHtml(c.body).trim()),
        ),
        if ((c.notes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: WebTokens.s2),
          const _SectionSubheader('Internal notes'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTokens.s4,
              WebTokens.s3,
              WebTokens.s4,
              0,
            ),
            child: _BodyCard(text: c.notes!.trim(), muted: true),
          ),
        ],
        if (_attachments.isNotEmpty) ...[
          const SizedBox(height: WebTokens.s2),
          _SectionSubheader(
            'Attachments',
            trailing: '${_attachments.length}',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTokens.s4,
              WebTokens.s3,
              WebTokens.s4,
              0,
            ),
            child: Column(
              children: [
                for (final a in _attachments) AttachmentTile(attachment: a),
              ],
            ),
          ),
        ],
        const SizedBox(height: WebTokens.s6),
      ],
    );
  }

  /// Two-column layout used at ≥ [_kTwoColumnBreakpoint] px: primary content
  /// (Response body, Internal notes, Attachments) on the left, fields
  /// sidebar on the right at [_kFieldsSidebarWidth]. A hairline seam
  /// separates the two columns — matches the reference layout where the
  /// details block sits as a fixed rail alongside the main content.
  Widget _buildWide(WebTokens t, CannedResponse c) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const _SectionSubheader('Response'),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WebTokens.s4,
                  WebTokens.s3,
                  WebTokens.s4,
                  0,
                ),
                child: _BodyCard(text: Fmt.stripHtml(c.body).trim()),
              ),
              if ((c.notes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: WebTokens.s2),
                const _SectionSubheader('Internal notes'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WebTokens.s4,
                    WebTokens.s3,
                    WebTokens.s4,
                    0,
                  ),
                  child: _BodyCard(text: c.notes!.trim(), muted: true),
                ),
              ],
              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: WebTokens.s2),
                _SectionSubheader(
                  'Attachments',
                  trailing: '${_attachments.length}',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WebTokens.s4,
                    WebTokens.s3,
                    WebTokens.s4,
                    0,
                  ),
                  child: Column(
                    children: [
                      for (final a in _attachments)
                        AttachmentTile(attachment: a),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: WebTokens.s6),
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
                _FieldsTable(canned: c, sidebar: true),
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
    required this.canned,
    required this.onClose,
    required this.onMenu,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });
  final CannedResponse? canned;
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
          if (canned == null)
            Expanded(child: Text('Loading…', style: t.cardName))
          else ...[
            _NumberChip(number: '${canned!.id}'),
            const SizedBox(width: WebTokens.s3),
            Expanded(
              child: Text(
                canned!.title.trim().isEmpty
                    ? '(untitled)'
                    : canned!.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.pageTitle,
              ),
            ),
          ],
          const SizedBox(width: WebTokens.s3),
          if (canned != null && onMenu != null) ...[
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
        borderRadius: BorderRadius.circular(WebTokens.rXs),
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
        const AppDropdownHeader<String>('Response actions'),
        const AppDropdownItem(
          value: 'edit',
          label: 'Edit',
          icon: Icons.edit_outlined,
        ),
        const AppDropdownItem(
          value: 'copy',
          label: 'Copy body',
          icon: Icons.copy_outlined,
        ),
        const AppDropdownDivider(),
        AppDropdownItem(
          value: 'delete',
          label: 'Delete response',
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
  const _FieldsTable({required this.canned, required this.sidebar});
  final CannedResponse canned;

  /// True when this table is rendered inside the wide-mode right rail —
  /// drops the outer rounded card + horizontal padding so the rows sit
  /// flush inside the sidebar. The sidebar's own left border acts as the
  /// separator instead.
  final bool sidebar;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final rows = <Widget>[
      _FieldRow(
        icon: Icons.tune,
        label: 'Scope',
        sidebar: sidebar,
        value: _TextValue(text: canned.isGlobal ? 'Global' : 'Department'),
      ),
      _FieldRow(
        icon: Icons.power_settings_new,
        label: 'Status',
        sidebar: sidebar,
        value: _StatusValuePill(
          label: canned.isEnabled ? 'Enabled' : 'Disabled',
          color: canned.isEnabled ? WebTokens.success : t.danger,
        ),
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
  /// squeezed footnote under the canned body card.
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
// Body card — bordered container for the response body and internal notes.
// ---------------------------------------------------------------------------

class _BodyCard extends StatelessWidget {
  const _BodyCard({required this.text, this.muted = false});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final empty = text.trim().isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(WebTokens.s4),
      decoration: BoxDecoration(
        color: muted ? t.bgTertiary : t.bgElevated,
        border: Border.all(color: t.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(_kFlatRadius),
      ),
      child: SelectableText(
        empty ? '—' : text,
        style: t.bodyBase.copyWith(
          color: empty ? t.textSecondary : t.textPrimary,
          height: 1.5,
        ),
      ),
    );
  }
}
