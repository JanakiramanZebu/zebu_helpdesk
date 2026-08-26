import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/common.dart';

/// The tag catalogue (`/tags`) — the mobile port of `scp/managetags.php`.
///
/// Applying a tag to a ticket or task is a different surface entirely
/// (`/tickets/{id}/tags`, `/tasks/{id}/tags`); this manages the shared
/// vocabulary itself: create, rename, recolor, enable/disable, merge, delete.
///
/// Gated server-side on `Tag::canManage()` — an admin, or the manager of any
/// department. Creating is a separate permission from managing, so the two are
/// gated independently on the client too (see `Me.canCreateTags` /
/// `Me.canManageTags`).
class TagsRepository {
  TagsRepository(this._api);
  final ApiClient _api;

  Tag _tag(dynamic body) => Tag.fromJson(J.map(J.map(body)['data']));

  Future<Paginated<Tag>> list({int page = 1, int limit = 25}) async {
    final body = await _api.get('/tags', query: {'page': page, 'limit': limit});
    return Paginated.fromEnvelope(J.map(body), Tag.fromJson);
  }

  Future<Tag> get(int id) async => _tag(await _api.get('/tags/$id'));

  Future<Tag> create({required String name, String? color}) async => _tag(
    await _api.post(
      '/tags',
      body: {'name': name, if (color != null) 'color': color},
    ),
  );

  /// Partial update: rename, recolor and enable/disable are all this one call,
  /// and anything omitted is left alone.
  Future<Tag> update(int id, Map<String, dynamic> changes) async =>
      _tag(await _api.post('/tags/$id', body: changes));

  /// Refused (not silently detached) while the tag is still applied to
  /// something; the result echoes what it was applied to.
  Future<TagDeleteResult> delete(int id) async => TagDeleteResult.fromJson(
    J.map(J.map(await _api.delete('/tags/$id'))['data']),
  );

  /// Merge [sourceIds] **into** [intoId]. The survivor is [intoId]; every
  /// source is consumed and deleted, and that is not reversible — the caller
  /// must confirm the direction first.
  ///
  /// Every id is resolved before anything mutates, so one unknown id aborts
  /// the whole request with nothing changed: there are no partial merges.
  Future<TagMergeResult> merge({
    required int intoId,
    required List<int> sourceIds,
  }) async {
    final body = await _api.post(
      '/tags/merge',
      body: {'into_id': intoId, 'source_ids': sourceIds},
    );
    return TagMergeResult.fromJson(J.map(J.map(body)['data']));
  }
}
