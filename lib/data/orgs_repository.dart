import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';

/// One row of `GET /organizations` — everything that list serializer returns.
///
/// Account Manager, domain, sharing flags and custom fields live only on the
/// `GET /organizations/{id}` payload, so a report built from the list cannot
/// carry them.
class OrgSummary {
  const OrgSummary({
    required this.id,
    required this.name,
    required this.userCount,
    this.created,
  });

  final int id;
  final String name;
  final int userCount;
  final DateTime? created;

  factory OrgSummary.fromJson(Map<String, dynamic> j) => OrgSummary(
    id: J.intOr(j['id']),
    name: J.strOr(j['name']),
    userCount: J.intOr(j['user_count']),
    created: J.dateTime(j['created']),
  );
}

/// Read-only `/organizations` access.
///
/// The Organizations *browse* screens were removed with the web's hidden Users
/// tab, but the web's Reports & Exports page still offers an Organizations
/// report — so the list endpoint is still needed to build one.
class OrgsRepository {
  OrgsRepository(this._api);
  final ApiClient _api;

  Future<Paginated<OrgSummary>> list({
    String? q,
    int page = 1,
    int limit = 25,
  }) async {
    final body = await _api.get(
      '/organizations',
      query: {'q': q, 'page': page, 'limit': limit},
    );
    return Paginated.fromEnvelope(J.map(body), OrgSummary.fromJson);
  }
}
