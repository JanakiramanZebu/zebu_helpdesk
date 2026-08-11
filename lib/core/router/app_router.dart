import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../responsive/responsive_body.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/web/login_screen_web.dart';
import '../../features/canned/canned_screen.dart';
import '../../features/canned/web/canned_screen_web.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/dashboard/web/dashboard_screen_web.dart';
import '../../features/faq/faq_detail_screen.dart';
import '../../features/faq/faq_screen.dart';
import '../../features/faq/web/faq_screen_web.dart';
import '../../features/more/more_screen.dart';
import '../../features/more/web/more_screen_web.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/notifications/web/notifications_screen_web.dart';
import '../../features/organizations/org_detail_screen.dart';
import '../../features/organizations/orgs_list_screen.dart';
import '../../features/organizations/web/orgs_list_screen_web.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/queues/queues_screen.dart';
import '../../features/queues/web/queues_screen_web.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/reports/web/reports_screen_web.dart';
import '../../features/shell/home_shell.dart';
import '../../features/shell/web/home_shell_web.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/tasks/create_task_screen.dart';
import '../../features/tasks/task_detail_screen.dart';
import '../../features/tasks/tasks_list_screen.dart';
import '../../features/tasks/web/tasks_list_screen_web.dart';
import '../../features/tickets/create_ticket_screen.dart';
import '../../features/tickets/ticket_detail_screen.dart';
import '../../features/tickets/tickets_list_screen.dart';
import '../../features/tickets/web/create_ticket_screen_web.dart';
import '../../features/tickets/web/tickets_list_screen_web.dart';
import '../../features/users/user_detail_screen.dart';
import '../../features/users/users_list_screen.dart';
import '../../features/users/web/users_list_screen_web.dart';
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
      GoRoute(
        path: Routes.login,
        builder: (_, __) =>
            kIsWeb ? const LoginScreenWeb() : const LoginScreen(),
      ),

      // Bottom-nav shell. On web, swap in the desktop-style sidebar shell.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            kIsWeb ? HomeShellWeb(shell: shell) : HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellKey,
            routes: [
              GoRoute(
                path: Routes.dashboard,
                builder: (_, __) => kIsWeb
                    ? const DashboardScreenWeb()
                    : const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.tickets,
                builder: (_, __) => kIsWeb
                    ? const TicketsListScreenWeb()
                    : const TicketsListScreen(),
                // Web-only: nest /tickets/new inside the tickets branch so
                // pushing it keeps the shell (sidebar + top bar) visible.
                // Mobile keeps this as a root-pushed route below.
                routes: [
                  if (kIsWeb)
                    GoRoute(
                      path: 'new',
                      builder: (_, __) => const CreateTicketScreenWeb(),
                    ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.tasks,
                builder: (_, __) => kIsWeb
                    ? const TasksListScreenWeb()
                    : const TasksListScreen(),
                // Web-only: nest /tasks/new and /tasks/:id inside the tasks
                // branch so pushing them keeps the shell (sidebar + top bar)
                // visible. Mobile keeps these as root-pushed routes below.
                routes: [
                  if (kIsWeb) ...[
                    GoRoute(
                      path: 'new',
                      builder: (_, __) => const CreateTaskScreen(),
                    ),
                    // Deep link — renders the list with the detail panel
                    // already open, rather than a second full-page task UI.
                    GoRoute(
                      path: ':id',
                      builder: (_, s) => TasksListScreenWeb(
                        openTaskId: int.tryParse(s.pathParameters['id'] ?? ''),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          // Web-only branch — makes /notifications render inside the shell
          // (sidebar stays visible), matching Dashboard / Tickets / Tasks.
          // On mobile, notifications is a root-pushed route below so the
          // pushed screen keeps its full-screen AppBar + back button.
          if (kIsWeb)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: Routes.notifications,
                  builder: (_, __) => const NotificationsScreenWeb(),
                ),
              ],
            ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.more,
                builder: (_, __) =>
                    kIsWeb ? const MoreScreenWeb() : const MoreScreen(),
              ),
              // Web-only: /users lives inside the More branch so the
              // sidebar stays visible (More tab remains highlighted).
              // Mobile keeps /users as a root-pushed route below.
              if (kIsWeb)
                GoRoute(
                  path: Routes.users,
                  builder: (_, __) => const UsersListScreenWeb(),
                ),
              // Web-only: /organizations lives inside the More branch so
              // the sidebar stays visible (More tab remains highlighted).
              // Mobile keeps /organizations as a root-pushed route below.
              // The org detail slide-over panel handles view/edit/notes/
              // members inline, so no nested detail route is required
              // here — the list-page panel covers those flows.
              if (kIsWeb)
                GoRoute(
                  path: Routes.organizations,
                  builder: (_, __) => const OrgsListScreenWeb(),
                ),
              // Web-only: /canned lives inside the More branch so the
              // sidebar stays visible. Mobile keeps the pushed route below.
              // Detail is handled inline by a slide-over panel, so no
              // nested detail route is required here.
              if (kIsWeb)
                GoRoute(
                  path: Routes.canned,
                  builder: (_, __) => const CannedScreenWeb(),
                ),
              // Web-only: /faq (Knowledgebase) lives inside the More
              // branch so the sidebar stays visible. Slide-over panel
              // covers the article detail, so no nested detail route.
              if (kIsWeb)
                GoRoute(
                  path: Routes.faq,
                  builder: (_, __) => const FaqScreenWeb(),
                ),
              // Web-only: /queues lives inside the More branch. Rows
              // navigate to the tickets/tasks list, so no detail route.
              if (kIsWeb)
                GoRoute(
                  path: Routes.queues,
                  builder: (_, __) => const QueuesScreenWeb(),
                ),
              // Web-only: /reports lives inside the More branch so the
              // sidebar stays visible.
              if (kIsWeb)
                GoRoute(
                  path: Routes.reports,
                  builder: (_, __) => const ReportsScreenWeb(),
                ),
            ],
          ),
          // Profile has no dedicated route on web — it opens as a modal
          // dialog (see [showProfileDialog]) so it can appear over any
          // page without swapping branches. Mobile still uses a pushed
          // route (declared below).
        ],
      ),

      // Detail / secondary routes (pushed over the shell on the root navigator).
      // `new` is declared before `:id` so it matches the create screen, not the
      // detail route (which would fail to parse "new" as an int).
      //
      // Each builder wraps its screen in [ResponsiveBody] so the content is
      // centered with a sensible max-width on widescreen browsers. The shell
      // branches above do the same wrap via [HomeShell]; this covers the
      // routes that push over the shell on the root navigator.
      // Mobile-only: ticket create pushes over the shell with an AppBar +
      // back button. On web the same path is nested inside the tickets
      // shell branch above so the sidebar stays visible.
      if (!kIsWeb)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: Routes.ticketNew,
          builder: (_, __) => const ResponsiveBody(child: CreateTicketScreen()),
        ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/tickets/:id',
        builder: (_, s) => ResponsiveBody(
          child: TicketDetailScreen(
            ticketId: int.parse(s.pathParameters['id']!),
          ),
        ),
      ),
      // Mobile-only: task create + detail push over the shell (native back
      // button + AppBar). On web these paths are nested inside the tasks
      // shell branch above, so the sidebar stays visible.
      if (!kIsWeb) ...[
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: Routes.taskNew,
          builder: (_, __) => const ResponsiveBody(child: CreateTaskScreen()),
        ),
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: '/tasks/:id',
          builder: (_, s) => ResponsiveBody(
            child: TaskDetailScreen(taskId: int.parse(s.pathParameters['id']!)),
          ),
        ),
      ],
      // Mobile-only: pushed full-screen over the shell (native back button +
      // AppBar). On web this same path is served by the shell branch above,
      // so the sidebar stays visible.
      if (!kIsWeb)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: Routes.notifications,
          builder: (_, __) =>
              const ResponsiveBody(child: NotificationsScreen()),
        ),
      // Mobile-only: /users pushes over the shell. On web the same path
      // is nested inside the More shell branch above so the sidebar
      // stays visible.
      if (!kIsWeb)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: Routes.users,
          builder: (_, __) => const ResponsiveBody(child: UsersListScreen()),
        ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/users/:id',
        builder: (_, s) => ResponsiveBody(
          child: UserDetailScreen(userId: int.parse(s.pathParameters['id']!)),
        ),
      ),
      // Mobile-only: /organizations pushes over the shell. On web the
      // same path is nested inside the More shell branch above so the
      // sidebar stays visible.
      if (!kIsWeb)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: Routes.organizations,
          builder: (_, __) => const ResponsiveBody(child: OrgsListScreen()),
        ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/organizations/:id',
        builder: (_, s) => ResponsiveBody(
          child: OrgDetailScreen(orgId: int.parse(s.pathParameters['id']!)),
        ),
      ),
      // Mobile-only: /faq pushes over the shell. On web the same path
      // is served by the shell branch above so the sidebar stays visible.
      if (!kIsWeb)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: Routes.faq,
          builder: (_, __) => const ResponsiveBody(child: FaqScreen()),
        ),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/faq/:id',
        builder: (_, s) => ResponsiveBody(
          child: FaqDetailScreen(faqId: int.parse(s.pathParameters['id']!)),
        ),
      ),
      // Mobile-only: /canned pushes over the shell. On web the same path
      // is served by the shell branch above so the sidebar stays visible.
      if (!kIsWeb)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: Routes.canned,
          builder: (_, __) => const ResponsiveBody(child: CannedScreen()),
        ),
      // Mobile-only: /queues pushes over the shell. On web the same
      // path is served by the shell branch above so the sidebar stays
      // visible.
      if (!kIsWeb)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: Routes.queues,
          builder: (_, __) => const ResponsiveBody(child: QueuesScreen()),
        ),
      // Mobile-only: /reports pushes over the shell. On web the same
      // path is served by the shell branch above so the sidebar stays
      // visible.
      if (!kIsWeb)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: Routes.reports,
          builder: (_, __) => const ResponsiveBody(child: ReportsScreen()),
        ),
      // Mobile-only: profile pushes over the shell (native back button +
      // AppBar). On web the same path is served by the shell branch
      // above so the sidebar stays visible.
      if (!kIsWeb)
        GoRoute(
          parentNavigatorKey: _rootKey,
          path: Routes.profile,
          builder: (_, __) => const ResponsiveBody(child: ProfileScreen()),
        ),
    ],
  );
});
