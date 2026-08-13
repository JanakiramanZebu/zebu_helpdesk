import 'package:flutter/material.dart';

import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';
import 'anchored_popover.dart';
import 'zebu_text_action.dart';

/// A popover that picks from a list you have to *read* before choosing:
/// titles on the left, the full body of the highlighted one on the right.
///
/// The canned-response picker was a centred dialog, and it had to be — a
/// 190 px menu row cannot show a paragraph, and choosing a reply you have not
/// read is how the wrong one gets sent. A preview pane answers that without
/// the scrim, so the picker can sit under the link that opened it like every
/// other picker in the form.
///
/// Highlighting is not choosing: moving down the list only changes what the
/// right pane shows. [confirmLabel] commits.
Future<T?> showZebuPreviewPicker<T>(
  BuildContext anchorContext, {
  required List<ZebuPreviewItem<T>> items,
  String searchHint = 'Search',
  String confirmLabel = 'Insert',
  String? footnote,
  double width = 590,
  double maxHeight = 300,
}) {
  final overlay = zebuOverlayBox(anchorContext);
  if (overlay == null) return Future<T?>.value();
  final anchor = zebuAnchorRect(anchorContext, overlay);
  if (anchor == null) return Future<T?>.value();

  return Navigator.of(anchorContext, rootNavigator: true).push<T>(
    ZebuAnchoredRoute<T>(
      anchor: anchor,
      overlaySize: overlay.size,
      width: width,
      estimatedHeight: maxHeight + 96,
      builder: (_) => _PreviewPanel<T>(
        items: items,
        searchHint: searchHint,
        confirmLabel: confirmLabel,
        footnote: footnote,
        width: width,
        maxHeight: maxHeight,
      ),
    ),
  );
}

class ZebuPreviewItem<T> {
  const ZebuPreviewItem({
    required this.value,
    required this.title,
    required this.body,
  });

  final T value;
  final String title;

  /// Shown in full on the right, and as a one-line teaser under the title on
  /// the left. Plain text — strip markup before passing it in.
  final String body;
}

class _PreviewPanel<T> extends StatefulWidget {
  const _PreviewPanel({
    required this.items,
    required this.searchHint,
    required this.confirmLabel,
    required this.footnote,
    required this.width,
    required this.maxHeight,
  });

  final List<ZebuPreviewItem<T>> items;
  final String searchHint;
  final String confirmLabel;
  final String? footnote;
  final double width;
  final double maxHeight;

  @override
  State<_PreviewPanel<T>> createState() => _PreviewPanelState<T>();
}

class _PreviewPanelState<T> extends State<_PreviewPanel<T>> {
  final _query = TextEditingController();
  T? _highlighted;

  @override
  void initState() {
    super.initState();
    // Open on the first row rather than an empty right pane — a blank half
    // reads as broken, and the top row is the one you are about to read.
    if (widget.items.isNotEmpty) _highlighted = widget.items.first.value;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<ZebuPreviewItem<T>> get _visible {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    // Titles *and* bodies: you often remember a phrase from a reply without
    // remembering what it was filed under.
    return [
      for (final i in widget.items)
        if (i.title.toLowerCase().contains(q) ||
            i.body.toLowerCase().contains(q))
          i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final rows = _visible;
    final current = rows.isEmpty
        ? null
        : rows.firstWhere(
            (i) => i.value == _highlighted,
            orElse: () => rows.first,
          );

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: widget.width,
          maxHeight: widget.maxHeight + 96,
        ),
        decoration: BoxDecoration(
          color: zebuPopoverPanel(t),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: zebuPopoverEdge(t)),
          boxShadow: kZebuPopoverShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: ZebuPopoverSearch(
                controller: _query,
                hint: widget.searchHint,
                onChanged: (_) => setState(() {}),
              ),
            ),
            Flexible(
              child: rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(ZebuSpacing.s4),
                      child: Text(
                        'No matches',
                        style: ZebuTextStyles.small(
                          context,
                          color: zebuPopoverInkMuted(t),
                        ).copyWith(fontSize: 13),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: widget.width * 0.36,
                          child: _List<T>(
                            items: rows,
                            highlighted: current?.value,
                            onHighlight: (v) =>
                                setState(() => _highlighted = v),
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: zebuPopoverEdge(t),
                        ),
                        Expanded(child: _Preview(item: current)),
                      ],
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(
                ZebuSpacing.s4,
                ZebuSpacing.s2,
                ZebuSpacing.s2,
                ZebuSpacing.s2,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: zebuPopoverEdge(t), width: 1),
                ),
              ),
              child: Row(
                children: [
                  if (widget.footnote != null)
                    // Says what the button will do before it is pressed —
                    // "Insert" alone leaves you guessing whether it replaces
                    // what you have already typed.
                    Expanded(
                      child: Text(
                        widget.footnote!,
                        style: ZebuTextStyles.small(
                          context,
                          color: zebuPopoverInkMuted(t),
                        ).copyWith(fontSize: 12),
                      ),
                    )
                  else
                    const Spacer(),
                  ZebuTextAction(
                    label: widget.confirmLabel,
                    fontSize: 13,
                    onTap: current == null
                        ? null
                        : () => Navigator.of(context).pop(current.value),
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

class _List<T> extends StatelessWidget {
  const _List({
    required this.items,
    required this.highlighted,
    required this.onHighlight,
  });

  final List<ZebuPreviewItem<T>> items;
  final T? highlighted;
  final ValueChanged<T> onHighlight;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in items)
          _Row<T>(
            item: i,
            active: i.value == highlighted,
            onTap: () => onHighlight(i.value),
          ),
      ],
    ),
  );
}

class _Row<T> extends StatefulWidget {
  const _Row({required this.item, required this.active, required this.onTap});
  final ZebuPreviewItem<T> item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_Row<T>> createState() => _RowState<T>();
}

class _RowState<T> extends State<_Row<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final bg = widget.active
        ? zebuPopoverSelectedBg(t)
        : (_hover
              ? zebuPopoverHoverBg(t)
              : zebuPopoverHoverBg(t).withValues(alpha: 0));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            // Plain ellipsis, no tooltips. The pane on the right already
            // shows this row's title and its whole body the moment the row is
            // highlighted — a tooltip would be a second copy of what is
            // already on screen, and on a body it paints a banner across the
            // window to say what the reader is looking straight at.
            children: [
              Text(
                widget.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZebuTextStyles.small(
                  context,
                  fontWeight: ZebuFonts.semiBold,
                ).copyWith(fontSize: 13, color: zebuPopoverInk(t)),
              ),
              const SizedBox(height: 1),
              Text(
                widget.item.body.replaceAll(RegExp(r'\s+'), ' ').trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ZebuTextStyles.small(
                  context,
                  color: zebuPopoverInkMuted(t),
                ).copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.item});
  final ZebuPreviewItem? item;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    if (item == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ZebuSpacing.s4,
        ZebuSpacing.s3,
        ZebuSpacing.s4,
        ZebuSpacing.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item!.title,
            style: ZebuTextStyles.body(
              context,
              color: zebuPopoverInk(t),
              fontWeight: ZebuFonts.semiBold,
            ),
          ),
          const SizedBox(height: ZebuSpacing.s2),
          // `SelectableText` so a phrase can be lifted out without inserting
          // the whole reply first.
          SelectableText(
            item!.body,
            style: ZebuTextStyles.small(
              context,
              color: t.textSlate,
            ).copyWith(fontSize: 13, height: 1.55),
          ),
        ],
      ),
    );
  }
}
