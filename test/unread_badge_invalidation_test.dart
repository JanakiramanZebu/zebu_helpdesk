import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/data/notifications_repository.dart';
import 'package:zebu_helpdesk/models/app_notification.dart';
import 'package:zebu_helpdesk/providers.dart';

/// Counts how many times the server was actually asked, and answers with
/// whatever [next] currently is — so a stale badge is unmistakable.
class _CountingRepo implements NotificationsRepository {
  int calls = 0;
  int next = 5;

  @override
  Future<NotificationCounts> counts() async {
    calls++;
    return NotificationCounts(unread: next, total: next);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// `notificationCountsProvider` also watches `authControllerProvider`, whose
/// bootstrap resolves a tick later and refetches on its own. Let that settle
/// before measuring, or the badge appears to refresh for the wrong reason.
Future<void> _settle(ProviderContainer c, _CountingRepo repo) async {
  for (var i = 0; i < 5; i++) {
    await c.read(notificationCountsProvider.future);
    await Future<void>.delayed(Duration.zero);
  }
  repo.calls = 0;
}

ProviderContainer _container(_CountingRepo repo) {
  final c = ProviderContainer(
    overrides: [notificationsRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // authControllerProvider bootstraps off secure storage; answer "no session".
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  test('invalidating notificationCountsProvider refetches the badge', () async {
    final repo = _CountingRepo();
    final c = _container(repo);
    await _settle(c, repo);

    expect(await c.read(unreadCountProvider.future), 5);

    // The server state moved on — an item was marked read.
    repo.next = 2;
    // What every action on the inbox screen, an incoming push, and an app
    // resume now do.
    c.invalidate(notificationCountsProvider);

    expect(await c.read(unreadCountProvider.future), 2,
        reason: 'the badge must show the new server count');
    expect(repo.calls, 1, reason: 'the count endpoint must be re-asked');
  });

  test('invalidating only the derived provider does NOT refetch', () async {
    // The trap this fix was about: unreadCountProvider is a view over
    // notificationCountsProvider, so invalidating it re-runs the derivation
    // against the cached counts and the badge silently never moves. Every
    // call site used to do exactly this.
    final repo = _CountingRepo();
    final c = _container(repo);
    await _settle(c, repo);

    expect(await c.read(unreadCountProvider.future), 5);
    repo.next = 2;
    c.invalidate(unreadCountProvider);

    expect(await c.read(unreadCountProvider.future), 5);
    expect(repo.calls, 0);
  });

  test('the badge tracks the source across repeated refreshes', () async {
    final repo = _CountingRepo();
    final c = _container(repo);
    await _settle(c, repo);

    for (final expected in [4, 0, 9]) {
      repo.next = expected;
      c.invalidate(notificationCountsProvider);
      expect(await c.read(unreadCountProvider.future), expected);
    }
    expect(repo.calls, 3);
  });
}
