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
    this.deptName,
    this.isEnabled = true,
    this.updatedLabel,
    this.fileCount = 0,
    this.notes,
    this.attachments = const [],
    this.filters = const [],
  });

  final int id;
  final String title;
  final String body;
  final int deptId; // 0 = global
  /// Department name on a list row; null for the global (All Departments) pool.
  final String? deptName;
  final bool isEnabled;

  /// "Last Updated" exactly as the list serializes it (`Format::datetime`,
  /// i.e. the install's own display format — not a parseable timestamp).
  final String? updatedLabel;

  /// Non-inline attachments on the response, as counted by the list row.
  final int fileCount;

  final String? notes;
  final List<Attachment> attachments;

  /// Email filters using this response (`Canned::getFilters()`), served on
  /// retrieve. `Canned::delete()` refuses while this is non-empty, so the edit
  /// sheet can warn before the delete rather than only after the 409.
  final List<String> filters;

  bool get isGlobal => deptId == 0;

  /// What the scope tag should read: the department's name when the payload
  /// carries it, else Global / Department.
  String get scopeLabel =>
      isGlobal ? 'Global' : (deptName?.trim().isNotEmpty == true
          ? deptName!.trim()
          : 'Department');

  factory CannedResponse.fromJson(Map<String, dynamic> j) => CannedResponse(
    id: J.intOr(j['id']),
    title: J.strOr(j['title']),
    body: J.strOr(j['body']),
    deptId: J.intOr(j['dept_id']),
    deptName: J.strNonBlank(j['dept_name']),
    isEnabled: J.boolOr(j['is_enabled'], true),
    updatedLabel: J.strNonBlank(j['updated']),
    fileCount: J.intOr(j['files']),
    notes: J.str(j['notes']),
    attachments: J.mapList(j['attachments']).map(Attachment.fromJson).toList(),
    filters: J.list(j['filters']).map((e) => J.strOr(e)).toList(),
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
