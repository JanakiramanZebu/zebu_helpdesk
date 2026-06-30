import '../core/api/json.dart';

/// An organization. List rows are lightweight (`user_count`); the full object
/// adds domain/manager/sharing/collab flags/custom_fields.
class Organization {
  const Organization({
    required this.id,
    required this.name,
    this.domain,
    this.manager,
    this.sharing,
    this.collabAll = false,
    this.collabPrimary = false,
    this.autoAssign = false,
    this.userCount = 0,
    this.created,
    this.updated,
    this.customFields = const {},
  });

  final int id;
  final String name;
  final String? domain;
  final OrgManager? manager;
  final String? sharing; // none | primary | everybody
  final bool collabAll;
  final bool collabPrimary;
  final bool autoAssign;
  final int userCount;
  final DateTime? created;
  final DateTime? updated;
  final Map<String, String> customFields;

  factory Organization.fromJson(Map<String, dynamic> j) {
    final cf = <String, String>{};
    if (j['custom_fields'] is Map) {
      J.map(j['custom_fields']).forEach((k, v) => cf[k] = J.strOr(v));
    }
    return Organization(
      id: J.intOr(j['id']),
      name: J.strOr(j['name']),
      domain: J.str(j['domain']),
      manager: j['manager'] is Map
          ? OrgManager.fromJson(J.map(j['manager']))
          : null,
      sharing: J.str(j['sharing']),
      collabAll: J.boolOr(j['collab_all']),
      collabPrimary: J.boolOr(j['collab_primary']),
      autoAssign: J.boolOr(j['auto_assign']),
      userCount: J.intOr(j['user_count']),
      created: J.dateTime(j['created']),
      updated: J.dateTime(j['updated']),
      customFields: cf,
    );
  }
}

class OrgManager {
  const OrgManager({required this.type, required this.id, required this.name});
  final String type; // agent | team
  final int id;
  final String name;

  factory OrgManager.fromJson(Map<String, dynamic> j) => OrgManager(
    type: J.strOr(j['type']),
    id: J.intOr(j['id']),
    name: J.strOr(j['name']),
  );
}
