import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/api_exception.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/core/theme/app_theme.dart';
import 'package:zebu_helpdesk/data/faq_repository.dart';
import 'package:zebu_helpdesk/features/faq/faq_screen.dart';
import 'package:zebu_helpdesk/models/faq.dart';
import 'package:zebu_helpdesk/models/me.dart';
import 'package:zebu_helpdesk/providers.dart';

/// Secure storage has no platform channel in a unit test, and the fake
/// repository never reaches the network anyway.
class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

ApiClient _client() => ApiClient(tokenStorage: _NoTokens(), dio: Dio());

/// The Categories page the web serves: name, type, article count.
final _cats = [
  const FaqCategory(id: 1, name: 'Funds', type: 'Featured', faqCount: 2),
  const FaqCategory(id: 2, name: 'General', type: 'Private', faqCount: 1),
  const FaqCategory(
    id: 3,
    name: 'Software',
    type: 'Public',
    public: true,
    faqCount: 0,
  ),
];

/// Records what `POST /faq/categories` was asked to create. [reject] makes the
/// create fail the way the API reports a duplicate name: detail in `fields`.
class _FakeFaq extends FaqRepository {
  _FakeFaq({this.reject = false}) : super(_client());

  final bool reject;
  final List<Map<String, dynamic>> created = [];
  final List<(int, Map<String, dynamic>)> updated = [];
  final List<int> deleted = [];

  @override
  Future<List<FaqCategory>> categories() async => _cats;

  @override
  Future<FaqCategory> updateCategory(
    int id,
    Map<String, dynamic> changes,
  ) async {
    updated.add((id, changes));
    return _cats.firstWhere((c) => c.id == id);
  }

  @override
  Future<int> deleteCategory(int id) async {
    deleted.add(id);
    return _cats.firstWhere((c) => c.id == id).faqCount;
  }

  @override
  Future<FaqCategory> createCategory({
    required String name,
    required String type,
    required String description,
    int parentId = 0,
    String? notes,
  }) async {
    created.add({
      'name': name,
      'type': type,
      'description': description,
      'parentId': parentId,
      'notes': notes,
    });
    if (reject) {
      throw ApiException(
        statusCode: 422,
        code: 'validation',
        message: '',
        fields: const {'name': 'Category already exists'},
      );
    }
    return FaqCategory(id: 9, name: name, type: type);
  }
}

Me _me({bool canManage = true}) => Me.fromJson({
  'id': 7,
  'name': 'Agent Seven',
  'permissions_by_department': {
    '3': {'faq.manage': canManage ? 1 : 0},
  },
});

Future<void> _open(
  WidgetTester t, {
  required _FakeFaq faq,
  bool canManage = true,
}) async {
  // The sheet is taller than the default 800x600 surface.
  await t.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => t.binding.setSurfaceSize(null));

  await t.pumpWidget(
    ProviderScope(
      overrides: [
        faqRepositoryProvider.overrideWithValue(faq),
        meProvider.overrideWith((ref) async => _me(canManage: canManage)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const FaqScreen()),
    ),
  );
  await t.pumpAndSettle();
}

/// The ids the Parent dropdown offers, in order — `0` is the web's
/// "— Top-Level Category —". Read off the widget rather than the open menu,
/// because the categories list behind the modal sheet carries the same names.
List<int> _parentOptions(WidgetTester t) => t
    .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
    .items!
    .map((i) => i.value!)
    .toList();

void main() {
  testWidgets('each category carries the web Type column and its count', (
    t,
  ) async {
    await _open(t, faq: _FakeFaq());

    expect(find.text('Featured'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Public'), findsOneWidget);
    expect(find.text('2 articles'), findsOneWidget);
    expect(find.text('1 article'), findsOneWidget); // singular, not "1 articles"
    expect(find.text('0 articles'), findsOneWidget);
  });

  testWidgets('Add new category is hidden without faq.manage', (t) async {
    await _open(t, faq: _FakeFaq(), canManage: false);
    expect(find.byTooltip('Add new category'), findsNothing);
  });

  testWidgets('Add new category is offered with faq.manage', (t) async {
    await _open(t, faq: _FakeFaq());
    expect(find.byTooltip('Add new category'), findsOneWidget);
  });

  testWidgets('creating a category posts the form and reloads the list', (
    t,
  ) async {
    final faq = _FakeFaq();
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Add new category'));
    await t.pumpAndSettle();

    await t.enterText(find.widgetWithText(TextField, 'Category name'), 'Payins');
    await t.enterText(
      find.widgetWithText(TextField, 'Description'),
      'How pay-ins are handled',
    );
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();

    expect(faq.created, hasLength(1));
    expect(faq.created.single['name'], 'Payins');
    expect(faq.created.single['description'], 'How pay-ins are handled');
    // The web's default visibility for a new category.
    expect(faq.created.single['type'], 'private');
    expect(find.text('Add new category'), findsNothing); // sheet closed
  });

  // The web's form has a Parent dropdown ("— Top-Level Category —"
  // plus every existing category); creating without touching it must still
  // say top level rather than leaving the server to guess.
  testWidgets('create offers every category as a parent, top level by default', (
    t,
  ) async {
    final faq = _FakeFaq();
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Add new category'));
    await t.pumpAndSettle();

    expect(_parentOptions(t), [0, 1, 2, 3]);

    await t.enterText(find.widgetWithText(TextField, 'Category name'), 'Payins');
    await t.enterText(find.widgetWithText(TextField, 'Description'), 'Pay-ins');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();

    expect(faq.created.single['parentId'], 0);
  });

  testWidgets('a picked parent is sent as the new category pid', (t) async {
    final faq = _FakeFaq();
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Add new category'));
    await t.pumpAndSettle();

    await t.tap(find.byType(DropdownButton<int>));
    await t.pumpAndSettle();
    // The categories list is still mounted behind the sheet, so take the
    // occurrence in the dropdown's overlay.
    await t.tap(find.text('General').last);
    await t.pumpAndSettle();

    await t.enterText(find.widgetWithText(TextField, 'Category name'), 'Payins');
    await t.enterText(find.widgetWithText(TextField, 'Description'), 'Pay-ins');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();

    expect(faq.created.single['parentId'], 2);
  });

  // A category can't be re-parented under itself; the web leaves it out of the
  // dropdown and so does the sheet.
  testWidgets('editing hides the category itself from the parent list', (
    t,
  ) async {
    await _open(t, faq: _FakeFaq());

    await t.tap(find.byTooltip('Category actions').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Edit'));
    await t.pumpAndSettle();

    // "Funds" is id 1, the row whose actions were opened.
    expect(_parentOptions(t), [0, 2, 3]);
  });

  testWidgets('name and description are required before any request', (
    t,
  ) async {
    final faq = _FakeFaq();
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Add new category'));
    await t.pumpAndSettle();
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();

    expect(faq.created, isEmpty);
    expect(find.text('Category name is required'), findsOneWidget);
    expect(find.text('A description is required'), findsOneWidget);
  });

  testWidgets('a 2-character name is rejected before any request', (t) async {
    final faq = _FakeFaq();
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Add new category'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Category name'), 'AP');
    await t.enterText(find.widgetWithText(TextField, 'Description'), 'Too short');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();

    // `Category::update()` enforces a 3-char minimum; the client says so first.
    expect(faq.created, isEmpty);
    expect(find.text('Name is too short. 3 chars minimum'), findsOneWidget);
  });

  testWidgets('a server-side field error lands on its field', (t) async {
    final faq = _FakeFaq(reject: true);
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Add new category'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Category name'), 'Funds');
    await t.enterText(find.widgetWithText(TextField, 'Description'), 'Dupe');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();

    expect(find.text('Category already exists'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget); // sheet stayed open
  });

  // Deleting a category takes its articles with it, exactly as the web's mass
  // action does — so the count has to be in the confirmation, before the call.
  testWidgets('delete states how many articles go with the category', (
    t,
  ) async {
    final faq = _FakeFaq();
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Category actions').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Delete').last);
    await t.pumpAndSettle();

    expect(
      find.textContaining('and the 2 articles in it'),
      findsOneWidget,
      reason: 'faq_count from the list row, stated before the delete',
    );

    await t.tap(find.widgetWithText(FilledButton, 'Delete').last);
    await t.pumpAndSettle();

    expect(faq.deleted, [1]);
  });

  // Visibility IS the `type` field — there is no separate endpoint — and the
  // update is partial, so nothing else may ride along.
  testWidgets('Make public sends only the type', (t) async {
    final faq = _FakeFaq();
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Category actions').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Make public'));
    await t.pumpAndSettle();

    expect(faq.updated.single.$1, 1);
    expect(faq.updated.single.$2, {'type': 'public'});
  });

  // The category payload never serves description/notes back, so an untouched
  // (empty) field must not blank the stored value.
  testWidgets('editing sends only the fields that were filled in', (t) async {
    final faq = _FakeFaq();
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Category actions').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Edit'));
    await t.pumpAndSettle();

    expect(find.text('Edit category'), findsOneWidget);
    await t.enterText(
      find.widgetWithText(TextField, 'Category name'),
      'Funds & Payouts',
    );
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    expect(faq.updated.single.$1, 1);
    expect(faq.updated.single.$2.keys, ['name', 'type', 'pid']);
    expect(faq.updated.single.$2['name'], 'Funds & Payouts');
  });

  testWidgets('category actions are hidden without faq.manage', (t) async {
    await _open(t, faq: _FakeFaq(), canManage: false);

    expect(find.byTooltip('Category actions'), findsNothing);
  });
}
