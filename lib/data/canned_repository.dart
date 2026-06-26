import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/canned.dart';
import '../models/common.dart';

/// All `/canned` endpoints. Note: the body field is `response` on write but
/// serializes back as `body`.
class CannedRepository {
  CannedRepository(this._api);
  final ApiClient _api;

  CannedResponse _canned(dynamic body) =>
      CannedResponse.fromJson(J.map(J.map(body)['data']));

  Future<Paginated<CannedResponse>> list({int page = 1, int limit = 25}) async {
    final body =
        await _api.get('/canned', query: {'page': page, 'limit': limit});
    return Paginated.fromEnvelope(J.map(body), CannedResponse.fromJson);
  }

  Future<CannedResponse> get(int id) async =>
      _canned(await _api.get('/canned/$id'));

  Future<CannedResponse> create({
    required String title,
    required String response,
    int deptId = 0,
    bool isEnabled = true,
    String? notes,
  }) async =>
      _canned(await _api.post('/canned', body: {
        'title': title,
        'response': response,
        'dept_id': deptId,
        'is_enabled': isEnabled,
        if (notes != null) 'notes': notes,
      }));

  Future<CannedResponse> update(int id, Map<String, dynamic> changes) async =>
      _canned(await _api.post('/canned/$id', body: changes));

  Future<void> delete(int id) => _api.delete('/canned/$id');

  /// Expand canned variables for a ticket.
  Future<CannedExpansion> expand(int id, {int ticketId = 0}) async {
    final body =
        await _api.get('/canned/$id/expand', query: {'ticket_id': ticketId});
    return CannedExpansion.fromJson(J.map(J.map(body)['data']));
  }

  Future<List<Attachment>> attachments(int id) async {
    final body = await _api.get('/canned/$id/attachments');
    return J.mapList(J.map(body)['data']).map(Attachment.fromJson).toList();
  }

  Future<Attachment> uploadAttachment(int id, MultipartFile file) async {
    final body = await _api.upload(
      '/canned/$id/attachments',
      fields: {},
      files: {
        'file': [file]
      },
    );
    return Attachment.fromJson(J.map(J.map(body)['data']));
  }

  Future<void> deleteAttachment(int id, int attId) =>
      _api.delete('/canned/$id/attachments/$attId');
}
