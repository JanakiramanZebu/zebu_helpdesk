import 'package:flutter/material.dart';

import '../core/theme/app_text.dart';
import '../models/meta.dart';
import 'app_sheet.dart';
import 'list_controls.dart';

/// The filter selection returned by [showFilterSheet] when the user taps Apply.
/// Carries the chosen create-date window, sort key and the per-facet selections
/// (only facets with a concrete choice are present; "All" is omitted).
class FilterSheetResult {
  const FilterSheetResult({
    required this.dateRange,
    required this.sort,
    required this.filters,
  });

  final DateRange dateRange;
  final String sort;
  final Map<String, MetaItem> filters;
}

/// Opens the list filter/sort bottom sheet and resolves to the applied
/// selection, or `null` if the user dismissed it without applying.
///
/// The sheet edits a *draft* copy of the current selection, so nothing changes
/// on the list until Apply is pressed. Reset clears the draft back to defaults
/// (all dates, [defaultSort], no facets) without closing the sheet.
Future<FilterSheetResult?> showFilterSheet({
  required BuildContext context,
  required DateRange dateRange,
  required String sort,
  required String defaultSort,
  required List<({String key, String label})> sortItems,
  required List<FilterFacet> facets,
  required Map<String, List<MetaItem>> facetOptions,
  required Map<String, MetaItem?> selected,
}) {
  return showAppSheet<FilterSheetResult>(
    context: context,
    builder: (_) => _FilterSheet(
      dateRange: dateRange,
      sort: sort,
      defaultSort: defaultSort,
      sortItems: sortItems,
      facets: facets,
      facetOptions: facetOptions,
      selected: selected,
    ),
  );
}

/// The filter trigger shown in a list search bar's trailing slot: a tune glyph
/// that opens the filter sheet, with a small dot when any filter is active.
class FilterButton extends StatelessWidget {
  const FilterButton({super.key, required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkResponse(
      radius: 22,
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 30,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            Icon(
              Icons.tune,
              size: 20,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
            if (active)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.dateRange,
    required this.sort,
    required this.defaultSort,
    required this.sortItems,
    required this.facets,
    required this.facetOptions,
    required this.selected,
  });

  final DateRange dateRange;
  final String sort;
  final String defaultSort;
  final List<({String key, String label})> sortItems;
  final List<FilterFacet> facets;
  final Map<String, List<MetaItem>> facetOptions;
  final Map<String, MetaItem?> selected;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late DateRange _date = widget.dateRange;
  late String _sort = widget.sort;
  // Draft facet selection by facet key → chosen option id (absent = "All").
  late final Map<String, int> _sel = {
    for (final e in widget.selected.entries)
      if (e.value != null) e.key: e.value!.id,
  };

  /// Facets that actually have options loaded — the only ones worth showing.
  List<FilterFacet> get _visibleFacets => [
    for (final f in widget.facets)
      if ((widget.facetOptions[f.key] ?? const []).isNotEmpty) f,
  ];

  void _reset() => setState(() {
    _date = DateRange.all;
    _sort = widget.defaultSort;
    _sel.clear();
  });

  void _apply() {
    final filters = <String, MetaItem>{};
    for (final entry in _sel.entries) {
      final opts = widget.facetOptions[entry.key] ?? const [];
      final match = opts.where((m) => m.id == entry.value);
      if (match.isNotEmpty) filters[entry.key] = match.first;
    }
    Navigator.of(context).pop(
      FilterSheetResult(dateRange: _date, sort: _sort, filters: filters),
    );
  }

  bool get _dirty =>
      _date != DateRange.all || _sort != widget.defaultSort || _sel.isNotEmpty;

  /// At or below this many options a facet renders as inline chips; above it,
  /// an expandable searchable dropdown is used instead so long lists
  /// (departments, agents) stay tidy.
  static const _chipThreshold = 6;

  /// Key of the facet whose inline dropdown is currently expanded (only one is
  /// open at a time), or null when all are collapsed.
  String? _openFacet;

  /// The current display label for facet [f] — the chosen option's name, or an
  /// "All …" placeholder when nothing is selected.
  String _facetLabel(FilterFacet f) {
    final id = _sel[f.key];
    if (id == null) return 'All ${f.label.toLowerCase()}';
    final match = (widget.facetOptions[f.key] ?? const []).where(
      (m) => m.id == id,
    );
    return match.isEmpty ? 'All ${f.label.toLowerCase()}' : match.first.name;
  }

  /// One facet block: inline chips for short lists, otherwise a tappable row
  /// that expands an inline searchable dropdown.
  Widget _facetGroup(FilterFacet f) {
    final options = widget.facetOptions[f.key]!;
    if (options.length <= _chipThreshold) {
      return _Group(
        title: f.label,
        child: _ChipRow<int?>(
          options: [
            (value: null, label: 'All'),
            for (final m in options) (value: m.id, label: m.name),
          ],
          selected: _sel[f.key],
          onSelect: (v) => setState(() {
            if (v == null) {
              _sel.remove(f.key);
            } else {
              _sel[f.key] = v;
            }
          }),
        ),
      );
    }

    final expanded = _openFacet == f.key;
    return _Group(
      title: f.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FacetSelector(
            label: _facetLabel(f),
            active: _sel.containsKey(f.key),
            expanded: expanded,
            onTap: () => setState(
              () => _openFacet = expanded ? null : f.key,
            ),
          ),
          if (expanded)
            _FacetDropdown(
              title: f.label,
              options: options,
              selectedId: _sel[f.key],
              onSelected: (id) => setState(() {
                if (id == null) {
                  _sel.remove(f.key);
                } else {
                  _sel[f.key] = id;
                }
                _openFacet = null;
              }),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppSheet(
      title: 'Filters',
      actions: [
        if (_dirty)
          TextButton(
            onPressed: _reset,
            child: const Text('Reset'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Group(
            title: 'Create date',
            child: _ChipRow<DateRange>(
              options: [
                for (final r in DateRange.values) (value: r, label: r.label),
              ],
              selected: _date,
              onSelect: (r) => setState(() => _date = r),
            ),
          ),
          _Group(
            title: 'Sort by',
            child: _ChipRow<String>(
              options: [
                for (final s in widget.sortItems) (value: s.key, label: s.label),
              ],
              selected: _sort,
              onSelect: (s) => setState(() => _sort = s),
            ),
          ),
          for (final f in _visibleFacets) _facetGroup(f),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _apply,
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled block within the filter sheet.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText.paraText(
            context,
            title.toUpperCase(),
            fw: 2,
            letterSpacing: 0.4,
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// A wrapping row of single-select choice chips.
class _ChipRow<T> extends StatelessWidget {
  const _ChipRow({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(o.label),
            selected: o.value == selected,
            showCheckmark: false,
            labelStyle: AppText.style(
              context,
              fontSize: 13,
              fw: o.value == selected ? 1 : 0,
              color: o.value == selected
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            ),
            selectedColor: scheme.primary.withValues(alpha: 0.12),
            backgroundColor: scheme.surface,
            side: BorderSide(
              color: o.value == selected
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.outlineVariant,
            ),
            onSelected: (_) => onSelect(o.value),
          ),
      ],
    );
  }
}

/// A tappable field that shows a facet's current selection and expands the
/// inline searchable dropdown — used instead of chips when the option list is
/// long. The chevron rotates to point up while [expanded].
class _FacetSelector extends StatelessWidget {
  const _FacetSelector({
    required this.label,
    required this.active,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlight = active || expanded;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: highlight
                ? scheme.primary.withValues(alpha: 0.5)
                : scheme.outlineVariant,
          ),
          color: active ? scheme.primary.withValues(alpha: 0.06) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: AppText.subText(
                context,
                label,
                fw: active ? 1 : 0,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                color: active ? scheme.primary : scheme.onSurface,
              ),
            ),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.expand_more,
                size: 20,
                color: highlight ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The inline, searchable single-select dropdown for one facet, revealed under
/// its [_FacetSelector]. Manages its own search query; calls [onSelected] with
/// the chosen option id (or null for "All"). No nested bottom sheet.
class _FacetDropdown extends StatefulWidget {
  const _FacetDropdown({
    required this.title,
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final String title;
  final List<MetaItem> options;
  final int? selectedId;
  final ValueChanged<int?> onSelected;

  @override
  State<_FacetDropdown> createState() => _FacetDropdownState();
}

class _FacetDropdownState extends State<_FacetDropdown> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty
        ? widget.options
        : widget.options
              .where((m) => m.name.toLowerCase().contains(q))
              .toList(growable: false);

    Widget option({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) => ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: AppText.subText(
        context,
        label,
        fw: selected ? 1 : 0,
        color: selected ? scheme.primary : scheme.onSurface,
      ),
      trailing: selected
          ? Icon(Icons.check, size: 20, color: scheme.primary)
          : null,
      onTap: onTap,
    );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: SheetSearchField(
              controller: _ctrl,
              autofocus: true,
              hintText: 'Search ${widget.title.toLowerCase()}',
              onChanged: (v) => setState(() => _query = v),
              onClear: () => setState(() => _query = ''),
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                if (q.isEmpty)
                  option(
                    label: 'All ${widget.title.toLowerCase()}',
                    selected: widget.selectedId == null,
                    onTap: () => widget.onSelected(null),
                  ),
                for (final m in matches)
                  option(
                    label: m.name,
                    selected: m.id == widget.selectedId,
                    onTap: () => widget.onSelected(m.id),
                  ),
                if (matches.isEmpty && q.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: AppText.paraText(
                      context,
                      'No matches',
                      align: TextAlign.center,
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
