import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/paginated.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/tags_repository.dart';
import 'package:zebu_helpdesk/features/tags/tags_screen.dart';
import 'package:zebu_helpdesk/models/common.dart';
import 'package:zebu_helpdesk/models/me.dart';
import 'package:zebu_helpdesk/providers.dart';

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

const _tags = [
  Tag(id: 11, name: 'Refunds', color: '#5bc0de', objectCount: 4),
  Tag(id: 12, name: 'refund', color: '#d9534f', objectCount: 2),
  Tag(id: 13, name: 'Payins', color: '#5cb85c'),
];

class _FakeTags extends TagsRepository {
  _FakeTags() : super(ApiClient(tokenStorage: _NoTokens(), dio: Dio()));

  ({int intoId, List<int> sourceIds})? mergeCall;
  final deleted = <int>[];

  @override
  Future<Paginated<Tag>> list({int page = 1, int limit = 25}) async =>
      Paginated(items: page == 1 ? _tags : const [], page: page, limit: limit,
          total: _tags.length);

  @override
  Future<TagMergeResult> merge({
    required int intoId,
    required List<int> sourceIds,
  }) async {
    mergeCall = (intoId: intoId, sourceIds: sourceIds);
    return TagMergeResult(
      into: const Tag(id: 11, name: 'Refunds', objectCount: 6),
      merged: const [MergedTag(id: 12, name: 'refund', objectsBefore: 2)],
    );
  }

  @override
  Future<TagDeleteResult> delete(int id) async {
    deleted.add(id);
    return const TagDeleteResult(ok: true, objectCount: 0);
  }
}

/// A department manager — `Tag::canManage()` on this install.
Me _manager() => Me.fromJson({
  'id': 7,
  'name': 'Agent Seven',
  'computed_capabilities': {
    'managed_departments': [3],
  },
});

void main() {
  Widget host(_FakeTags repo) => ProviderScope(
    overrides: [
      tagsRepositoryProvider.overrideWithValue(repo),
      meProvider.overrideWith((ref) async => _manager()),
    ],
    child: const MaterialApp(home: TagsScreen()),
  );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // Merge is irreversible and the web's own merge silently destroys the
  // associations, so this app is the only safe path — the direction it sends
  // has to be exactly the one the UI showed.
  testWidgets('merge keeps the first pick and consumes the rest', (
    tester,
  ) async {
    tall(tester);
    final repo = _FakeTags();
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    // Long-press picks the survivor.
    await tester.longPress(find.text('Refunds'));
    await tester.pumpAndSettle();
    expect(find.text('Merge into "Refunds"'), findsOneWidget);
    expect(find.text('Keep'), findsOneWidget);

    // A tap in merge mode adds a tag to be consumed.
    await tester.tap(find.text('refund'));
    await tester.pumpAndSettle();
    expect(find.text('Merge 1 tag'), findsOneWidget);

    await tester.tap(find.text('Merge 1 tag'));
    await tester.pumpAndSettle();

    // The confirmation names both sides and the number of tagged items moving.
    expect(find.textContaining('"refund" will be deleted'), findsOneWidget);
    expect(find.textContaining('2 tagged items will move'), findsOneWidget);
    // Both the tray and the dialog state the survivor.
    expect(find.textContaining('move to "Refunds"'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Merge').last);
    await tester.pumpAndSettle();

    expect(repo.mergeCall?.intoId, 11);
    expect(repo.mergeCall?.sourceIds, [12]);
  });

  // The server refuses to delete a tag that is still applied rather than
  // detaching it from live tickets, so the app must not even try.
  testWidgets('deleting a tag in use offers merge instead', (tester) async {
    tall(tester);
    final repo = _FakeTags();
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.text('Tag is in use'), findsOneWidget);
    expect(
      find.textContaining('is on 4 ticket/tasks'),
      findsOneWidget,
      reason: 'the count comes from object_count',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Merge').last);
    await tester.pumpAndSettle();

    expect(repo.deleted, isEmpty);
    expect(find.text('Merge into "Refunds"'), findsOneWidget);
  });

  // An unused tag deletes without the merge detour.
  testWidgets('an unused tag deletes straight away', (tester) async {
    tall(tester);
    final repo = _FakeTags();
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(find.text('Delete tag?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
    await tester.pumpAndSettle();

    expect(repo.deleted, [13]);
  });
}
