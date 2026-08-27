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

AppNotification _act(int id, String event, {bool read = false}) =>
    AppNotification(
      id: id,
      event: event,
      title: 'Payout not received',
      actor: 'Ravi',
      created: DateTime(2026, 8, 20, 10, id % 60),
      read: read,
    );

/// The server's grouped inbox: ticket #009893 with six activities (two unread),
/// task #44 with one unread, and ticket #000009 fully read — three cards, two
/// of them unread.
List<NotificationGroup> _groups() => [
  NotificationGroup(
    type: 'ticket',
    objectId: 5,
    number: '009893',
    subject: 'Payout not received',
    unreadCount: 2,
    totalCount: 6,
    lastActivity: DateTime(2026, 8, 20, 10, 30),
    activities: [
      for (var i = 0; i < 6; i++)
        _act(100 + i, ['message', 'note', 'status', 'transfer', 'assigned',
          'mention'][i], read: i >= 2),
    ],
  ),
  NotificationGroup(
    type: 'task',
    objectId: 7,
    number: '000044',
    subject: 'Certificate renewal',
    unreadCount: 1,
    totalCount: 1,
    lastActivity: DateTime(2026, 8, 19, 9),
    activities: [_act(200, 'message')],
  ),
  NotificationGroup(
    type: 'ticket',
    objectId: 9,
    number: '000009',
    subject: 'KYC pending',
    unreadCount: 0,
    totalCount: 1,
    lastActivity: DateTime(2026, 8, 18, 9),
    activities: [_act(300, 'message', read: true)],
  ),
];

class _FakeNotifications extends NotificationsRepository {
  _FakeNotifications() : super(_api());

  final deleted = <int>[];
  final readObjects = <String>[];

  /// What the screen asked the server for. Every view narrows in the query
  /// now — the screen never filters a loaded page.
  final queries = <String>[];

  @override
  Future<Paginated<NotificationGroup>> list({
    int page = 1,
    int limit = 25,
    String? type,
    bool? read,
    String? q,
  }) async {
    queries.add('page=$page limit=$limit read=$read type=$type q=$q');
    // The server applies the filters itself.
    var groups = _groups();
    if (read == false) groups = groups.where((g) => g.hasUnread).toList();
    if (type != null) groups = groups.where((g) => g.type == type).toList();
    if (q != null && q.isNotEmpty) {
      final needle = q.toLowerCase();
      groups = groups
          .where((g) => g.displaySubject.toLowerCase().contains(needle))
          .toList();
    }
    return Paginated(
      items: page == 1 ? groups : const [],
      page: page,
      limit: limit,
      total: groups.length,
    );
  }

  /// `/notifications/count` is object-based now: 3 cards, 2 of them unread.
  @override
  Future<NotificationCounts> counts() async {
    countCalls++;
    return const NotificationCounts(
      unread: 2,
      total: 3,
      byType: {
        'ticket': (total: 2, unread: 1),
        'task': (total: 1, unread: 1),
      },
    );
  }

  int countCalls = 0;

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
  of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
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
      GoRoute(
        path: '/tasks/:id',
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

  // The list is grouped server-side, so a card carries the object's display
  // number — not the raw object id the client used to fall back on.
  testWidgets('cards head with the object number and subject', (tester) async {
    tall(tester);
    final repo = _FakeNotifications();
    await tester.pumpWidget(host(repo, router()));
    await tester.pumpAndSettle();

    expect(find.text('#009893'), findsOneWidget);
    expect(find.text('Payout not received'), findsOneWidget);
    expect(find.text('#000044'), findsOneWidget);
    // A card with more than one unread event badges the server's count.
    expect(find.text('2'), findsWidgets);
  });

  // Every view narrows in the query — the Unread tab with `read=0`, the type
  // tabs with `type=`. Nothing is filtered after the fetch, because a page is
  // counted in cards and dropping one would hide a card the server did send.
  testWidgets('the tabs narrow server-side', (tester) async {
    tall(tester);
    final repo = _FakeNotifications();
    await tester.pumpWidget(host(repo, router()));
    await tester.pumpAndSettle();

    expect(
      repo.queries.every((q) => q.contains('read=null') && q.contains('type=null')),
      isTrue,
      reason: 'All lists the whole inbox',
    );

    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    expect(repo.queries.last, contains('read=false'));
    expect(find.text('#000009'), findsNothing);

    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(repo.queries.last, contains('type=task'));
    expect(find.text('#000044'), findsOneWidget);
    expect(find.text('#009893'), findsNothing);
  });

  // The chips used to badge unread *rows* while the tab listed one card per
  // ticket/task. `/notifications/count` is object-based now, so each chip's
  // number is the size of the list it opens.
  testWidgets('the chips badge the card counts from by_type', (tester) async {
    tall(tester);
    final repo = _FakeNotifications();
    await tester.pumpWidget(host(repo, router()));
    await tester.pumpAndSettle();

    expect(_chipCount('All', '3'), findsOneWidget);
    expect(_chipCount('Unread', '2'), findsOneWidget);
    expect(_chipCount('Tickets', '2'), findsOneWidget);
    expect(_chipCount('Tasks', '1'), findsOneWidget);

    // And the Unread tab really does list exactly that many cards.
    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    expect(find.text('#009893'), findsOneWidget);
    expect(find.text('#000044'), findsOneWidget);
    expect(find.text('#000009'), findsNothing);
  });

  // Swipe-delete only ever spoke up when it FAILED, so a successful delete just
  // made the card vanish with no confirmation.
  testWidgets('deleting a card confirms with a toast', (tester) async {
    tall(tester);
    final repo = _FakeNotifications();
    await tester.pumpWidget(host(repo, router()));
    await tester.pumpAndSettle();

    await tester.drag(find.text('#000044'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(repo.deleted, [200]);
    expect(find.text('Notification deleted'), findsOneWidget);

    // A card that stands for several activities says how many went with it.
    await tester.drag(find.text('#009893'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(repo.deleted.length, 7);
    expect(find.text('6 notifications deleted'), findsOneWidget);
  });

  // Tapping a card marks the whole object read in ONE request — a card with six
  // activities must not cost six.
  testWidgets('selecting a card marks the object read once', (tester) async {
    tall(tester);
    final repo = _FakeNotifications();
    await tester.pumpWidget(host(repo, router()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('#009893'));
    await tester.pumpAndSettle();

    expect(repo.readObjects, ['ticket:5']);
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

    // Select the card to expand the panel (total_count 6 > the five shown, so
    // the link is offered).
    await tester.tap(find.text('#009893'));
    await tester.pumpAndSettle();
    expect(find.text('View All Activity'), findsOneWidget);

    await tester.tap(find.text('View All Activity'));
    await tester.pumpAndSettle();

    expect(find.text('opened /tickets/5?tab=activity'), findsOneWidget);
  });

  // The route target is `object_id` + `type`, never an activity id.
  testWidgets('Open routes on object_id, and a task lands on /tasks', (
    tester,
  ) async {
    tall(tester);
    final repo = _FakeNotifications();
    await tester.pumpWidget(host(repo, router()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('#000044'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('opened /tasks/7'), findsOneWidget);
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

    final before = repo.queries.length;
    expect(before, greaterThan(0));

    ref.read(notificationsChangedProvider.notifier).bump();
    await tester.pumpAndSettle();

    expect(
      repo.queries.length,
      greaterThan(before),
      reason: 'the resume signal must reload the list',
    );
  });
}
