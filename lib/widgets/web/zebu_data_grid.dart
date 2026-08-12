import 'package:flutter/material.dart';

import '../../res/zebu_spacing.dart';
import '../../res/zebu_text_styles.dart';
import '../../res/zebu_theme.dart';
import 'select_checkbox.dart';

/// One column of a [ZebuDataGrid].
///
/// The point of this class is that **the header and the body are rendered
/// from the same list**. Every web list screen used to hand-write the column
/// widths twice — once in a `_TableHeader` widget and again, hundreds of
/// lines away, in a `_Row` widget — and nothing but care kept the two in
/// step. The old code carries comments documenting bugs where they drifted a
/// few pixels apart and every column shifted against its label.
///
/// Give a column either a fixed [width] or a [flex] weight, never both.
class ZebuGridColumn<T> {
  const ZebuGridColumn({
    required this.label,
    required this.cell,
    this.width,
    this.flex,
    this.alignRight = false,
  }) : assert(
         (width == null) != (flex == null),
         'Supply exactly one of width / flex',
       );

  /// Column header text.
  final String label;

  /// Builds this column's cell for one row.
  final Widget Function(T item) cell;

  /// Fixed column width in logical pixels.
  final double? width;

  /// Share of the leftover width, relative to the other flex columns.
  final int? flex;

  /// Right-aligns the header label and the cell — for dates and numerics.
  final bool alignRight;
}

/// Body-cell geometry — the padding and alignment every grid cell uses.
///
/// Exported because skeleton loaders have to mirror the real row exactly, and
/// the alternative is each screen re-deriving the same numbers and drifting.
/// Give it either a fixed [width] or a [flex], matching its column.
class ZebuGridCell extends StatelessWidget {
  const ZebuGridCell({
    super.key,
    required this.child,
    this.width,
    this.flex,
    this.alignRight = false,
  });

  final Widget child;
  final double? width;
  final int? flex;
  final bool alignRight;

  /// Leading select-checkbox column width, shared by header, rows, and
  /// skeletons.
  static const double selectWidth = _kSelectWidth;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: 8,
      ),
      child: Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: child,
      ),
    );
    return flex != null
        ? Expanded(flex: flex!, child: content)
        : SizedBox(width: width, child: content);
  }
}

/// Header select-all state for grids with a checkbox column. Pass null to
/// [ZebuDataGrid.selection] to omit the column entirely.
class ZebuGridSelection {
  const ZebuGridSelection({
    required this.allChecked,
    required this.someChecked,
    required this.onToggleAll,
  });

  final bool allChecked;
  final bool someChecked;
  final VoidCallback onToggleAll;
}

/// Builds one row. Handed to [ZebuDataGrid.body] so the caller can drive it
/// from whatever list widget it already uses — normally `PagedListView`,
/// which owns fetching, filtering, and sorting.
typedef ZebuGridRowBuilder<T> =
    Widget Function(
      T item, {
      bool selected,
      bool checked,
      VoidCallback? onTap,
      VoidCallback? onToggleChecked,
    });

/// Shared table shell for the web list screens.
///
/// Owns the parts every one of them repeated: the horizontal-scroll fallback
/// below [minWidth], the header strip, the leading checkbox column, uniform
/// row height, and hover / selected row states. The caller supplies the
/// column spec and the body — usually a `PagedListView` — and nothing else.
class ZebuDataGrid<T> extends StatefulWidget {
  const ZebuDataGrid({
    super.key,
    required this.columns,
    required this.body,
    required this.minWidth,
    this.rowHeight = 44,
    this.selection,
  });

  final List<ZebuGridColumn<T>> columns;

  /// Renders the scrolling body. Call the supplied builder for each item to
  /// get a row laid out against [columns].
  final Widget Function(BuildContext context, ZebuGridRowBuilder<T> row) body;

  /// Below this width the grid scrolls horizontally instead of squeezing
  /// columns past legibility. Header and body share one controller so they
  /// scroll together.
  final double minWidth;

  final double rowHeight;

  /// Non-null adds a leading checkbox column with a tri-state select-all.
  final ZebuGridSelection? selection;

  @override
  State<ZebuDataGrid<T>> createState() => _ZebuDataGridState<T>();
}

/// Leading select-checkbox column, shared by the header and every row.
const double _kSelectWidth = 44;

class _ZebuDataGridState<T> extends State<ZebuDataGrid<T>> {
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scrolls = constraints.maxWidth <= widget.minWidth;
        final tableWidth = scrolls ? widget.minWidth : constraints.maxWidth;
        return Scrollbar(
          controller: _hScroll,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GridHeader<T>(
                    columns: widget.columns,
                    selection: widget.selection,
                    // Reserve room for the horizontal scrollbar so the last
                    // column's label stays aligned with its cells; without a
                    // scrollbar the gutter would be a dead strip.
                    scrollGutter: scrolls,
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: t.bgElevated,
                      child: widget.body(context, _buildRow),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(
    T item, {
    bool selected = false,
    bool checked = false,
    VoidCallback? onTap,
    VoidCallback? onToggleChecked,
  }) {
    return _GridRow<T>(
      item: item,
      columns: widget.columns,
      height: widget.rowHeight,
      selectable: widget.selection != null,
      selected: selected,
      checked: checked,
      onTap: onTap,
      onToggleChecked: onToggleChecked,
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _GridHeader<T> extends StatelessWidget {
  const _GridHeader({
    required this.columns,
    required this.selection,
    required this.scrollGutter,
  });

  final List<ZebuGridColumn<T>> columns;
  final ZebuGridSelection? selection;
  final bool scrollGutter;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
    final sel = selection;
    // Grey strip rather than white: the page, the card, and the rows are all
    // white, so a white header had nothing but hairlines holding it apart and
    // the labels read as floating above the list. A filled strip defines the
    // grid's top edge without adding borders.
    return Container(
      decoration: BoxDecoration(
        color: t.bgTertiary,
        border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
      ),
      child: Row(
        children: [
          if (sel != null)
            SizedBox(
              width: _kSelectWidth,
              child: Center(
                child: SelectCheckbox(
                  value: sel.allChecked
                      ? true
                      : (sel.someChecked ? null : false),
                  onChanged: (_) => sel.onToggleAll(),
                  tooltip: sel.allChecked ? 'Deselect all' : 'Select all',
                ),
              ),
            ),
          for (final c in columns) _headerCell(context, c),
          if (scrollGutter) const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _headerCell(BuildContext context, ZebuGridColumn<T> c) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ZebuSpacing.s3,
        vertical: ZebuSpacing.s3,
      ),
      child: Align(
        alignment: c.alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          c.label,
          maxLines: 1,
          // Labels must stay on one line — "Department" used to wrap to
          // "Depart / ment" when its column narrowed, stretching the header
          // taller than the body rows.
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textAlign: c.alignRight ? TextAlign.right : TextAlign.left,
          style: ZebuTextStyles.tableHeader(context),
        ),
      ),
    );
    return c.flex != null
        ? Expanded(flex: c.flex!, child: content)
        : SizedBox(width: c.width, child: content);
  }
}

// ---------------------------------------------------------------------------
// Row
// ---------------------------------------------------------------------------

class _GridRow<T> extends StatefulWidget {
  const _GridRow({
    required this.item,
    required this.columns,
    required this.height,
    required this.selectable,
    required this.selected,
    required this.checked,
    required this.onTap,
    required this.onToggleChecked,
  });

  final T item;
  final List<ZebuGridColumn<T>> columns;
  final double height;
  final bool selectable;
  final bool selected;
  final bool checked;
  final VoidCallback? onTap;
  final VoidCallback? onToggleChecked;

  @override
  State<_GridRow<T>> createState() => _GridRowState<T>();
}

class _GridRowState<T> extends State<_GridRow<T>> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = ZebuTheme.of(context);
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
                // A 10 % accent wash rather than the solid `accentMuted`
                // (`#E8F4FD`), which read as too heavy. It has to stay
                // clearly bluer than the header strip (`#F1F3F8`) though —
                // at 6 % the two were indistinguishable.
                ? t.accent.withValues(alpha: 0.10)
                // Idle is the hover tone at zero alpha, not
                // `Colors.transparent` — that is transparent *black*, and
                // lerping from it washes the row through grey on the way in.
                : (_hover ? t.bgHover : t.bgHover.withValues(alpha: 0)),
            border: Border(bottom: BorderSide(color: t.borderSubtle, width: 1)),
          ),
          child: SizedBox(
            height: widget.height,
            child: Row(
              children: [
                if (widget.selectable)
                  SizedBox(
                    width: _kSelectWidth,
                    child: Center(
                      child: GestureDetector(
                        // Ticking a row must not also open it.
                        onTap: widget.onToggleChecked,
                        child: SelectCheckbox(
                          value: widget.checked,
                          onChanged: (_) => widget.onToggleChecked?.call(),
                        ),
                      ),
                    ),
                  ),
                for (final c in widget.columns) _bodyCell(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bodyCell(ZebuGridColumn<T> c) => ZebuGridCell(
    width: c.width,
    flex: c.flex,
    alignRight: c.alignRight,
    child: c.cell(widget.item),
  );
}

/// Plain text in a grid cell, with a lighter placeholder when empty.
///
/// Shared so the two list screens can't disagree about cell type size — they
/// already had: tickets rendered `tableCell` (14, medium) while tasks used
/// `small` (12, w500), so the same column read two sizes on two screens.
class ZebuGridTextCell extends StatelessWidget {
  const ZebuGridTextCell({super.key, required this.text, this.emptyLabel});

  final String text;

  /// Shown when [text] is blank — "Unassigned" reads better than an em-dash
  /// where the absence itself is meaningful. Defaults to an em-dash.
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    final empty = text.trim().isEmpty;
    return Text(
      empty ? (emptyLabel ?? '\u2014') : text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // Placeholders read lighter than real values.
      style: empty
          ? ZebuTextStyles.small(context)
          : ZebuTextStyles.tableCell(context),
    );
  }
}
