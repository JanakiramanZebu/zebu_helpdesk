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
