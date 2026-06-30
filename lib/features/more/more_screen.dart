import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import '../../core/theme/theme_controller.dart';
import '../../providers.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/states.dart';
import '../../widgets/user_avatar.dart';

/// A settings-style menu hub (the "More" tab).
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final unread = ref.watch(unreadCountProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        children: [
          // --- Profile header card ------------------------------------------
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
            data: (m) {
              final dept = m.primaryDepartment;
              final subtitleParts = <String>[
                if (dept != null) dept.name,
                if (dept?.roleName != null && dept!.roleName!.isNotEmpty)
                  dept.roleName!,
              ];
              return Card(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push(Routes.profile),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        UserAvatar(name: m.name, radius: 28),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                m.email,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (subtitleParts.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitleParts.join(' · '),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // --- Menu items ----------------------------------------------------
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            trailing: _Trailing(
              badge: unread.maybeWhen(
                data: (n) => n > 0 ? n : null,
                orElse: () => null,
              ),
            ),
            onTap: () => context.push(Routes.notifications),
          ),
          ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('Users'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.users),
          ),
          ListTile(
            leading: const Icon(Icons.business_outlined),
            title: const Text('Organizations'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.organizations),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Knowledgebase'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.faq),
          ),
          ListTile(
            leading: const Icon(Icons.quickreply_outlined),
            title: const Text('Canned Responses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.canned),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('Saved Queues'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.queues),
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: const Text('Reports'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.reports),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Profile & Settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.profile),
          ),
          ListTile(
            leading: Icon(_themeIcon(themeMode)),
            title: const Text('Appearance'),
            subtitle: Text(_themeLabel(themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _chooseTheme(context, ref, themeMode),
          ),

          const Divider(height: 24),

          ListTile(
            leading: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Sign out',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => _confirmSignOut(context, ref),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  static String _themeLabel(ThemeMode m) => switch (m) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'System default',
  };

  static IconData _themeIcon(ThemeMode m) => switch (m) {
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
    ThemeMode.system => Icons.brightness_auto_outlined,
  };

  Future<void> _chooseTheme(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final bottom = MediaQuery.of(sheetContext).padding.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom + 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Appearance',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final mode in ThemeMode.values)
                ListTile(
                  leading: Icon(_themeIcon(mode)),
                  title: Text(_themeLabel(mode)),
                  trailing: mode == current
                      ? Icon(
                          Icons.check,
                          color: Theme.of(sheetContext).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    ref.read(themeModeProvider.notifier).set(mode);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        );
      },
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

class _Trailing extends StatelessWidget {
  const _Trailing({this.badge});
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final b = badge;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (b != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              b > 99 ? '99+' : '$b',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(width: 6),
        const Icon(Icons.chevron_right),
      ],
    );
  }
}
