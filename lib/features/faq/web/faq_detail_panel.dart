import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../models/faq.dart';
import '../../../providers.dart';
import '../../../widgets/attachment_tile.dart';
import '../../../widgets/states.dart';
import '../../../widgets/web/status_pill.dart';
import '../../../res/zebu_text_styles.dart';
import '../../../res/zebu_theme.dart';
import '../../../res/zebu_spacing.dart';

/// Web-only KB-article detail panel — visual parity with
/// [TicketDetailPanel]:
///   - single-row header with a `#id` chip + question title on the left
///     and Fullscreen + Close on the right (no actions — read-only);
///   - fields expressed as a left-labeled table inside one rounded card;
///   - answer / notes / attachments follow as bordered body cards.
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

class FaqDetailPanel extends ConsumerStatefulWidget {
  const FaqDetailPanel({
    super.key,
    required this.faqId,
    required this.onClose,
    this.isFullscreen = false,
    this.onToggleFullscreen,
  });
  final int faqId;
  final VoidCallback onClose;
  final bool isFullscreen;
  final VoidCallback? onToggleFullscreen;

  @override
  ConsumerState<FaqDetailPanel> createState() => _FaqDetailPanelState();
}

class _FaqDetailPanelState extends ConsumerState<FaqDetailPanel> {
  Faq? _faq;
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
    try {
      final faq = await ref.read(faqRepositoryProvider).get(widget.faqId);
      if (!mounted) return;
      setState(() {
        _faq = faq;
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

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return Material(
      // Warm-paper ground so the panel matches the list surface behind it.
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
            faq: null,
            onClose: widget.onClose,
            isFullscreen: widget.isFullscreen,
            onToggleFullscreen: widget.onToggleFullscreen,
          ),
          const Expanded(child: LoadingView()),
        ],
      );
    }
    if (_error != null || _faq == null) {
      return Column(
        children: [
          _Header(
            faq: null,
            onClose: widget.onClose,
            isFullscreen: widget.isFullscreen,
            onToggleFullscreen: widget.onToggleFullscreen,
          ),
          Expanded(
            child: ErrorView(error: _error ?? 'Not found', onRetry: _load),
          ),
        ],
      );
    }
    final f = _faq!;
    return Column(
      children: [
        _Header(
          faq: f,
          onClose: widget.onClose,
          isFullscreen: widget.isFullscreen,
          onToggleFullscreen: widget.onToggleFullscreen,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _kTwoColumnBreakpoint;
              if (wide) return _buildWide(t, f);
              return _buildNarrow(t, f);
            },
          ),
        ),
      ],
    );
  }

  /// Narrow single-column layout: fields card on top, then Answer / Notes /
  /// Attachments stacked below. Kept for the sub-780 px slot the panel gets
  /// when the list underneath is still visible on smaller viewports.
  Widget _buildNarrow(ZebuTheme t, Faq f) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: ZebuSpacing.s3),
        _FieldsTable(faq: f, sidebar: false),
        const SizedBox(height: ZebuSpacing.s2),
        const _SectionSubheader('Answer'),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ZebuSpacing.s4,
            ZebuSpacing.s3,
            ZebuSpacing.s4,
            0,
          ),
          child: _BodyCard(text: Fmt.stripHtml(f.answer).trim()),
        ),
        if ((f.notes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: ZebuSpacing.s2),
          const _SectionSubheader('Internal notes'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZebuSpacing.s4,
              ZebuSpacing.s3,
              ZebuSpacing.s4,
              0,
            ),
            child: _BodyCard(text: f.notes!.trim(), muted: true),
          ),
        ],
        if (f.attachments.isNotEmpty) ...[
          const SizedBox(height: ZebuSpacing.s2),
          _SectionSubheader('Attachments', trailing: '${f.attachments.length}'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZebuSpacing.s4,
              ZebuSpacing.s3,
              ZebuSpacing.s4,
              0,
            ),
            child: Column(
              children: [
                for (final a in f.attachments) AttachmentTile(attachment: a),
              ],
            ),
          ),
        ],
        const SizedBox(height: ZebuSpacing.s6),
      ],
    );
  }

  /// Two-column layout used at ≥ [_kTwoColumnBreakpoint] px: primary content
  /// (Answer body, Internal notes, Attachments) on the left, fields sidebar
  /// on the right at [_kFieldsSidebarWidth]. A hairline seam separates the
  /// two columns — matches the reference layout where the details block
  /// sits as a fixed rail alongside the main content.
  Widget _buildWide(ZebuTheme t, Faq f) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const _SectionSubheader('Answer'),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ZebuSpacing.s4,
                  ZebuSpacing.s3,
                  ZebuSpacing.s4,
                  0,
                ),
                child: _BodyCard(text: Fmt.stripHtml(f.answer).trim()),
              ),
              if ((f.notes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: ZebuSpacing.s2),
                const _SectionSubheader('Internal notes'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZebuSpacing.s4,
                    ZebuSpacing.s3,
                    ZebuSpacing.s4,
                    0,
                  ),
                  child: _BodyCard(text: f.notes!.trim(), muted: true),
                ),
              ],
              if (f.attachments.isNotEmpty) ...[
                const SizedBox(height: ZebuSpacing.s2),
                _SectionSubheader(
                  'Attachments',
                  trailing: '${f.attachments.length}',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ZebuSpacing.s4,
                    ZebuSpacing.s3,
                    ZebuSpacing.s4,
                    0,
                  ),
                  child: Column(
                    children: [
                      for (final a in f.attachments)
                        AttachmentTile(attachment: a),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: ZebuSpacing.s6),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: t.borderSubtle, width: 1)),
          ),
          child: SizedBox(
            width: _kFieldsSidebarWidth,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: ZebuSpacing.s4),
              children: [_FieldsTable(faq: f, sidebar: true)],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header — read-only (no Actions button); FS + destructive Close only.
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.faq,
    required this.onClose,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });
  final Faq? faq;
  final VoidCallback onClose;
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (faq == null)
            Expanded(
              child: Text(
                'Loading…',
                style: ZebuTextStyles.smallStrong(context),
              ),
            )
          else ...[
            _NumberChip(number: '${faq!.id}'),
            const SizedBox(width: ZebuSpacing.s3),
            Expanded(
              child: Text(
                faq!.question.trim().isEmpty ? '(untitled)' : faq!.question,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZebuTextStyles.pageTitle(context),
              ),
            ),
          ],
          const SizedBox(width: ZebuSpacing.s3),
          if (onToggleFullscreen != null) ...[
            _IconBtn(
              icon: isFullscreen ? Icons.close_fullscreen : Icons.open_in_full,
              tooltip: isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
              onTap: onToggleFullscreen!,
            ),
            const SizedBox(width: ZebuSpacing.s2),
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
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.bgTertiary,
        borderRadius: BorderRadius.circular(ZebuRadius.rXs),
      ),
      child: Text(
        '#$number',
        style: ZebuTextStyles.small(context)
            .copyWith(fontWeight: FontWeight.w600, color: t.textPrimary)
            .withTabularNums(),
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

// ---------------------------------------------------------------------------
// Fields table
// ---------------------------------------------------------------------------

class _FieldsTable extends StatelessWidget {
  const _FieldsTable({required this.faq, required this.sidebar});
  final Faq faq;

  /// True when this table is rendered inside the wide-mode right rail —
  /// drops the outer rounded card + horizontal padding so the rows sit
  /// flush inside the sidebar. The sidebar's own left border acts as the
  /// separator instead.
  final bool sidebar;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final type = (faq.type ?? '').trim();
    final categoryName = faq.category?.name.trim() ?? '';

    final rows = <Widget>[
      _FieldRow(
        icon: Icons.visibility_outlined,
        label: 'Visibility',
        sidebar: sidebar,
        value: _StatusValuePill(
          label: faq.published ? 'Public' : 'Internal',
          color: faq.published ? ZebuTheme.success : ZebuTheme.info,
        ),
      ),
      if (type.isNotEmpty)
        _FieldRow(
          icon: Icons.category_outlined,
          label: 'Type',
          sidebar: sidebar,
          value: _TextValue(text: type),
        ),
      if (categoryName.isNotEmpty)
        _FieldRow(
          icon: Icons.folder_outlined,
          label: 'Category',
          sidebar: sidebar,
          value: _TextValue(text: categoryName),
        ),
      _FieldRow(
        icon: Icons.event_outlined,
        label: 'Created',
        sidebar: sidebar,
        value: _TextValue(text: Fmt.dateTime(faq.created)),
      ),
      _FieldRow(
        icon: Icons.update,
        label: 'Updated',
        sidebar: sidebar,
        value: _TextValue(text: Fmt.dateTime(faq.updated)),
      ),
    ];

    // Sidebar mode: wrap the field rows in a single elevated card so every
    // row sits on the same white ground against the panel's warm-paper bg.
    // Subtle shadow lifts the rail off the page.
    if (sidebar) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          ZebuSpacing.s3,
          0,
          ZebuSpacing.s3,
          ZebuSpacing.s3,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.bgElevated,
            borderRadius: BorderRadius.circular(ZebuRadius.rMd),
            border: Border.all(color: t.borderSubtle, width: 1),
            boxShadow: ZebuElevation.shadowXs,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ZebuSpacing.s3,
              vertical: ZebuSpacing.s2,
            ),
            child: DefaultTextStyle.merge(
              style: ZebuTextStyles.body(
                context,
              ).copyWith(color: t.textPrimary),
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
      padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s4),
      child: DecoratedBox(
        decoration: BoxDecoration(
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
  /// squeezed footnote under the FAQ body card.
  final bool sidebar;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final rowHeight = sidebar ? _kSidebarRowHeight : 30.0;
    final labelStyle = sidebar
        ? ZebuTextStyles.body(
            context,
          ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w500)
        : ZebuTextStyles.small(
            context,
          ).copyWith(color: t.textPrimary, fontWeight: FontWeight.w500);
    // Leading icons removed — labels alone carry the meaning and the row
    // reads cleaner without the credential glyphs.
    return SizedBox(
      height: rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZebuSpacing.s1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _kFieldLabelWidth,
              child: Text(label, style: labelStyle),
            ),
            const SizedBox(width: ZebuSpacing.s3),
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
    final t = ZebuTheme.of(context);
    final base = DefaultTextStyle.of(context).style;
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: base.copyWith(color: t.textPrimary, fontWeight: FontWeight.w500),
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
    final t = ZebuTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s4,
        vertical: ZebuSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: t.bgElevated,
        border: Border(top: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: ZebuTextStyles.smallStrong(
              context,
            ).copyWith(color: t.textPrimary),
          ),
          if (trailing != null) ...[
            const SizedBox(width: ZebuSpacing.s2),
            Text(
              trailing!,
              style: ZebuTextStyles.label(context).withTabularNums(),
            ),
          ],
        ],
      ),
    );
  }
}

class _BodyCard extends StatelessWidget {
  const _BodyCard({required this.text, this.muted = false});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final empty = text.trim().isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ZebuSpacing.s4),
      decoration: BoxDecoration(
        color: muted ? t.bgTertiary : t.bgElevated,
        border: Border.all(color: t.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(_kFlatRadius),
      ),
      child: SelectableText(
        empty ? '—' : text,
        style: ZebuTextStyles.body(
          context,
        ).copyWith(color: empty ? t.textSecondary : t.textPrimary, height: 1.5),
      ),
    );
  }
}
