import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../models/team_member.dart';
import '../../providers.dart';
import '../../widgets/app_snack.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';

/// "My Team" — the mobile port of `scp/team-availability.php`.
///
/// A department manager marks which of their employees may receive
/// round-robin auto-assigned tickets. `ost_staff.is_available` defaults to
/// off, so nobody is auto-assigned until a manager opts them in.
///
/// The list is the server's own `getManagedEmployees()` set, and it is also
/// the whitelist: `POST /agents/{id}/availability` answers 404 for anyone
/// outside it — including agents that plainly exist — so the screen never
/// offers a row that didn't come from this fetch.
class TeamAvailabilityScreen extends ConsumerStatefulWidget {
  const TeamAvailabilityScreen({super.key});

  @override
  ConsumerState<TeamAvailabilityScreen> createState() =>
      _TeamAvailabilityScreenState();
}

class _TeamAvailabilityScreenState
    extends ConsumerState<TeamAvailabilityScreen> {
  List<TeamMember>? _members;
  Object? _error;
  bool _loading = true;

  /// Ids whose toggle is in flight, so a row can't be double-tapped.
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(teamRepositoryProvider).list();
      if (!mounted) return;
      setState(() {
        _members = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(TeamMember m, bool value) async {
    setState(() => _busy.add(m.id));
    try {
      final saved = await ref
          .read(teamRepositoryProvider)
          .setAvailable(m.id, value);
      if (!mounted) return;
      setState(() {
        _members = [
          for (final x in _members ?? const <TeamMember>[])
            if (x.id == saved.id) saved else x,
        ];
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // 404 here is "not yours to change", never "this agent is gone" — the
      // API won't confirm the existence of an agent outside your departments.
      AppSnack.error(
        context,
        e.isNotFound
            ? '${m.name} is no longer in a department you manage.'
            : e.message,
      );
    } finally {
      if (mounted) setState(() => _busy.remove(m.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Team')),
      body: SafeArea(child: RefreshIndicator(onRefresh: _load, child: _body())),
    );
  }

  Widget _body() {
    // Every branch has to be scrollable, or the pull is swallowed: three of
    // the four states here are centred panels, and a manager's team is short
    // enough that even the list fits the screen.
    if (_loading) return const RefreshableState(child: LoadingView());
    if (_error != null) {
      return RefreshableState(child: ErrorView(error: _error!, onRetry: _load));
    }
    final members = _members ?? const <TeamMember>[];
    if (members.isEmpty) {
      // Managing nobody is an empty list, not a failure — most agents land
      // here, so it must read as a normal state.
      return const RefreshableState(
        child: EmptyView(
          icon: Icons.groups_outlined,
          message: 'No team members',
          hint: 'Only a department manager has employees to opt in here.',
        ),
      );
    }
    return ListView.builder(
      physics: alwaysScrollablePhysics,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: members.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _intro();
        return _row(members[i - 1]);
      },
    );
  }

  Widget _intro() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: AppText.paraText(
        context,
        'An unassigned ticket landing in your department is handed to the '
        'next available employee in rotation. Turn someone on to include '
        'them.',
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  Widget _row(TeamMember m) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _busy.contains(m.id);
    final blocked = m.blockedReason;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SwitchListTile(
        secondary: UserAvatar(name: m.name, radius: 19),
        value: m.available,
        onChanged: busy ? null : (v) => _toggle(m, v),
        title: AppText.subText(context, m.name, fw: 1),
        subtitle: Row(
          children: [
            // `eligible` is the outcome (active, not on vacation, available);
            // the switch is only one of its three inputs.
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: m.eligible ? AppTheme.open : AppTheme.closed,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: AppText.paraText(
                context,
                [
                  m.eligible ? 'Receiving assignments' : (blocked ?? 'Not receiving'),
                  if (m.department != null) m.department!,
                ].join(' · '),
                color: scheme.onSurfaceVariant,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
