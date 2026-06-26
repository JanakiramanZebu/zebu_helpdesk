import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../models/reports.dart';

/// Reporting (`/reports/*`). All counts are visibility-scoped.
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
}
