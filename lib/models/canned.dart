import '../core/api/json.dart';
import 'common.dart';

/// A canned response. Note: the write field is `response` but it serializes
/// back as `body`.
class CannedResponse {
  const CannedResponse({
    required this.id,
    required this.title,
    required this.body,
    this.deptId = 0,
    this.isEnabled = true,
    this.notes,
    this.attachments = const [],
  });

  final int id;
  final String title;
  final String body;
  final int deptId; // 0 = global
  final bool isEnabled;
  final String? notes;
  final List<Attachment> attachments;

  bool get isGlobal => deptId == 0;

  factory CannedResponse.fromJson(Map<String, dynamic> j) => CannedResponse(
    id: J.intOr(j['id']),
    title: J.strOr(j['title']),
    body: J.strOr(j['body']),
    deptId: J.intOr(j['dept_id']),
    isEnabled: J.boolOr(j['is_enabled'], true),
    notes: J.str(j['notes']),
    attachments: J.mapList(j['attachments']).map(Attachment.fromJson).toList(),
  );
}

/// The `?ticket_id=` expand payload / `GET /canned/{id}/expand`.
class CannedExpansion {
  const CannedExpansion({
    required this.title,
    required this.raw,
    required this.expanded,
  });
  final String title;
  final String raw;
  final String expanded;

  factory CannedExpansion.fromJson(Map<String, dynamic> j) => CannedExpansion(
    title: J.strOr(j['title']),
    raw: J.strOr(j['response_raw']),
    expanded: J.strOr(j['response_expanded']),
  );
}
