import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../models/me.dart';
import '../../models/meta.dart';
import '../../providers.dart';
import '../../widgets/app_search_field.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';

/// Colleague directory. Lists active agents from `GET /meta/agents` and, on tap,
/// loads the full profile from `GET /agents/{id}` (name, contact, department,
/// role, availability, open-ticket count) in a bottom sheet.
///
/// The roster is narrowed the way the web's `scp/directory.php` narrows it —
/// to the departments this agent can access, unless they hold
/// `visibility.agents` — via [AgentDirectory.visible].
class AgentsDirectoryScreen extends ConsumerStatefulWidget {
  const AgentsDirectoryScreen({super.key});

  @override
  ConsumerState<AgentsDirectoryScreen> createState() =>
      _AgentsDirectoryScreenState();
}

class _AgentsDirectoryScreenState extends ConsumerState<AgentsDirectoryScreen> {
  final _searchCtrl = TextEditingController();
  List<MetaItem> _agents = const [];

  /// Whether [_agents] is actually narrower than the full roster — drives the
  /// scope note, so a short list never reads as "these are all the agents".
  bool _scoped = false;
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Scoping needs /me for the permission + department set; without it (a
      // cold cache or a failed refresh) fall back to the unscoped roster
      // rather than showing nobody.
      final me = await ref.read(meProvider.future);
      final list = await ref.read(agentDirectoryProvider).visible(me);
      if (mounted) {
        setState(() {
          _agents = list.agents;
          _scoped = list.scoped;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  List<MetaItem> get _filtered {
    if (_query.isEmpty) return _agents;
    final q = _query.toLowerCase();
    return _agents.where((a) => a.name.toLowerCase().contains(q)).toList();
  }

  Future<void> _openAgent(int id) async {
    await showAppSheet<void>(
      context: context,
      builder: (_) => _AgentDetailSheet(agentId: id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return Scaffold(
      appBar: AppBar(title: AppText.titleText(context, 'Agent Directory', fw: 1)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: AppSearchField(
                controller: _searchCtrl,
                hintText: 'Search agents',
                onChanged: (v) => setState(() => _query = v.trim()),
                onSubmitted: (v) => setState(() => _query = v.trim()),
                onClear: () => setState(() => _query = ''),
              ),
            ),
            if (_scoped && !_loading && _error == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: AppText.paraText(
                        context,
                        'Agents in your departments',
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const LoadingView()
                  : _error != null
                  ? ErrorView(error: _error!, onRetry: _load)
                  : items.isEmpty
                  ? const EmptyView(message: 'No agents found')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                          indent: 68,
                        ),
                        itemBuilder: (_, i) {
                          final a = items[i];
                          return ListTile(
                            leading: UserAvatar(name: a.name),
                            title: AppText.subText(context, a.name, fw: 1),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openAgent(a.id),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that loads and shows a single agent's profile.
class _AgentDetailSheet extends ConsumerStatefulWidget {
  const _AgentDetailSheet({required this.agentId});
  final int agentId;

  @override
  ConsumerState<_AgentDetailSheet> createState() => _AgentDetailSheetState();
}

class _AgentDetailSheetState extends ConsumerState<_AgentDetailSheet> {
  AgentProfile? _agent;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await ref.read(meRepositoryProvider).getAgent(widget.agentId);
      if (mounted) {
        setState(() {
          _agent = a;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = _agent;
    return AppSheet(
      title: a?.name ?? 'Agent',
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          : _error != null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AppText.subText(context, _error!),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    UserAvatar(name: a!.name, radius: 26),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText.titleText(context, a.name, fw: 1),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: a.available
                                      ? AppTheme.open
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 6),
                              AppText.paraText(
                                context,
                                a.available ? 'Available' : 'Unavailable',
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (a.email != null)
                  _InfoRow(icon: Icons.email_outlined, label: 'Email', value: a.email!),
                if (a.phone != null)
                  _InfoRow(icon: Icons.phone_outlined, label: 'Phone', value: a.phone!),
                if (a.department != null)
                  _InfoRow(
                    icon: Icons.apartment_outlined,
                    label: 'Department',
                    value: a.department!,
                  ),
                if (a.role != null)
                  _InfoRow(
                    icon: Icons.badge_outlined,
                    label: 'Role',
                    value: a.role!,
                  ),
                _InfoRow(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Open tickets',
                  value: '${a.openTickets}',
                ),
              ],
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText.paraText(context, label, color: scheme.onSurfaceVariant),
                const SizedBox(height: 2),
                AppText.subText(context, value, fw: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
