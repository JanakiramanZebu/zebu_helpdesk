import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/common.dart';
import '../models/faq.dart';

/// Knowledgebase (`/faq`) — browse and search articles, manage categories,
/// and author new articles (the web's "Add New FAQ" and "Add New Category").
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

  /// Create a knowledgebase article — the web's "Add New FAQ" form
  /// (`scp/faq.php?a=add`).
  ///
  /// `category_id`, `question` and `answer` are required, and the **question
  /// must be unique across the whole knowledgebase**, not just its category —
  /// only the server can check that. [answer] and [notes] are HTML and are
  /// sanitised server-side. [published] omitted means unpublished, which comes
  /// back as `type: "Internal"`.
  ///
  /// [topicIds] are the help topics the article answers. An unknown id is a
  /// 422 naming it, not a silent drop.
  Future<Faq> createArticle({
    required int categoryId,
    required String question,
    required String answer,
    bool published = false,
    List<int> topicIds = const [],
    String? notes,
  }) async {
    final body = await _api.post(
      '/faq',
      body: {
        'category_id': categoryId,
        'question': question,
        'answer': answer,
        'published': published,
        'topic_ids': topicIds,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      },
    );
    return Faq.fromJson(J.map(J.map(body)['data']));
  }

  /// Edit an article (`scp/faq.php?id=N`), and publish / unpublish it — there
  /// is no separate publish endpoint, publishing is `{'published': true}`.
  ///
  /// **Partial**: send only what changed. Anything omitted keeps its value,
  /// **including attachments and help topics** — the server never passes its
  /// "keep only these files" list unless asked, so a publish toggle cannot
  /// wipe an article's attachments.
  ///
  /// `topic_ids` is the one key where absent and empty differ: omitted leaves
  /// the links alone, `[]` clears them all, a list replaces them wholesale.
  Future<Faq> updateArticle(int id, Map<String, dynamic> changes) async {
    final body = await _api.post('/faq/$id', body: changes);
    return Faq.fromJson(J.map(J.map(body)['data']));
  }

  /// Delete an article, its help-topic links and its attachments.
  Future<void> deleteArticle(int id) => _api.delete('/faq/$id');

  /// An article's attachments. Deliberately separate from the edit call, so a
  /// partial edit can never disturb them.
  Future<List<Attachment>> attachments(int id) async {
    final body = await _api.get('/faq/$id/attachments');
    return J.mapList(J.map(body)['data']).map(Attachment.fromJson).toList();
  }

  Future<Attachment> uploadAttachment(int id, MultipartFile file) async {
    final body = await _api.upload(
      '/faq/$id/attachments',
      fields: {},
      files: {
        'file': [file],
      },
    );
    return Attachment.fromJson(J.map(J.map(body)['data']));
  }

  Future<void> deleteAttachment(int id, int attId) =>
      _api.delete('/faq/$id/attachments/$attId');

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
