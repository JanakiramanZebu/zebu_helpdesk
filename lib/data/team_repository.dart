import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../models/team_member.dart';

/// Team availability (`/agents/team-availability`) — the mobile port of
/// `scp/team-availability.php`.
///
/// A department manager marks which of their employees may receive
/// round-robin auto-assigned tickets (`ost_staff.is_available`). This is a
/// different flag from `POST /me/availability`, which sets the signed-in
/// agent's own **vacation** state.
class TeamRepository {
  TeamRepository(this._api);
  final ApiClient _api;

  /// The agents this agent manages. An agent who manages nobody gets an empty
  /// list — not an error — so the screen renders an empty state.
  Future<List<TeamMember>> list() async {
    final body = await _api.get('/agents/team-availability');
    return J.mapList(J.map(body)['data']).map(TeamMember.fromJson).toList();
  }

  /// Toggle one member's availability.
  ///
  /// A `404` here means "not yours to change" — the API refuses to confirm
  /// that an agent outside the caller's managed departments even exists — so
  /// it must never be read as "this agent was deleted".
  Future<TeamMember> setAvailable(int agentId, bool available) async {
    final body = await _api.post(
      '/agents/$agentId/availability',
      body: {'available': available},
    );
    return TeamMember.fromJson(J.map(J.map(body)['data']));
  }
}
