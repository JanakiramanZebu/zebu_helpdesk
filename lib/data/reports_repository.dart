import 'dart:typed_data';

import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../models/reports.dart';

/// Reporting (`/reports/*`). All counts are visibility-scoped.
///
/// Two families live here:
///  * `summary` / `volume` — the dashboard's activity cards.
///  * the export surface — the mobile port of `scp/reports.php`'s four record
///    types. Every route in that family requires `reports.export`, accepted as
///    the global permission *or* any department role, which is the same dual
///    check the web page makes.
///
/// Exports are never streamed through this client's JSON path: a `link` call
/// mints a short-lived HMAC-signed URL and [download] fetches the CSV from it.
class ReportsRepository {
  ReportsRepository(this._api);
  final ApiClient _api;

  Future<ReportSummary> summary() async {
    final body = await _api.get('/reports/summary');
    return ReportSummary.fromJson(J.map(J.map(body)['data']));
  }

  /// Daily opened-vs-closed volume over the last [days] (clamped 1..90).
  Future<VolumeReport> volume({int days = 30}) async {
    final body = await _api.get('/reports/volume', query: {'days': days});
    return VolumeReport.fromJson(J.map(J.map(body)['data']));
  }

  // --- Record exports -------------------------------------------------------

  /// The four exportable record types with each one's visible count, in the
  /// fixed order that drives the tab strip.
  Future<List<ReportTypeInfo>> exportTypes() async {
    final body = await _api.get('/reports/exports');
    final data = J.map(J.map(body)['data']);
    return J.mapList(data['types']).map(ReportTypeInfo.fromJson).toList();
  }

  /// One record type's column catalog plus the filters it supports.
  Future<ReportFieldSet> exportFields(String type) async {
    final body = await _api.get('/reports/exports/$type/fields');
    return ReportFieldSet.fromJson(J.map(J.map(body)['data']));
  }

  /// Mint a signed download link for a record export.
  ///
  /// Every argument is optional and omitted when empty. Note that omitting
  /// [columns] exports **all** of the type's columns, not the default subset —
  /// so the caller should always send the picker's selection.
  ///
  /// [status] is the type's own vocabulary: for tickets a mix of numeric
  /// status ids and `state:open` / `state:closed`; for tasks a single
  /// `open` / `closed` / `all`. `users` and `orgs` honour only [start]/[end].
  Future<ReportLink> exportLink(
    String type, {
    List<String>? columns,
    String? start,
    String? end,
    List<String>? status,
    List<int>? deptIds,
    List<int>? topicIds,
    List<int>? staffIds,
  }) async {
    final body = await _api.post(
      '/reports/exports/$type/link',
      body: _compact({
        'columns': columns,
        'start': start,
        'end': end,
        'status': status,
        'dept_id': deptIds,
        'topic_id': topicIds,
        'staff_id': staffIds,
      }),
    );
    return ReportLink.fromJson(J.map(J.map(body)['data']));
  }

  // --- Delivery -------------------------------------------------------------

  /// Fetch the CSV a minted [ReportLink] points at. The link is the credential
  /// and expires 300 seconds after minting, so this runs straight after the
  /// mint rather than being deferred.
  Future<Uint8List> download(ReportLink link) => _api.getSignedBytes(link.url);

  /// Drop nulls and empty collections so the request body carries only the
  /// filters actually in use — the server treats an empty array as "no filter"
  /// anyway, but an absent key says so more plainly in the log.
  Map<String, dynamic> _compact(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    raw.forEach((k, v) {
      if (v == null) return;
      if (v is Iterable && v.isEmpty) return;
      if (v is String && v.isEmpty) return;
      out[k] = v;
    });
    return out;
  }
}
