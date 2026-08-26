import '../models/me.dart';
import '../models/meta.dart';
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
/// `GET /meta/agents?dept_id=` runs the server's own `Dept::getAssignees()`
/// rule — the same one `Ticket::assign()` re-checks before answering 422
/// ("Permission denied" / "Agent is unavailable for assignment") — so every
/// agent it returns can genuinely take the assignment, extended `dept_access`
/// included. The list is exact, not a guess.
///
/// The department is whatever the caller holds: an id goes straight to the
/// server, a bare name is resolved through `/meta/departments` first. With
/// neither, or when the scoped call fails, the full roster comes back unscoped
/// rather than a list we can't vouch for.
class AgentDirectory {
  AgentDirectory(this._meta);

  final MetaRepository _meta;

  Future<List<MetaItem>> all({bool refresh = false}) =>
      _meta.get(MetaKind.agents, refresh: refresh);

  /// The agents assignable in the given department. Pass whichever the caller
  /// holds — [departmentId] directly, or [departmentName] to resolve the id
  /// from `/meta/departments`. With neither, the full roster comes back
  /// unscoped.
  Future<AgentPickList> assignable({
    String? departmentName,
    int? departmentId,
  }) async {
    final agents = await all();
    final dept = await _department(departmentName, departmentId);
    if (dept == null || agents.isEmpty) {
      return AgentPickList(agents: agents, all: agents, scoped: false);
    }

    final List<MetaItem> scoped;
    try {
      scoped = await _meta.agentsInDepartment(dept.id);
    } catch (_) {
      // Offline or forbidden — offer the whole roster rather than a list we
      // can't vouch for, and say it isn't scoped.
      return AgentPickList(
        agents: agents,
        all: agents,
        scoped: false,
        departmentName: dept.name,
      );
    }

    return AgentPickList(
      agents: scoped,
      all: agents,
      // An install that ignores the filter hands back the whole roster; saying
      // "scoped" then would put a department note on an unnarrowed list.
      scoped: scoped.length != agents.length,
      departmentName: dept.name,
    );
  }

  /// Whether [agentId] survives the department scope — used to re-check a
  /// choice made before the department changed. True whenever the scope
  /// couldn't be applied.
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

  /// The agents [me] may see in the **directory**, porting osTicket's
  /// `Staff::applyDeptVisibility()` (`include/class.staff.php`) — the filter
  /// behind the web's Agent Directory (`scp/directory.php` ->
  /// `Staff::getDeptAgents()`). An agent holding `visibility.agents` sees the
  /// whole roster; everyone else sees only agents belonging to a department
  /// they themselves can access.
  ///
  /// Each `/meta/agents` row now names the agent's **home** department, so the
  /// match no longer costs a lookup per agent. It is still narrower than the
  /// web's, which also matches on `dept_access` — published by no endpoint —
  /// so a colleague with extended access to one of my departments but a
  /// different home one is not recognized. The rule therefore stays permissive:
  /// an agent whose department the payload doesn't state stays in, and a filter
  /// that rules nothing (or everything) out is reported as unscoped rather
  /// than applied.
  Future<AgentPickList> visible(Me me) async {
    final agents = await all();
    // `applyDeptVisibility` reads the agent's OWN permission set here (osTicket
    // calls hasPerm() with its default $global=true), not their roles.
    if (agents.isEmpty || me.can(Me.permViewAgents)) {
      return AgentPickList(agents: agents, all: agents, scoped: false);
    }

    final mine = <int>{
      ...me.permissionsByDepartment.keys,
      ...me.managedDepartments,
    };
    if (mine.isEmpty) {
      return AgentPickList(agents: agents, all: agents, scoped: false);
    }

    final scoped = [
      for (final a in agents)
        if (a.deptId == null || mine.contains(a.deptId)) a,
    ];
    if (scoped.isEmpty || scoped.length == agents.length) {
      return AgentPickList(agents: agents, all: agents, scoped: false);
    }
    return AgentPickList(agents: scoped, all: agents, scoped: true);
  }

  /// Resolve the department the caller means, by id or by name (the ticket list
  /// rows and the create form only know one or the other). Null when neither
  /// identifies a department.
  Future<({int id, String name})?> _department(String? name, int? id) async {
    final trimmed = name?.trim() ?? '';
    if (id != null && id != 0) {
      return (id: id, name: trimmed.isNotEmpty ? trimmed : await _nameOf(id));
    }
    if (trimmed.isEmpty) return null;
    try {
      for (final d in await _meta.departments()) {
        if (d.name.trim().toLowerCase() == trimmed.toLowerCase()) {
          return (id: d.id, name: d.name.trim());
        }
      }
    } catch (_) {
      // Offline or forbidden — treat the department as unknown.
    }
    return null;
  }

  Future<String> _nameOf(int id) async {
    try {
      for (final d in await _meta.departments()) {
        if (d.id == id && d.name.trim().isNotEmpty) return d.name.trim();
      }
    } catch (_) {
      // Fall through to the id-only label.
    }
    return '';
  }
}
