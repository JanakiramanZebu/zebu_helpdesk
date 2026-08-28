import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/api_client.dart';
import 'core/auth/auth_controller.dart';
import 'core/auth/token_storage.dart';
import 'core/config.dart';
import 'core/network/server_config.dart';
import 'core/push/push_service.dart';
import 'data/agent_directory.dart';
import 'data/auth_repository.dart';
import 'data/canned_repository.dart';
import 'data/faq_repository.dart';
import 'data/me_repository.dart';
import 'data/meta_repository.dart';
import 'data/notifications_repository.dart';
import 'data/orgs_repository.dart';
import 'data/password_reset_repository.dart';
import 'data/push_repository.dart';
import 'data/reports_repository.dart';
import 'data/tags_repository.dart';
import 'data/tasks_repository.dart';
import 'data/team_repository.dart';
import 'data/tickets_repository.dart';
import 'data/users_repository.dart';
import 'models/app_notification.dart';
import 'models/me.dart';

/// Central dependency-injection graph for the app.

// --- Core -------------------------------------------------------------------

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final apiClientProvider = Provider<ApiClient>((ref) {
  final tokens = ref.watch(tokenStorageProvider);
  // Rebuild (and re-point Dio) whenever the configured base URL changes.
  final baseUrl = ref.watch(serverConfigProvider);
  return ApiClient(
    tokenStorage: tokens,
    apiRoot: AppConfig.apiRootFor(baseUrl),
    onSessionExpired: () =>
        ref.read(authControllerProvider.notifier).onSessionExpired(),
  );
});

// --- Auth -------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStorageProvider),
  ),
);

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Agent self-service "forgot password" flow (`/auth/forgot-password` +
/// `/auth/reset-password`). Public endpoints — no bearer required.
final passwordResetRepositoryProvider = Provider<PasswordResetRepository>(
  (ref) => PasswordResetRepository(ref.watch(apiClientProvider)),
);

// --- Repositories -----------------------------------------------------------

final meRepositoryProvider = Provider<MeRepository>(
  (ref) => MeRepository(ref.watch(apiClientProvider)),
);

final ticketsRepositoryProvider = Provider<TicketsRepository>(
  (ref) => TicketsRepository(ref.watch(apiClientProvider)),
);

final tasksRepositoryProvider = Provider<TasksRepository>(
  (ref) => TasksRepository(ref.watch(apiClientProvider)),
);

final usersRepositoryProvider = Provider<UsersRepository>(
  (ref) => UsersRepository(ref.watch(apiClientProvider)),
);

/// Read-only `/organizations` access — the Reports page's Organizations
/// report is the only thing that still needs it.
final orgsRepositoryProvider = Provider<OrgsRepository>(
  (ref) => OrgsRepository(ref.watch(apiClientProvider)),
);

final cannedRepositoryProvider = Provider<CannedRepository>(
  (ref) => CannedRepository(ref.watch(apiClientProvider)),
);

final faqRepositoryProvider = Provider<FaqRepository>(
  (ref) => FaqRepository(ref.watch(apiClientProvider)),
);

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);

final pushRepositoryProvider = Provider<PushRepository>(
  (ref) => PushRepository(ref.watch(apiClientProvider)),
);

/// FCM lifecycle manager: requests notification permission, registers the
/// device token with the backend, and routes notification taps. Started once
/// the user is authenticated (see `HomeShell`) and stopped on logout.
final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(ref),
);

final reportsRepositoryProvider = Provider<ReportsRepository>(
  (ref) => ReportsRepository(ref.watch(apiClientProvider)),
);

/// The shared tag catalogue (`/tags`) — create, rename, recolor, enable /
/// disable, merge, delete.
final tagsRepositoryProvider = Provider<TagsRepository>(
  (ref) => TagsRepository(ref.watch(apiClientProvider)),
);

/// Round-robin availability for the agents a manager is responsible for.
final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => TeamRepository(ref.watch(apiClientProvider)),
);

final metaRepositoryProvider = Provider<MetaRepository>(
  (ref) => MetaRepository(ref.watch(apiClientProvider)),
);

/// Department-scoped agent pick-lists for the assign/reassign flows.
final agentDirectoryProvider = Provider<AgentDirectory>(
  (ref) => AgentDirectory(ref.watch(metaRepositoryProvider)),
);

// --- Derived async state ----------------------------------------------------

/// The authenticated agent's full `GET /me` profile (auto-refreshes on auth
/// changes).
final meProvider = FutureProvider<Me>((ref) async {
  // Re-fetch whenever auth status changes.
  ref.watch(authControllerProvider);
  return ref.watch(meRepositoryProvider).getMe();
});

/// Unread notification totals (`GET /notifications/count`).
///
/// **This provider owns the fetch — invalidate *this* one to refresh a badge.**
/// [unreadCountProvider] only derives from it, so invalidating that instead
/// re-runs the derivation against this provider's still-cached value and
/// silently changes nothing.
final notificationCountsProvider = FutureProvider<NotificationCounts>((
  ref,
) async {
  ref.watch(authControllerProvider);
  return ref.watch(notificationsRepositoryProvider).counts();
});

/// The unread badge shown on the nav bell, the More row and the inbox's Unread
/// chip: unread **conversations**, not notification rows, so every badge
/// matches the cards the inbox lists (and the web's `Unread (n)`). The server
/// counts objects now, so this is `data.unread` straight off the payload.
///
/// Read-only view over [notificationCountsProvider] — see the note there before
/// reaching for `invalidate`.
final unreadCountProvider = FutureProvider<int>((ref) async {
  final counts = await ref.watch(notificationCountsProvider.future);
  return counts.unread;
});

// --- UI cross-tab signals ---------------------------------------------------

/// A pending list filter requested from another tab (e.g. tapping a dashboard
/// stat tile). The target list screen applies it and resets it to null.
class ViewRequest extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? view) => state = view;
}

/// Pending Tickets-list filter requested from another tab.
final ticketsViewRequestProvider = NotifierProvider<ViewRequest, String?>(
  ViewRequest.new,
);

/// Pending Tasks-list filter requested from another tab.
final tasksViewRequestProvider = NotifierProvider<ViewRequest, String?>(
  ViewRequest.new,
);

/// A monotonically-increasing revision that bumps whenever a ticket/task is
/// mutated (edited, status-changed, assigned, …) from anywhere — most
/// importantly the detail screen. The matching list folds this into its refresh
/// key so it refetches after an edit instead of showing stale rows. Because the
/// list route stays mounted behind the pushed detail, the refetch runs while
/// the detail is still on top, so returning to the list shows fresh data.
class Revision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final tasksChangedProvider = NotifierProvider<Revision, int>(Revision.new);
final ticketsChangedProvider = NotifierProvider<Revision, int>(Revision.new);

/// Bumped when a knowledgebase article or category is created, edited,
/// published or deleted. The Knowledgebase screen reloads its categories on
/// it, so an article edited from the detail screen doesn't leave a stale row
/// (or a stale article count) on the list behind it.
final faqChangedProvider = NotifierProvider<Revision, int>(Revision.new);

/// Bumped when the inbox may have changed underneath us — a push arrived, or
/// the app came back to the foreground after alerts landed in the tray while it
/// was backgrounded. The Alerts screen folds it into its refresh key so the
/// list reloads instead of showing the pre-push state until a manual pull.
final notificationsChangedProvider = NotifierProvider<Revision, int>(
  Revision.new,
);

/// Per-branch reset counters for the bottom-nav shell, keyed by branch index.
///
/// `StatefulShellRoute.indexedStack` keeps every branch mounted, so a tab
/// resumed wherever the agent left it — mid-search, filtered, scrolled down.
/// Tapping a tab bumps that branch's counter and the router rebuilds its root
/// screen under a fresh key, discarding the old State: the tab always opens in
/// its initial state, with search cleared, filters/sort back to defaults and
/// the list refetched.
class BranchEpochs extends Notifier<Map<int, int>> {
  @override
  Map<int, int> build() => const {};

  void bump(int branch) => state = {...state, branch: (state[branch] ?? 0) + 1};
}

final branchEpochProvider = NotifierProvider<BranchEpochs, Map<int, int>>(
  BranchEpochs.new,
);
