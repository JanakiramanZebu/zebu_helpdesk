import 'json.dart';

/// A page of list results plus the top-level `pagination` metadata that list
/// endpoints return alongside `data`.
class Paginated<T> {
  const Paginated({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    this.unreadCount,
  });

  final List<T> items;
  final int page;
  final int limit;
  final int total;

  /// Only present on `GET /notifications` (top-level `unread_count`).
  final int? unreadCount;

  bool get hasMore => page * limit < total;
  int get pageCount => limit == 0 ? 1 : (total + limit - 1) ~/ limit;

  /// Build from a full envelope: `{ "data": [...], "pagination": {...} }`.
  factory Paginated.fromEnvelope(
    Map<String, dynamic> envelope,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final items = J
        .mapList(envelope['data'])
        .map(fromJson)
        .toList(growable: false);
    final pg = J.map(envelope['pagination']);
    return Paginated<T>(
      items: items,
      page: J.intOr(pg['page'], 1),
      limit: J.intOr(pg['limit'], items.length),
      total: J.intOr(pg['total'], items.length),
      unreadCount: J.intOrNull(envelope['unread_count']),
    );
  }

  Paginated<T> copyWithItems(List<T> items) => Paginated<T>(
    items: items,
    page: page,
    limit: limit,
    total: total,
    unreadCount: unreadCount,
  );
}
