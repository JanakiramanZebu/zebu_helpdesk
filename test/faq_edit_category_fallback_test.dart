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
import 'package:zebu_helpdesk/features/faq/faq_detail_screen.dart';
import 'package:zebu_helpdesk/models/common.dart';
import 'package:zebu_helpdesk/models/faq.dart';
import 'package:zebu_helpdesk/models/me.dart';
import 'package:zebu_helpdesk/models/meta.dart';
import 'package:zebu_helpdesk/providers.dart';

/// Editing an article from its detail screen (`scp/faq.php?id=N`).
///
/// The sheet opens its Category dropdown on the article's own category, and
/// `DropdownButtonFormField` asserts unless that value is one of its items —
/// so the screen has to guarantee the category is in the list it hands over,
/// however `GET /faq/categories` behaved. The other editor tests open the
/// sheet directly with a good list, so only this route covers that.

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

ApiClient _client() => ApiClient(tokenStorage: _NoTokens(), dio: Dio());

/// The article under edit — filed under category 3.
const _article = Faq(
  id: 51,
  question: 'How long does a payin take?',
  answer: 'Up to two hours on a bank working day.',
  type: 'Public',
  published: true,
  category: NamedRef(id: 3, name: 'Software'),
);

class _FakeFaq extends FaqRepository {
  _FakeFaq({this.listing}) : super(_client());

  /// What `GET /faq/categories` answers, or null to make it fail the way a
  /// dropped connection does.
  final List<FaqCategory>? listing;

  @override
  Future<Faq> get(int id) async => _article;

  @override
  Future<List<FaqCategory>> categories() async {
    final rows = listing;
    if (rows == null) {
      throw ApiException(
        statusCode: 500,
        code: 'server_error',
        message: 'Request failed (500)',
      );
    }
    return rows;
  }
}

class _FakeMeta extends MetaRepository {
  _FakeMeta() : super(_client());

  @override
  Future<List<MetaItem>> topics() async => const [
    MetaItem(id: 5, name: 'Payins'),
  ];
}

Me _me() => Me.fromJson({
  'id': 7,
  'name': 'Agent Seven',
  'permissions_by_department': {
    '3': {'faq.manage': 1},
  },
});

Future<void> _openEditor(WidgetTester t, _FakeFaq faq) async {
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
        home: const FaqDetailScreen(faqId: 51),
      ),
    ),
  );
  await t.pumpAndSettle();

  await t.tap(find.byTooltip('Article actions'));
  await t.pumpAndSettle();
  await t.tap(find.text('Edit'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the editor still opens when the category list fails', (t) async {
    await _openEditor(t, _FakeFaq());

    expect(t.takeException(), isNull);
    expect(find.text('Update FAQ'), findsOneWidget);
    // The article's own category stands in. Its visibility isn't in the
    // article payload — only an id and a name — so it reads as Private.
    expect(find.text('Software (Private)'), findsOneWidget);
  });

  testWidgets('a category missing from the listing is added back', (t) async {
    await _openEditor(
      t,
      _FakeFaq(
        listing: const [
          FaqCategory(id: 1, name: 'Funds', type: 'Public', public: true),
        ],
      ),
    );

    expect(t.takeException(), isNull);
    expect(find.text('Update FAQ'), findsOneWidget);
    expect(find.text('Software (Private)'), findsOneWidget);
  });

  testWidgets('a listed category is used as listed, not duplicated', (t) async {
    await _openEditor(
      t,
      _FakeFaq(
        listing: const [
          FaqCategory(id: 1, name: 'Funds', type: 'Public', public: true),
          FaqCategory(id: 3, name: 'Software', type: 'Public', public: true),
        ],
      ),
    );

    expect(t.takeException(), isNull);
    // The real row wins — one option, and it keeps the listing's visibility.
    expect(find.text('Software (Public)'), findsOneWidget);
    expect(find.text('Software (Private)'), findsNothing);
  });
}
