import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/agents/agents_directory_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/canned/canned_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/faq/faq_detail_screen.dart';
import '../../features/faq/faq_screen.dart';
import '../../features/more/more_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/settings/server_settings_screen.dart';
import '../../features/shell/home_shell.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/tasks/create_task_screen.dart';
import '../../features/tasks/task_detail_screen.dart';
import '../../features/tags/tags_screen.dart';
import '../../features/tasks/tasks_list_screen.dart';
import '../../features/team/team_availability_screen.dart';
import '../../features/tickets/create_ticket_screen.dart';
import '../../features/tickets/ticket_detail_screen.dart';
import '../../features/tickets/tickets_list_screen.dart';
import '../../models/task.dart';
import '../../providers.dart';
import '../../widgets/keyboard_dismisser.dart';
import 'routes.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

/// App router with an auth-aware redirect guard and a 4-tab bottom-nav shell.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    // Every detail/secondary route is pushed here (parentNavigatorKey:
    // _rootKey), so one observer covers leaving a page with the keyboard up.
    observers: [KeyboardDismissObserver()],
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      if (!auth.isKnown) return loc == Routes.splash ? null : Routes.splash;

      final loggingIn = loc == Routes.login;
      final onSplash = loc == Routes.splash;
      // Public, pre-auth routes reachable from the login screen.
      final onPublicAuthRoute = loggingIn || loc == Routes.forgotPassword;

      if (!auth.isAuthenticated) {
        return onPublicAuthRoute ? null : Routes.login;
      }
      if (loggingIn || onSplash) return Routes.dashboard;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (_, __) => const ForgotPasswordScreen(),
      ),

      // Bottom-nav shell.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellKey,
            routes: [
              GoRoute(
                path: Routes.dashboard,
                builder: (_, __) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.tickets,
                builder: (_, __) => const TicketsListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.tasks,
                builder: (_, __) => const TasksListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.notifications,
                builder: (_, __) => const NotificationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.more,
                builder: (_, __) => const MoreScreen(),
              ),
            ],
          ),
        ],
      ),

      // Detail / secondary routes (pushed over the shell on the root navigator).
      // `new` is declared before `:id` so it matches the create screen, not the
      // detail route (which would fail to parse "new" as an int).
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.ticketNew,
        builder: (_, __) => const CreateTicketScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/tickets/:id',
        builder: (_, s) => TicketDetailScreen(
          ticketId: int.parse(s.pathParameters['id']!),
          initialTab: _detailTabIndex(s.uri.queryParameters['tab']),
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.taskNew,
        // A "Create task" action on a ticket passes (id, number) as `extra` to
        // pre-link the new task to that ticket; a task's "Add subtask" passes
        // the parent Task itself, which pre-fills parent + department.
        builder: (_, s) {
          final link = s.extra;
          return CreateTaskScreen(
            ticketId: link is ({int id, String number}) ? link.id : null,
            ticketNumber: link is ({int id, String number})
                ? link.number
                : null,
            parentTask: link is Task ? link : null,
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/tasks/:id',
        builder: (_, s) => TaskDetailScreen(
          taskId: int.parse(s.pathParameters['id']!),
          initialTab: _detailTabIndex(s.uri.queryParameters['tab']),
        ),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.faq,
        builder: (_, __) => const FaqScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/faq/:id',
        builder: (_, s) =>
            FaqDetailScreen(faqId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.canned,
        builder: (_, __) => const CannedScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.reports,
        builder: (_, __) => const ReportsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.agents,
        builder: (_, __) => const AgentsDirectoryScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.tags,
        builder: (_, __) => const TagsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.team,
        builder: (_, __) => const TeamAvailabilityScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.profile,
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.serverSettings,
        builder: (_, __) => const ServerSettingsScreen(),
      ),
    ],
  );
});

/// Maps a `?tab=` query value to the tab index shared by the ticket and task
/// detail screens (Conversation / Details / Activity). Anything unrecognised
/// falls back to the Conversation tab, so a hand-typed URL still opens.
int _detailTabIndex(String? tab) => switch (tab) {
  'details' => 1,
  'activity' => 2,
  _ => 0,
};
