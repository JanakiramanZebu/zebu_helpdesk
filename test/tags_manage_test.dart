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
  ({String name, String? color, bool? isActive})? createCall;
  final updates = <(int, Map<String, dynamic>)>[];

  /// Set to have `POST /tags` ignore `is_active` the way an install that
  /// never implemented the field would, so the follow-up update is exercised.
  bool ignoresIsActiveOnCreate = false;

  @override
  Future<Tag> create({
    required String name,
    String? color,
    bool? isActive,
  }) async {
    createCall = (name: name, color: color, isActive: isActive);
    return Tag(
      id: 99,
      name: name,
      color: color ?? '#666666',
      isActive: ignoresIsActiveOnCreate ? true : (isActive ?? true),
    );
  }

  @override
  Future<Tag> update(int id, Map<String, dynamic> changes) async {
    updates.add((id, changes));
    return Tag(
      id: id,
      name: changes['name'] as String? ?? 'Refunds',
      color: changes['color'] as String? ?? '#5bc0de',
      isActive: changes['is_active'] as bool? ?? true,
    );
  }

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

  // --- The create / edit sheet vs the web's Add New Tag form ---------------

  /// Opens the FAB's create sheet. The name box is first, the colour second.
  Future<_FakeTags> openCreate(WidgetTester tester) async {
    tall(tester);
    final repo = _FakeTags();
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    return repo;
  }

  final nameField = find.byType(TextField).at(0);
  final colourField = find.byType(TextField).at(1);
  final saveButton = find.widgetWithText(FilledButton, 'Save');

  // The web's Add form starts on osTicket's own default colour, and its
  // Status checkbox is on the Add form too — not only on the edit form.
  testWidgets('create offers the web default colour and the Active switch', (
    tester,
  ) async {
    await openCreate(tester);

    expect(find.text('New tag'), findsOneWidget);
    expect(
      tester.widget<TextField>(colourField).controller?.text,
      '#3b7dd8',
    );
    expect(find.byType(SwitchListTile), findsOneWidget);
  });

  testWidgets('a tag can be created already disabled', (tester) async {
    final repo = await openCreate(tester);

    await tester.enterText(nameField, 'Escalation');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repo.createCall?.name, 'Escalation');
    expect(repo.createCall?.isActive, isFalse);
    expect(repo.updates, isEmpty, reason: 'the create call already took it');
  });

  // If POST /tags ignores the field, the tag would come back active and the
  // agent would never know the switch did nothing.
  testWidgets('a disabled create is enforced when the server ignores it', (
    tester,
  ) async {
    tall(tester);
    final repo = _FakeTags()..ignoresIsActiveOnCreate = true;
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(nameField, 'Escalation');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repo.updates.length, 1);
    expect(repo.updates.single.$1, 99);
    expect(repo.updates.single.$2, {'is_active': false});
  });

  // The web's control is a free colour picker, so a colour outside the quick
  // picks has to survive the trip.
  testWidgets('any hex colour can be typed, not just the swatches', (
    tester,
  ) async {
    final repo = await openCreate(tester);

    await tester.enterText(nameField, 'Escalation');
    await tester.enterText(colourField, '#A1B2C3');
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repo.createCall?.color, '#a1b2c3');
  });

  testWidgets('a colour that is not a hex is refused before any request', (
    tester,
  ) async {
    final repo = await openCreate(tester);

    await tester.enterText(nameField, 'Escalation');
    await tester.enterText(colourField, 'blue');
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // The server's own wording, and nothing was sent.
    expect(
      find.textContaining('Enter a valid hex color'),
      findsOneWidget,
    );
    expect(repo.createCall, isNull);
  });

  // Editing a tag recoloured on the web used to show no swatch selected at
  // all; the hex box states the real colour.
  testWidgets('editing shows the stored colour even outside the swatches', (
    tester,
  ) async {
    tall(tester);
    final repo = _FakeTags();
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Refunds'));
    await tester.pumpAndSettle();

    expect(find.text('Edit tag'), findsOneWidget);
    expect(
      tester.widget<TextField>(colourField).controller?.text,
      '#5bc0de',
    );
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
