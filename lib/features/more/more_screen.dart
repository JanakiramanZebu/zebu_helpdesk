import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/assets.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../models/me.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/states.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/svg_icon.dart';
import '../../widgets/user_avatar.dart';

/// A settings-style menu hub (the "More" tab).
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final unread = ref.watch(unreadCountProvider);
    final themeMode = ref.watch(themeModeProvider);

    final unreadBadge = unread.maybeWhen(
      data: (n) => n > 0 ? n : null,
      orElse: () => null,
    );

    // Permission-gated menu entries. While /me is loading the tile stays
    // hidden rather than flashing in and out — the screens behind them are
    // reachable only from here, and the backend is the real guard anyway.
    final canManageCanned = me.maybeWhen(
      data: (m) => m.canManageCanned,
      orElse: () => false,
    );
    final canViewReports = me.maybeWhen(
      data: (m) => m.canViewReports,
      orElse: () => false,
    );
    // The web shows Tags and My Team as their own top-level tabs, to
    // department managers (`Tag::canManage()` /
    // `Staff::getManagedDepartments()`). Tags also admits admins here, who on
    // the web would curate them from the Admin Panel instead — mobile has no
    // admin panel, so this is their only route to the vocabulary.
    final canManageTags = me.maybeWhen(
      data: (m) => m.canManageTags,
      orElse: () => false,
    );
    final managesTeam = me.maybeWhen(
      data: (m) => m.managesAnyDepartment,
      orElse: () => false,
    );

    return Scaffold(
      appBar: AppBar(
        // Menu is a root bottom-nav tab, so there's no route to pop — send the
        // back affordance to the Dashboard (home) tab instead.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Dashboard',
          onPressed: () => context.go(Routes.dashboard),
        ),
        title: const Text('Menu'),
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        children: [
          // --- Gradient profile header --------------------------------------
          me.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LoadingView(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: ErrorView(
                error: e,
                onRetry: () => ref.invalidate(meProvider),
              ),
            ),
            data: (m) => _ProfileHeader(
              me: m,
              onTap: () => context.push(Routes.profile),
            ),
          ),

          // --- Workspace section --------------------------------------------
          _Section(
            title: 'Workspace',
            children: [
              _MenuTile(
                icon: Assets.menuInbox,
                color: AppTheme.brand,
                label: 'Inbox',
                badge: unreadBadge,
                onTap: () => context.push(Routes.notifications),
              ),
              _MenuTile(
                icon: Assets.menuAgents,
                color: AppTheme.brand,
                label: 'Agent Directory',
                onTap: () => context.push(Routes.agents),
              ),
              if (canViewReports)
                _MenuTile(
                  icon: Assets.menuReports,
                  color: AppTheme.warning,
                  label: 'Reports',
                  onTap: () => context.push(Routes.reports),
                ),
              if (managesTeam)
                _MenuTile(
                  icon: Assets.actCollaborators,
                  color: AppTheme.brand,
                  label: 'My Team',
                  onTap: () => context.push(Routes.team),
                ),
            ],
          ),

          // --- Resources section --------------------------------------------
          // Knowledgebase is ungated for every agent, matching the web's
          // `kbase` tab; Canned Responses needs `canned.manage` on one of the
          // agent's roles, matching that tab's sub-nav (see [Me.canManageCanned]).
          _Section(
            title: 'Resources',
            children: [
              _MenuTile(
                icon: Assets.menuKnowledge,
                color: AppTheme.brandLight,
                label: 'Knowledgebase',
                onTap: () => context.push(Routes.faq),
              ),
              if (canManageCanned)
                _MenuTile(
                  icon: Assets.menuCanned,
                  color: AppTheme.open,
                  label: 'Canned Responses',
                  onTap: () => context.push(Routes.canned),
                ),
              if (canManageTags)
                _MenuTile(
                  icon: Assets.actTag,
                  color: AppTheme.warning,
                  label: 'Tags',
                  onTap: () => context.push(Routes.tags),
                ),
            ],
          ),

          // --- Appearance (inline theme toggle) -----------------------------
          _Section(
            title: 'Appearance',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: _ThemeToggle(
                  current: themeMode,
                  onChanged: (m) =>
                      ref.read(themeModeProvider.notifier).set(m),
                ),
              ),
            ],
          ),

          // --- Sign out -----------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: OutlinedButton.icon(
              onPressed: () => _confirmSignOut(context, ref),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    // Capture the router up front — after logout this widget (a shell branch)
    // is torn down, so its context can't be used to navigate.
    final router = GoRouter.of(context);
    final ok = await showAppConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'You will need to sign in again to continue.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (ok != true) return;
    await ref.read(authControllerProvider.notifier).logout();
    // Drive the navigation explicitly. Relying only on the redirect guard while
    // inside a StatefulShellRoute can leave a blank/black route after sign-out.
    router.go(Routes.login);
  }
}

/// Clean surface profile header at the top of the menu — consistent with the
/// menu section cards below it. Shows the app's standard [UserAvatar] with a
/// live availability dot, the name with an optional Admin badge, email, and a
/// status/department/role chip row. Tap to open the profile.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.me, required this.onTap});

  final Me me;
  final VoidCallback onTap;

  /// (color, label) for the agent's current availability.
  ({Color color, String label}) get _status {
    if (me.profile.onVacation) {
      return (color: AppTheme.warning, label: 'On vacation');
    }
    if (me.available) return (color: AppTheme.open, label: 'Available');
    return (color: const Color(0xFFBDBDBD), label: 'Away');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _status;
    final dept = me.primaryDepartment;
    final role = dept?.roleName;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _AvatarWithStatus(
                      name: me.name,
                      statusColor: status.color,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: AppText.titleText(
                                  context,
                                  me.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  fw: 2,
                                ),
                              ),
                              if (me.isAdmin) ...[
                                const SizedBox(width: 8),
                                const _AdminBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                Icons.mail_outline,
                                size: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 5),
                              Flexible(
                                child: AppText.paraText(
                                  context,
                                  me.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Meta chips: live status + department + role.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(label: status.label, color: status.color, dense: true),
                    if (dept != null)
                      MetaChip(icon: Icons.apartment_rounded, label: dept.name),
                    if (role != null && role.isNotEmpty)
                      MetaChip(icon: Icons.badge_outlined, label: role),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's [UserAvatar] with a live status dot in the bottom-right corner,
/// ringed against the card surface.
class _AvatarWithStatus extends StatelessWidget {
  const _AvatarWithStatus({required this.name, required this.statusColor});
  final String name;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        UserAvatar(name: name, radius: 26),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 2.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// A soft-tinted brand "Admin" badge shown next to the name for admin agents.
class _AdminBadge extends StatelessWidget {
  const _AdminBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_outlined, size: 12, color: AppTheme.brand),
          const SizedBox(width: 4),
          AppText.overlineText(context, 'ADMIN', color: AppTheme.brand, fw: 2),
        ],
      ),
    );
  }
}

/// A labelled group of menu tiles rendered inside a single rounded card.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: AppText.captionText(
            context,
            title.toUpperCase(),
            color: scheme.onSurfaceVariant,
            fw: 2,
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i != 0) const Divider(height: 1, indent: 60),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A menu row with a soft-tinted rounded icon badge, an optional count badge,
/// and a trailing chevron. The badge tint derives from [color].
class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.badge,
  });

  /// Path to a bundled SVG glyph (see [Assets]).
  final String icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: SvgIcon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppText.custmText(context, label, fs: 15, fw: 0),
            ),
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.error,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AppText.paraText(
                  context,
                  badge! > 99 ? '99+' : '${badge!}',
                  color: Colors.white,
                  fw: 2,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Inline System / Light / Dark segmented control that drives the theme mode.
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.current, required this.onChanged});

  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  static const _options = <(ThemeMode, IconData, String)>[
    (ThemeMode.system, Icons.brightness_auto_outlined, 'System'),
    (ThemeMode.light, Icons.light_mode_outlined, 'Light'),
    (ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final track = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF1F1F1);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final (mode, icon, label) in _options)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: mode == current
                        ? scheme.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: mode == current
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: mode == current
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 4),
                      AppText.paraText(
                        context,
                        label,
                        fw: mode == current ? 2 : 0,
                        color: mode == current
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
