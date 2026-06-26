import '../core/api/json.dart';
import 'common.dart';

/// A requester (end user). Summary rows omit phone/org/custom_fields.
class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.org,
    this.created,
    this.updated,
    this.customFields = const {},
  });

  final int id;
  final String name;
  final String email;
  final String? phone;
  final NamedRef? org;
  final DateTime? created;
  final DateTime? updated;
  final Map<String, String> customFields;

  factory AppUser.fromJson(Map<String, dynamic> j) {
    final cf = <String, String>{};
    if (j['custom_fields'] is Map) {
      J.map(j['custom_fields']).forEach((k, v) => cf[k] = J.strOr(v));
    }
    return AppUser(
      id: J.intOr(j['id']),
      name: J.strOr(j['name']),
      email: J.strOr(j['email']),
      phone: J.str(j['phone']),
      org: NamedRef.maybe(j['org']),
      created: J.dateTime(j['created']),
      updated: J.dateTime(j['updated']),
      customFields: cf,
    );
  }
}
