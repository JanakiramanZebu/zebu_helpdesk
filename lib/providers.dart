import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/api_client.dart';
import 'core/auth/auth_controller.dart';
import 'core/auth/token_storage.dart';
import 'core/config.dart';
import 'core/network/server_config.dart';
import 'core/push/push_service.dart';
import 'data/auth_repository.dart';
import 'data/canned_repository.dart';
import 'data/faq_repository.dart';
import 'data/me_repository.dart';
import 'data/meta_repository.dart';
import 'data/notifications_repository.dart';
import 'data/orgs_repository.dart';
import 'data/password_reset_repository.dart';
import 'data/push_repository.dart';
import 'data/queues_repository.dart';
import 'data/reports_repository.dart';
import 'data/tasks_repository.dart';
import 'data/tickets_repository.dart';
import 'data/users_repository.dart';
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

final orgsRepositoryProvider = Provider<OrgsRepository>(
  (ref) => OrgsRepository(ref.watch(apiClientProvider)),
);

final cannedRepositoryProvider = Provider<CannedRepository>(
  (ref) => CannedRepository(ref.watch(apiClientProvider)),
);

final faqRepositoryProvider = Provider<FaqRepository>(
  (ref) => FaqRepository(ref.watch(apiClientProvider)),
);

final queuesRepositoryProvider = Provider<QueuesRepository>(
  (ref) => QueuesRepository(ref.watch(apiClientProvider)),
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

final metaRepositoryProvider = Provider<MetaRepository>(
  (ref) => MetaRepository(ref.watch(apiClientProvider)),
);

// --- Derived async state ----------------------------------------------------

/// The authenticated agent's full `GET /me` profile (auto-refreshes on auth
/// changes).
final meProvider = FutureProvider<Me>((ref) async {
  // Re-fetch whenever auth status changes.
  ref.watch(authControllerProvider);
  return ref.watch(meRepositoryProvider).getMe();
});

/// Unread notification count, used for the bell badge.
final unreadCountProvider = FutureProvider<int>((ref) async {
  ref.watch(authControllerProvider);
  return ref.watch(notificationsRepositoryProvider).count();
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
