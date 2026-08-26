import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/faq.dart';

/// Knowledgebase (`/faq`). Articles are read-only; categories can also be
/// created (the web's Knowledgebase → Categories → "Add New Category").
class FaqRepository {
  FaqRepository(this._api);
  final ApiClient _api;

  Future<Paginated<Faq>> search({
    String? q,
    int page = 1,
    int limit = 25,
  }) async {
    final body = await _api.get(
      '/faq',
      query: {'q': q, 'page': page, 'limit': limit},
    );
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

  /// Create a KB category — the web's Knowledgebase → Categories → "Add New
  /// Category" form (`scp/categories.php`).
  ///
  /// [type] is one of `private` / `public` / `featured`, the three values the
  /// web's Type column reports and the same set `/faq/categories` echoes back
  /// as `type`. Name and description are both required by `Category::update()`;
  /// a duplicate name is rejected server-side.
  ///
  /// [parentId] is the web form's Parent dropdown — `0` for "— Top-Level
  /// Category —". It is always sent, so an install that still hard-codes
  /// `pid = 0` server-side is visible as a wrong parent rather than a silent
  /// difference.
  Future<FaqCategory> createCategory({
    required String name,
    required String type,
    required String description,
    int parentId = 0,
    String? notes,
  }) async {
    final body = await _api.post(
      '/faq/categories',
      body: {
        'name': name,
        'type': type,
        'description': description,
        'pid': parentId,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return FaqCategory.fromJson(J.map(J.map(body)['data']));
  }

  /// Edit a category (`scp/categories.php`'s edit form). **Partial** — send
  /// only what changed; anything omitted is left alone.
  ///
  /// Public/private is the `type` field (`private` / `public` / `featured`);
  /// there is no separate visibility call. `pid` re-parents the category (`0`
  /// = top level). Validation mirrors create: name required and 3+ characters,
  /// no duplicate under the same parent, description required.
  Future<FaqCategory> updateCategory(
    int id,
    Map<String, dynamic> changes,
  ) async {
    final body = await _api.post('/faq/categories/$id', body: changes);
    return FaqCategory.fromJson(J.map(J.map(body)['data']));
  }

  /// Delete a category **and every article in it**, the way the web's mass
  /// action does. Not reversible: the caller must state the article count
  /// before calling. Returns how many articles went with it.
  ///
  /// If an article fails to delete the server leaves the category intact and
  /// answers 500 rather than orphaning anything — so a failure here means
  /// nothing was destroyed.
  Future<int> deleteCategory(int id) async {
    final body = await _api.delete('/faq/categories/$id');
    return J.intOr(J.map(J.map(body)['data'])['faqs_deleted']);
  }
}
