import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/paginated.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/notifications_repository.dart';
import 'package:zebu_helpdesk/features/notifications/notifications_screen.dart';
import 'package:zebu_helpdesk/models/app_notification.dart';
import 'package:zebu_helpdesk/providers.dart';

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;

  // The unread badge watches auth, whose bootstrap reads the cached agent —
  // keep it off the secure-storage plugin in tests.
  @override
  Future<Map<String, dynamic>?> readAgentSnapshot() async => null;
}

ApiClient _api() => ApiClient(tokenStorage: _NoTokens(), dio: Dio());

/// Ticket #5 carries six unread activities, ticket #7 one, ticket #9 one that
/// is already read — so the inbox is **7 unread rows** but only **2 unread
/// cards**. Events differ per row so [NotificationGroup] doesn't collapse them.
List<AppNotification> _rows() {
  final events = ['message', 'note', 'status', 'transfer', 'assigned', 'mention'];
  return [
    for (var i = 0; i < events.length; i++)
      AppNotification(
        id: 100 + i,
        type: 'ticket',
        objectId: 5,
        event: events[i],
        title: 'Payout not received',
        actor: 'Ravi',
        created: DateTime(2026, 8, 20, 10, i),
      ),
    AppNotification(
      id: 200,
      type: 'ticket',
      objectId: 7,
      event: 'message',
      title: 'Certificate renewal',
      actor: 'Meera',
      created: DateTime(2026, 8, 19, 9),
    ),
    AppNotification(
      id: 300,
      type: 'ticket',
      objectId: 9,
      event: 'message',
      title: 'KYC pending',
      actor: 'Anand',
      created: DateTime(2026, 8, 18, 9),
      read: true,
    ),
  ];
}

class _FakeNotifications extends NotificationsRepository {
  _FakeNotifications() : super(_api());

  final deleted = <int>[];
  final readObjects = <String>[];

  /// Records what the screen asked the server for — the Unread tab narrows
  /// with `read=0` rather than paging until it has a screenful. The badge
  /// derivation reads the unread feed too, so the feed's own calls are the
  /// ones at the screen's page size.
  final queries = <String>[];

  Iterable<String> get feedQueries =>
      queries.where((q) => q.contains('limit=50'));

  @override
  Future<Paginated<AppNotification>> list({
    int page = 1,
    int limit = 25,
    String? type,
    bool? read,
    String? q,
  }) async {
    queries.add('page=$page limit=$limit read=$read type=$type q=$q');
    // The server applies `read=0` itself, so the unread feed excludes #9.
    final rows = read == false
        ? _rows().where((n) => !n.read).toList()
        : _rows();
    final items = page == 1 ? rows : <AppNotification>[];
    return Paginated(
      items: items,
      page: page,
      limit: limit,
      total: rows.length,
    );
  }

  /// `/notifications/count` reports unread **rows** (7) and no object-level
  /// total, so the badge has to be derived from the unread feed: 2 cards.
  @override
  Future<NotificationCounts> counts() async {
    countCalls++;
    return NotificationCounts(
      rows: 7,
      conversations: await _unreadConversationsForTest(),
    );
  }

  int countCalls = 0;

  Future<int> _unreadConversationsForTest() async {
    final p = await list(page: 1, limit: 100, read: false);
    return p.items.map((n) => '${n.type}:${n.objectId}').toSet().length;
  }

  @override
  Future<void> deleteOne(int id) async => deleted.add(id);

  @override
  Future<int> readObject(String type, int objectId) async {
    readObjects.add('$type:$objectId');
    return 1;
  }
}

/// The count rendered inside the chip whose label is [label].
Finder _chipCount(String label, String count) => find.descendant(
  of: find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first,
  matching: find.text(count),
);

void main() {
  Widget host(_FakeNotifications repo, GoRouter router) => ProviderScope(
    overrides: [
      notificationsRepositoryProvider.overrideWithValue(repo),
      tokenStorageProvider.overrideWithValue(_NoTokens()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );

  GoRouter router() => GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const NotificationsScreen()),
      GoRoute(
        path: '/tickets/:id',
        builder: (_, s) =>
            Scaffold(body: Center(child: Text('opened ${s.uri}'))),
      ),
    ],
  );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // The inbox used to page until it had a screenful of unread cards, because
  // `GET /notifications` took no filter. It asks for them now.
  testWidgets('the Unread tab narrows server-side with read=0', (tester) async {
    tall(tester);
    final repo = _FakeNotifications();
    await tester.pumpWidget(host(repo, router()));
    await tester.pumpAndSettle();

    expect(
      repo.feedQueries.every((q) => q.contains('read=null')),
      isTrue,
      reason: 'All lists the whole inbox',
    );

    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();

    expect(repo.feedQueries.any((q) => q.contains('read=false')), isTrue);
  });

  // The Unread chip used to badge `GET /notifications/count`, which counts
  // unread rows, while the tab lists one card per ticket/task — so a ticket
  // with six unread events read "Unread 7" over two cards.
  testWidgets('the Unread chip counts cards, not notification rows', (
    tester,
  ) async {
    tall(tester);
    final repo = _FakeNotifications();
    await tester.pumpWidget(host(repo, router()));
    await tester.pumpAndSettle();

    expect(_chipCount('Unread', '2'), findsOneWidget);
    expect(_chipCount('Unread', '7'), findsNothing);

    // And the tab really does list exactly that many cards.
    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    expect(find.text('#5'), findsOneWidget);
    expect(find.text('#7'), findsOneWidget);
    expect(find.text('#9'), findsNothing);
    expect(_chipCount('Unread', '2'), findsOneWidget);
  });

  // Swipe-delete only ever spoke up when it FAILED, so a successful delete just
  // made the card vanish with no confirmation.
  testWidgets('deleting a card confirms with a toast', (tester) async {
    tall(tester);
    final repo = _FakeNotifications();
    await tester.pumpWidget(host(repo, router()));
    await tester.pumpAndSettle();

    await tester.drag(find.text('#7'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(repo.deleted, [200]);
    expect(find.text('Notification deleted'), findsOneWidget);

    // A card that collapses several activities says how many went with it.
    await tester.drag(find.text('#5'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(repo.deleted.length, 7);
    expect(find.text('6 notifications deleted'), findsOneWidget);
  });

  // "View All Activity" was wired to the same callback as "Open", so it landed
  // on the Conversation tab instead of the object's activity log.
  testWidgets('View All Activity opens the object on its Activity tab', (
    tester,
  ) async {
    tall(tester);
    final repo = _FakeNotifications();
    await tester.pumpWidget(host(repo, router()));
    await tester.pumpAndSettle();

    // Select the card to expand the panel (six activities > the five shown, so
    // the link is offered).
    await tester.tap(find.text('#5'));
    await tester.pumpAndSettle();
    expect(find.text('View All Activity'), findsOneWidget);

    await tester.tap(find.text('View All Activity'));
    await tester.pumpAndSettle();

    expect(find.text('opened /tickets/5?tab=activity'), findsOneWidget);
  });

  // "Open" keeps the default tab.
  testWidgets('Open lands on the default tab', (tester) async {
    tall(tester);
    final repo = _FakeNotifications();
    await tester.pumpWidget(host(repo, router()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('#5'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('opened /tickets/5'), findsOneWidget);
  });

  // Alerts that arrive while the app is backgrounded are delivered to the OS
  // tray, not to onMessage, so nothing in the running app hears about them.
  // The shell bumps notificationsChangedProvider on resume; the inbox folds it
  // into its refresh key so the list refetches instead of sitting on the page
  // it loaded before the app went away.
  testWidgets('the inbox refetches when the resume signal is bumped', (
    tester,
  ) async {
    tall(tester);
    final repo = _FakeNotifications();
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationsRepositoryProvider.overrideWithValue(repo),
          tokenStorageProvider.overrideWithValue(_NoTokens()),
        ],
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return MaterialApp.router(routerConfig: router());
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = repo.feedQueries.length;
    expect(before, greaterThan(0));

    ref.read(notificationsChangedProvider.notifier).bump();
    await tester.pumpAndSettle();

    expect(
      repo.feedQueries.length,
      greaterThan(before),
      reason: 'the resume signal must reload the list',
    );
  });
}
