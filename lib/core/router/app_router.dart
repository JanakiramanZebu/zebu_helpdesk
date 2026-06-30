import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/canned/canned_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/faq/faq_detail_screen.dart';
import '../../features/faq/faq_screen.dart';
import '../../features/more/more_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/organizations/org_detail_screen.dart';
import '../../features/organizations/orgs_list_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/queues/queues_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/shell/home_shell.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/tasks/create_task_screen.dart';
import '../../features/tasks/task_detail_screen.dart';
import '../../features/tasks/tasks_list_screen.dart';
import '../../features/tickets/create_ticket_screen.dart';
import '../../features/tickets/ticket_detail_screen.dart';
import '../../features/tickets/tickets_list_screen.dart';
import '../../features/users/user_detail_screen.dart';
import '../../features/users/users_list_screen.dart';
import '../../providers.dart';
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
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;

      if (!auth.isKnown) return loc == Routes.splash ? null : Routes.splash;

      final loggingIn = loc == Routes.login;
      final onSplash = loc == Routes.splash;

      if (!auth.isAuthenticated) return loggingIn ? null : Routes.login;
      if (loggingIn || onSplash) return Routes.dashboard;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),

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
        builder: (_, s) =>
            TicketDetailScreen(ticketId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.taskNew,
        builder: (_, __) => const CreateTaskScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/tasks/:id',
        builder: (_, s) =>
            TaskDetailScreen(taskId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.notifications,
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.users,
        builder: (_, __) => const UsersListScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/users/:id',
        builder: (_, s) =>
            UserDetailScreen(userId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.organizations,
        builder: (_, __) => const OrgsListScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/organizations/:id',
        builder: (_, s) =>
            OrgDetailScreen(orgId: int.parse(s.pathParameters['id']!)),
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
        path: Routes.queues,
        builder: (_, __) => const QueuesScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.reports,
        builder: (_, __) => const ReportsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: Routes.profile,
        builder: (_, __) => const ProfileScreen(),
      ),
    ],
  );
});
