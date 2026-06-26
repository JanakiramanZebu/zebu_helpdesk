import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/faq.dart';

/// Read-only Knowledgebase (`/faq`).
class FaqRepository {
  FaqRepository(this._api);
  final ApiClient _api;

  Future<Paginated<Faq>> search({String? q, int page = 1, int limit = 25}) async {
    final body = await _api.get('/faq', query: {'q': q, 'page': page, 'limit': limit});
    return Paginated.fromEnvelope(J.map(body), Faq.fromJson);
  }

  Future<Faq> get(int id) async {
    final body = await _api.get('/faq/$id');
    return Faq.fromJson(J.map(J.map(body)['data']));
  }

  Future<List<FaqCategory>> categories() async {
    final body = await _api.get('/faq/categories');
    return J.mapList(J.map(body)['data']).map(FaqCategory.fromJson).toList();
  }

  Future<FaqCategory> category(int id) async {
    final body = await _api.get('/faq/categories/$id');
    return FaqCategory.fromJson(J.map(J.map(body)['data']));
  }
}
