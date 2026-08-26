import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/api_exception.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/core/theme/app_theme.dart';
import 'package:zebu_helpdesk/data/faq_repository.dart';
import 'package:zebu_helpdesk/data/meta_repository.dart';
import 'package:zebu_helpdesk/features/faq/faq_screen.dart';
import 'package:zebu_helpdesk/models/faq.dart';
import 'package:zebu_helpdesk/models/me.dart';
import 'package:zebu_helpdesk/features/faq/faq_editor_sheet.dart';
import 'package:zebu_helpdesk/models/common.dart';
import 'package:zebu_helpdesk/models/meta.dart';
import 'package:zebu_helpdesk/providers.dart';
import 'package:zebu_helpdesk/widgets/rich_message_field.dart';

/// The web's "Add New FAQ" form (`scp/faq.php?a=add`), ported to the
/// Knowledgebase screen: category, help topics, listing type, question,
/// answer, internal notes.

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

ApiClient _client() => ApiClient(tokenStorage: _NoTokens(), dio: Dio());

final _cats = [
  // Featured is a public visibility in osTicket, so the picker labels it
  // "(Public)" exactly as the web's option does.
  const FaqCategory(
    id: 1,
    name: 'Funds',
    type: 'Featured',
    public: true,
    faqCount: 2,
  ),
  const FaqCategory(
    id: 3,
    name: 'Software',
    type: 'Public',
    public: true,
    faqCount: 0,
  ),
];

class _FakeFaq extends FaqRepository {
  _FakeFaq({this.reject = false}) : super(_client());

  /// Makes the create fail the way the API reports a duplicate question:
  /// blank message, detail in `fields`.
  final bool reject;
  final List<Map<String, dynamic>> articles = [];
  final List<(int, Map<String, dynamic>)> updated = [];
  final List<int> deleted = [];
  final List<(int, int)> attachmentDeletes = [];

  @override
  Future<List<FaqCategory>> categories() async => _cats;

  @override
  Future<Faq> createArticle({
    required int categoryId,
    required String question,
    required String answer,
    bool published = false,
    List<int> topicIds = const [],
    String? notes,
  }) async {
    articles.add({
      'category_id': categoryId,
      'question': question,
      'answer': answer,
      'published': published,
      'topic_ids': topicIds,
      'notes': notes,
    });
    if (reject) {
      throw ApiException(
        statusCode: 422,
        code: 'validation',
        message: '',
        fields: const {'question': 'Question already exists'},
      );
    }
    return Faq(id: 51, question: question, published: published);
  }

  @override
  Future<Faq> updateArticle(int id, Map<String, dynamic> changes) async {
    updated.add((id, changes));
    return Faq(
      id: id,
      question: changes['question'] as String? ?? 'How long does a payin take?',
      published: changes['published'] as bool? ?? false,
    );
  }

  @override
  Future<void> deleteArticle(int id) async => deleted.add(id);

  @override
  Future<void> deleteAttachment(int id, int attId) async =>
      attachmentDeletes.add((id, attId));
}

class _FakeMeta extends MetaRepository {
  _FakeMeta() : super(_client());

  @override
  Future<List<MetaItem>> topics() async => const [
    MetaItem(id: 4, name: 'Account opening'),
    MetaItem(id: 5, name: 'Payins'),
  ];
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
  await t.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => t.binding.setSurfaceSize(null));

  await t.pumpWidget(
    ProviderScope(
      overrides: [
        faqRepositoryProvider.overrideWithValue(faq),
        metaRepositoryProvider.overrideWithValue(_FakeMeta()),
        meProvider.overrideWith((ref) async => _me(canManage: canManage)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const FaqScreen()),
    ),
  );
  await t.pumpAndSettle();
}

/// Types into a rich-text field through its controller — the Fleather editor
/// has no plain [TextField] for `enterText` to target.
Future<void> _write(WidgetTester t, int index, String text) async {
  final field = t.widget<RichMessageField>(
    find.byType(RichMessageField).at(index),
  );
  field.controller.replaceText(
    0,
    0,
    text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  await t.pump();
}

const _answerField = 0;

void main() {
  testWidgets('Add new FAQ is hidden without faq.manage', (t) async {
    await _open(t, faq: _FakeFaq(), canManage: false);
    expect(find.byTooltip('Add new FAQ'), findsNothing);
  });

  testWidgets('Add new FAQ is offered with faq.manage', (t) async {
    await _open(t, faq: _FakeFaq());
    expect(find.byTooltip('Add new FAQ'), findsOneWidget);
  });

  testWidgets('creating an article posts the web form field for field', (
    t,
  ) async {
    final faq = _FakeFaq();
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Add new FAQ'));
    await t.pumpAndSettle();

    // Category listing (the web's required select, placeholder rejected).
    await t.tap(find.text('Select FAQ category'));
    await t.pumpAndSettle();
    await t.tap(find.text('Software (Public)').last);
    await t.pumpAndSettle();

    // Help topics — the web's multi-select of the agent's own topics.
    await t.tap(find.text('None'));
    await t.pumpAndSettle();
    await t.tap(find.text('Payins'));
    await t.pumpAndSettle();
    await t.tap(find.text('Apply'));
    await t.pumpAndSettle();

    await t.enterText(
      find.widgetWithText(TextField, 'Question'),
      'How long does a payin take?',
    );
    await _write(t, _answerField, 'Up to two hours on a bank working day.');

    await t.tap(find.text('Add FAQ'));
    await t.pumpAndSettle();

    expect(faq.articles, hasLength(1));
    final sent = faq.articles.single;
    expect(sent['category_id'], 3);
    expect(sent['question'], 'How long does a payin take?');
    expect(sent['answer'], contains('bank working day'));
    expect(sent['topic_ids'], [5]);
    // The web's Listing Type select opens on Internal — `published: false`,
    // which the API reports back as type "Internal".
    expect(sent['published'], isFalse);
  });

  testWidgets('opening from a category preselects it', (t) async {
    final faq = _FakeFaq();
    await _open(t, faq: faq);

    await t.tap(find.byType(PopupMenuButton<String>).first);
    await t.pumpAndSettle();
    await t.tap(find.text('Add FAQ').last);
    await t.pumpAndSettle();

    expect(find.text('Funds (Public)'), findsOneWidget);
    expect(find.text('Select FAQ category'), findsNothing);
  });

  testWidgets('question, category and answer are required before any request', (
    t,
  ) async {
    final faq = _FakeFaq();
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Add new FAQ'));
    await t.pumpAndSettle();
    await t.tap(find.text('Add FAQ'));
    await t.pumpAndSettle();

    // `FAQ::update()`'s own wording, and nothing was sent.
    expect(find.text('Question required'), findsOneWidget);
    expect(find.text('Category is required'), findsOneWidget);
    expect(find.text('FAQ answer is required'), findsOneWidget);
    expect(faq.articles, isEmpty);
  });

  testWidgets('a duplicate question comes back on the question field', (
    t,
  ) async {
    final faq = _FakeFaq(reject: true);
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Add new FAQ'));
    await t.pumpAndSettle();
    await t.tap(find.text('Select FAQ category'));
    await t.pumpAndSettle();
    await t.tap(find.text('Software (Public)').last);
    await t.pumpAndSettle();
    await t.enterText(
      find.widgetWithText(TextField, 'Question'),
      'How long does a payin take?',
    );
    await _write(t, _answerField, 'Up to two hours.');
    await t.tap(find.text('Add FAQ'));
    await t.pumpAndSettle();

    expect(find.text('Question already exists'), findsOneWidget);
    expect(find.text('Add FAQ'), findsWidgets, reason: 'sheet stays open');
  });

  // --- Editing (`POST /faq/{id}`, partial) ---------------------------------

  /// The full article `GET /faq/{id}` serves — what the edit form opens on.
  const stored = Faq(
    id: 51,
    question: 'How long does a payin take?',
    answer: '<p>Up to two hours.</p>',
    published: false,
    type: 'Internal',
    category: NamedRef(id: 3, name: 'Software'),
    attachments: [Attachment(id: 8, name: 'flow.png')],
    topicIds: [5],
    notes: '<p>Agents only.</p>',
  );

  /// Opens the editor straight over a bare app, so editing can be exercised
  /// without the detail route.
  Future<void> openEditor(
    WidgetTester t,
    _FakeFaq faq, {
    Faq article = stored,
  }) async {
    await t.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          faqRepositoryProvider.overrideWithValue(faq),
          metaRepositoryProvider.overrideWithValue(_FakeMeta()),
          meProvider.overrideWith((ref) async => _me()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showFaqEditorSheet(
                  context,
                  categories: _cats,
                  existing: article,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('the edit form opens on the stored article', (t) async {
    await openEditor(t, _FakeFaq());

    expect(find.text('Update FAQ'), findsOneWidget);
    expect(find.text('Software (Public)'), findsOneWidget);
    // Help topics and attachments both round-trip out of the read payload.
    expect(find.text('Payins'), findsOneWidget);
    expect(find.text('Attachments (1)'), findsOneWidget);
    expect(find.textContaining('flow.png'), findsOneWidget);
  });

  testWidgets('editing sends the form but never the attachments', (t) async {
    final faq = _FakeFaq();
    await openEditor(t, faq);

    // Publish it, the web's Listing Type change.
    await t.tap(find.text('Internal — Agents only'));
    await t.pumpAndSettle();
    await t.tap(find.text('Public — Published to the knowledgebase').last);
    await t.pumpAndSettle();

    await t.tap(find.text('Save changes'));
    await t.pumpAndSettle();

    expect(faq.updated.length, 1);
    final (id, sent) = faq.updated.single;
    expect(id, 51);
    expect(sent['published'], isTrue);
    expect(sent['category_id'], 3);
    expect(sent['topic_ids'], [5]);
    // The server treats a file list as "keep only these", so a form that isn't
    // editing files must not name them at all.
    expect(sent.containsKey('attachments'), isFalse);
    expect(sent.containsKey('files'), isFalse);
  });

  // --- Listing type: `published` is lossy, so only write it deliberately ---
  //
  // `FAQ::isPublished()` is `ispublished != 0 && category->isPublic()`, and
  // the API's `published` boolean is that. Writing it back from a read would
  // demote the article's own column, so the editor reads `type` instead and
  // only sends `published` when the agent moved the dropdown.

  testWidgets('an untouched listing type is not written back', (t) async {
    final faq = _FakeFaq();
    await openEditor(t, faq);

    await t.enterText(
      find.widgetWithText(TextField, 'Question'),
      'How long does a payin really take?',
    );
    await t.tap(find.text('Save changes'));
    await t.pumpAndSettle();

    final (_, sent) = faq.updated.single;
    expect(sent['question'], 'How long does a payin really take?');
    expect(
      sent.containsKey('published'),
      isFalse,
      reason: 'the dropdown never moved, so ispublished must be left alone',
    );
  });

  testWidgets('a Public article under a Private category stays Public', (
    t,
  ) async {
    // The trap: its own ispublished is 1, but isPublished() folds in the
    // category and reports false. Reading the boolean would demote it to 0.
    const publicInPrivateCategory = Faq(
      id: 52,
      question: 'Internal-only category, public article',
      answer: '<p>Body.</p>',
      published: false,
      type: 'Public',
      category: NamedRef(id: 1, name: 'Funds'),
    );
    final faq = _FakeFaq();
    await openEditor(t, faq, article: publicInPrivateCategory);

    expect(find.text('Public — Published to the knowledgebase'), findsOneWidget);

    await t.tap(find.text('Save changes'));
    await t.pumpAndSettle();

    final (_, sent) = faq.updated.single;
    expect(sent.containsKey('published'), isFalse);
  });

  testWidgets('a Featured article keeps Featured through an edit', (t) async {
    const featured = Faq(
      id: 53,
      question: 'Front-page question',
      answer: '<p>Body.</p>',
      published: true,
      type: 'Featured',
      category: NamedRef(id: 3, name: 'Software'),
    );
    final faq = _FakeFaq();
    await openEditor(t, faq, article: featured);

    // Offered only because it already is Featured — it cannot be set.
    expect(
      find.text('Featured — Promoted to the help centre front page'),
      findsOneWidget,
    );

    await t.tap(find.text('Save changes'));
    await t.pumpAndSettle();

    final (_, sent) = faq.updated.single;
    expect(
      sent.containsKey('published'),
      isFalse,
      reason: 'published: true would flatten ispublished 2 -> 1',
    );
  });

  testWidgets('Featured is not offered for a new article', (t) async {
    final faq = _FakeFaq();
    await _open(t, faq: faq);

    await t.tap(find.byTooltip('Add new FAQ'));
    await t.pumpAndSettle();
    await t.tap(find.text('Internal — Agents only'));
    await t.pumpAndSettle();

    // Scoped to the dropdown's own wording: a category chip on the screen
    // behind the sheet also says "Featured".
    expect(
      find.textContaining('Promoted to the help centre'),
      findsNothing,
    );
  });

  testWidgets('removing a stored attachment deletes it after the save', (
    t,
  ) async {
    final faq = _FakeFaq();
    await openEditor(t, faq);

    await t.tap(find.byTooltip('Remove').first);
    await t.pumpAndSettle();
    expect(find.text('Attachments (0)'), findsOneWidget);

    await t.tap(find.text('Save changes'));
    await t.pumpAndSettle();

    expect(faq.attachmentDeletes, [(51, 8)]);
  });
}
