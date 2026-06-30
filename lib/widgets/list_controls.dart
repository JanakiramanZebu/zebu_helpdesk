import 'package:flutter/material.dart';

/// One selectable filter facet, backed by a `GET /meta/{kind}` list.
class FilterFacet {
  const FilterFacet({
    required this.key,
    required this.label,
    required this.metaKind,
  });

  final String key;
  final String label;
  final String metaKind;
}

/// A facet rendered as a dropdown pill in [ListControlsBar]. `selected` is the
/// string id of the chosen option ('all' = none); [items] always begins with an
/// "All" entry.
typedef FacetControl = ({
  String label,
  List<({String value, String text})> items,
  String selected,
  ValueChanged<String> onSelected,
});

/// A create-date range filter, mirroring the web "Create Date" dropdown.
enum DateRange {
  all('All dates'),
  today('Today'),
  yesterday('Yesterday'),
  last7('Last 7 days'),
  last30('Last 30 days');

  const DateRange(this.label);
  final String label;

  /// Inclusive [from, to] bounds for this range relative to [now], or null for
  /// [DateRange.all].
  (DateTime, DateTime)? bounds(DateTime now) {
    final startToday = DateTime(now.year, now.month, now.day);
    DateTime endOf(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
    return switch (this) {
      DateRange.all => null,
      DateRange.today => (startToday, endOf(startToday)),
      DateRange.yesterday => (
        startToday.subtract(const Duration(days: 1)),
        endOf(startToday.subtract(const Duration(days: 1))),
      ),
      DateRange.last7 => (
        startToday.subtract(const Duration(days: 6)),
        endOf(now),
      ),
      DateRange.last30 => (
        startToday.subtract(const Duration(days: 29)),
        endOf(now),
      ),
    };
  }
}

/// The filter + sort control row shown above a list: a horizontally scrollable
/// strip of Mynt-style pill dropdowns — Create Date, Sort, and one per filter
/// facet. Each opens a popup menu and applies immediately.
class ListControlsBar extends StatelessWidget {
  const ListControlsBar({
    super.key,
    required this.dateRange,
    required this.onDateRange,
    required this.sortItems,
    required this.sortKey,
    required this.onSort,
    this.facets = const [],
  });

  final DateRange dateRange;
  final ValueChanged<DateRange> onDateRange;

  /// (key, label) pairs for the sort menu, in display order.
  final List<({String key, String label})> sortItems;
  final String sortKey;
  final ValueChanged<String> onSort;

  final List<FacetControl> facets;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sortLabel = sortItems
        .firstWhere((s) => s.key == sortKey, orElse: () => sortItems.first)
        .label;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _PillMenu<DateRange>(
              icon: Icons.filter_list,
              label: dateRange == DateRange.all
                  ? 'Create Date'
                  : dateRange.label,
              active: dateRange != DateRange.all,
              selected: dateRange,
              items: [
                for (final r in DateRange.values) (value: r, text: r.label),
              ],
              onSelected: onDateRange,
            ),
            const SizedBox(width: 8),
            _PillMenu<String>(
              icon: Icons.swap_vert,
              label: sortLabel,
              active: true,
              selected: sortKey,
              items: [for (final s in sortItems) (value: s.key, text: s.label)],
              onSelected: onSort,
            ),
            for (final f in facets) ...[
              const SizedBox(width: 8),
              _PillMenu<String>(
                icon: Icons.filter_alt_outlined,
                label: f.selected == 'all'
                    ? f.label
                    : f.items
                          .firstWhere(
                            (i) => i.value == f.selected,
                            orElse: () => (value: 'all', text: f.label),
                          )
                          .text,
                active: f.selected != 'all',
                selected: f.selected,
                items: f.items,
                onSelected: f.onSelected,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PillMenu<T> extends StatelessWidget {
  const _PillMenu({
    required this.icon,
    required this.label,
    required this.active,
    required this.selected,
    required this.items,
    required this.onSelected,
  });

  final IconData icon;
  final String label;
  final bool active;
  final T selected;
  final List<({T value, String text})> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = active ? scheme.primary : scheme.onSurfaceVariant;
    return PopupMenuButton<T>(
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      tooltip: '',
      itemBuilder: (_) => [
        for (final i in items)
          PopupMenuItem<T>(
            value: i.value,
            child: Row(
              children: [
                Icon(
                  i.value == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: i.value == selected
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(i.text),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? scheme.primary.withValues(alpha: 0.06) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? scheme.primary.withValues(alpha: 0.5)
                : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 20, color: fg),
          ],
        ),
      ),
    );
  }
}
