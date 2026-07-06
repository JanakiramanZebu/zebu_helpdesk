import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../models/faq.dart';
import '../../../providers.dart';
import '../../../widgets/attachment_tile.dart';
import '../../../widgets/states.dart';
import '../../../widgets/web/status_pill.dart';
import '../../dashboard/web/_tokens.dart';

/// Web-only KB-article detail panel — visual parity with
/// [TicketDetailPanel]:
///   - single-row header with a `#id` chip + question title on the left
///     and Fullscreen + Close on the right (no actions — read-only);
///   - fields expressed as a left-labeled table inside one rounded card;
///   - answer / notes / attachments follow as bordered body cards.
const _kFlatRadius = 8.0;
const double _kFieldLabelWidth = 88;

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
    final t = WebTokens.of(context);
    return Material(
      color: t.bgElevated,
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
  Widget _buildNarrow(WebTokens t, Faq f) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: WebTokens.s3),
        _FieldsTable(faq: f, sidebar: false),
        const SizedBox(height: WebTokens.s2),
        const _SectionSubheader('Answer'),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WebTokens.s4,
            WebTokens.s3,
            WebTokens.s4,
            0,
          ),
          child: _BodyCard(text: Fmt.stripHtml(f.answer).trim()),
        ),
        if ((f.notes ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: WebTokens.s2),
          const _SectionSubheader('Internal notes'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WebTokens.s4,
              WebTokens.s3,
              WebTokens.s4,
              0,
            ),
            child: _BodyCard(text: f.notes!.trim(), muted: true),
          ),
        ],
        if (f.attachments.isNotEmpty) ...[
          const SizedBox(height: WebTokens.s2),
          _SectionSubheader(
            'Attachments',
            trailing: '${f.attachments.length}',
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
                for (final a in f.attachments)
                  AttachmentTile(attachment: a),
              ],
            ),
          ),
        ],
        const SizedBox(height: WebTokens.s6),
      ],
    );
  }

  /// Two-column layout used at ≥ [_kTwoColumnBreakpoint] px: primary content
  /// (Answer body, Internal notes, Attachments) on the left, fields sidebar
  /// on the right at [_kFieldsSidebarWidth]. A hairline seam separates the
  /// two columns — matches the reference layout where the details block
  /// sits as a fixed rail alongside the main content.
  Widget _buildWide(WebTokens t, Faq f) {
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
                  WebTokens.s4,
                  WebTokens.s3,
                  WebTokens.s4,
                  0,
                ),
                child: _BodyCard(text: Fmt.stripHtml(f.answer).trim()),
              ),
              if ((f.notes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: WebTokens.s2),
                const _SectionSubheader('Internal notes'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WebTokens.s4,
                    WebTokens.s3,
                    WebTokens.s4,
                    0,
                  ),
                  child: _BodyCard(text: f.notes!.trim(), muted: true),
                ),
              ],
              if (f.attachments.isNotEmpty) ...[
                const SizedBox(height: WebTokens.s2),
                _SectionSubheader(
                  'Attachments',
                  trailing: '${f.attachments.length}',
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
                      for (final a in f.attachments)
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
                _FieldsTable(faq: f, sidebar: true),
              ],
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
          if (faq == null)
            Expanded(child: Text('Loading…', style: t.cardName))
          else ...[
            _NumberChip(number: '${faq!.id}'),
            const SizedBox(width: WebTokens.s3),
            Expanded(
              child: Text(
                faq!.question.trim().isEmpty
                    ? '(untitled)'
                    : faq!.question,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.pageTitle,
              ),
            ),
          ],
          const SizedBox(width: WebTokens.s3),
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
        ? WebTokens.danger
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
  const _FieldsTable({required this.faq, required this.sidebar});
  final Faq faq;

  /// True when this table is rendered inside the wide-mode right rail —
  /// drops the outer rounded card + horizontal padding so the rows sit
  /// flush inside the sidebar. The sidebar's own left border acts as the
  /// separator instead.
  final bool sidebar;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    final type = (faq.type ?? '').trim();
    final categoryName = faq.category?.name.trim() ?? '';

    final rows = <Widget>[
      _FieldRow(
        icon: Icons.visibility_outlined,
        label: 'Visibility',
        value: _StatusValuePill(
          label: faq.published ? 'Public' : 'Internal',
          color: faq.published ? WebTokens.success : WebTokens.info,
        ),
      ),
      if (type.isNotEmpty)
        _FieldRow(
          icon: Icons.category_outlined,
          label: 'Type',
          value: _TextValue(text: type),
        ),
      if (categoryName.isNotEmpty)
        _FieldRow(
          icon: Icons.folder_outlined,
          label: 'Category',
          value: _TextValue(text: categoryName),
        ),
      _FieldRow(
        icon: Icons.event_outlined,
        label: 'Created',
        value: _TextValue(text: Fmt.dateTime(faq.created)),
      ),
      _FieldRow(
        icon: Icons.update,
        label: 'Updated',
        value: _TextValue(text: Fmt.dateTime(faq.updated)),
      ),
    ];

    if (sidebar) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: WebTokens.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
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
  });
  final IconData icon;
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final t = WebTokens.of(context);
    return SizedBox(
      height: 30,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WebTokens.s1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: t.textPrimary),
            const SizedBox(width: WebTokens.s3),
            SizedBox(
              width: _kFieldLabelWidth,
              child: Text(
                label,
                style: t.bodySm.copyWith(
                  color: t.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
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
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: t.bodySm.copyWith(
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
