import '../models/me.dart';
import '../models/meta.dart';
import 'me_repository.dart';
import 'meta_repository.dart';

/// One assignment's agent pick-list, already narrowed to a department.
class AgentPickList {
  const AgentPickList({
    required this.agents,
    required this.all,
    required this.scoped,
    this.departmentName,
  });

  /// What the picker should show — the department's agents when [scoped].
  final List<MetaItem> agents;

  /// Every active agent, behind the picker's "Show all agents" escape hatch.
  final List<MetaItem> all;

  /// Whether [agents] is actually narrower than [all].
  final bool scoped;

  /// Department the list was narrowed to, for the picker's scope note.
  final String? departmentName;
}

/// Department-scoped agent pick-lists for the assign/reassign flows.
///
/// `GET /meta/agents` returns every active agent and carries no department, but
/// the server only accepts an assignee the ticket's department allows — osTicket
/// re-checks `Dept::canAssign()` in `Ticket::assign()` and answers 422
/// ("Permission denied" / "Agent is unavailable for assignment"). Offering the
/// whole roster therefore means offering picks that cannot succeed.
///
/// With no bulk endpoint for it, the department comes from `GET /agents/{id}`:
/// each agent's profile is fetched once per session (a few lookups in flight at
/// a time) and cached, so only the first assignment of a session pays for it.
///
/// That profile only names an agent's *primary* department, so the match can be
/// narrower than the server's rule (a department set to "all agents", or an
/// agent with extended access, is assignable without being a primary member).
/// The list is therefore a default, never a gate: anything unproven stays in,
/// an empty match falls back to the full roster, and the picker always keeps a
/// "Show all agents" way out.
class AgentDirectory {
  AgentDirectory(this._meta, this._me);

  final MetaRepository _meta;
  final MeRepository _me;

  /// How many `/agents/{id}` lookups are in flight while hydrating.
  static const _lanes = 6;

  /// Session cache of `GET /agents/{id}`. A null value marks a lookup that
  /// failed — that agent's department stays unknown.
  final Map<int, AgentProfile?> _profiles = {};
  Future<void>? _hydration;

  Future<List<MetaItem>> all({bool refresh = false}) =>
      _meta.get(MetaKind.agents, refresh: refresh);

  /// The agents assignable in the given department. Pass whichever the caller
  /// holds — [departmentName] directly, or [departmentId] to resolve the name
  /// from `/meta/departments`. With neither, the full roster comes back
  /// unscoped.
  Future<AgentPickList> assignable({
    String? departmentName,
    int? departmentId,
  }) async {
    final agents = await all();
    final dept = await _departmentName(departmentName, departmentId);
    if (dept == null || agents.isEmpty) {
      return AgentPickList(agents: agents, all: agents, scoped: false);
    }

    await _hydrate(agents);
    final key = dept.toLowerCase();
    final scoped = [
      for (final a in agents)
        if (_belongs(a.id, key)) a,
    ];
    // Nothing matched (or nothing was ruled out) — the filter has told us
    // nothing useful, so don't pretend it did.
    if (scoped.isEmpty || scoped.length == agents.length) {
      return AgentPickList(
        agents: agents,
        all: agents,
        scoped: false,
        departmentName: dept,
      );
    }
    return AgentPickList(
      agents: scoped,
      all: agents,
      scoped: true,
      departmentName: dept,
    );
  }

  /// Whether [agentId] survives the department scope — used to re-check a
  /// choice made before the department changed. True whenever the scope
  /// couldn't be applied, matching [assignable]'s "unproven stays in" rule.
  Future<bool> isAssignable(
    int agentId, {
    String? departmentName,
    int? departmentId,
  }) async {
    final list = await assignable(
      departmentName: departmentName,
      departmentId: departmentId,
    );
    if (!list.scoped) return true;
    return list.agents.any((a) => a.id == agentId);
  }

  void clearCache() => _profiles.clear();

  /// Resolve the department name, falling back to a `/meta/departments` lookup
  /// by id (the ticket list rows and the create form only know one or the
  /// other). Null when neither identifies a department.
  Future<String?> _departmentName(String? name, int? id) async {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    if (id == null || id == 0) return null;
    try {
      final depts = await _meta.departments();
      for (final d in depts) {
        if (d.id == id && d.name.trim().isNotEmpty) return d.name.trim();
      }
    } catch (_) {
      // Offline or forbidden — treat the department as unknown.
    }
    return null;
  }

  /// True unless the agent's profile positively rules them out: only a loaded
  /// profile naming a different department, or an unavailable agent (inactive /
  /// on vacation, which `Dept::canAssign()` rejects too), drops out.
  bool _belongs(int agentId, String deptKey) {
    if (!_profiles.containsKey(agentId)) return true;
    final profile = _profiles[agentId];
    if (profile == null) return true;
    if (!profile.available) return false;
    final dept = profile.department?.trim().toLowerCase() ?? '';
    return dept.isEmpty || dept == deptKey;
  }

  Future<void> _hydrate(List<MetaItem> agents) async {
    // A concurrent picker may already be fetching; let it finish first so its
    // results count towards ours.
    final running = _hydration;
    if (running != null) await running;

    final pending = [
      for (final a in agents)
        if (!_profiles.containsKey(a.id)) a.id,
    ];
    if (pending.isEmpty) return;

    final run = _fetchProfiles(pending);
    _hydration = run;
    try {
      await run;
    } finally {
      if (identical(_hydration, run)) _hydration = null;
    }
  }

  Future<void> _fetchProfiles(List<int> ids) async {
    var next = 0;
    Future<void> lane() async {
      while (next < ids.length) {
        final id = ids[next++];
        try {
          _profiles[id] = await _me.getAgent(id);
        } catch (_) {
          // Remember the failure so one bad id doesn't get retried on every
          // picker open; the agent simply stays unfiltered.
          _profiles[id] = null;
        }
      }
    }

    final lanes = ids.length < _lanes ? ids.length : _lanes;
    await Future.wait([for (var i = 0; i < lanes; i++) lane()]);
  }
}
