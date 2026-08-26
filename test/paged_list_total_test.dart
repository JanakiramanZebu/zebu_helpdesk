import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/paginated.dart';
import 'package:zebu_helpdesk/widgets/paged_list_view.dart';

/// TC_621: the "N total" line under the app-bar title must describe the ACTIVE
/// view — including after a swipe between filter tabs.
///
/// Both list screens page their filter tabs through a [PageView] and hand
/// `onTotalChanged` to the active page only. A page built while still inactive
/// (the incoming page of a swipe) therefore fetched with no listener attached
/// and dropped its total; once it settled into place an unchanged `refreshKey`
/// meant no refetch, so the host was never told and kept showing the total of
/// the tab the user had just swiped away from. [PagedListView] now remembers
/// its last total and re-announces it when handed a listener it lacked.
///
/// This host is the two list screens in miniature: same PageView, same
/// active-only gating, same "N total" header.
class _TabbedListHost extends StatefulWidget {
  const _TabbedListHost({required this.totals});

  /// Pagination total the fetcher reports for each tab.
  final List<int> totals;

  @override
  State<_TabbedListHost> createState() => _TabbedListHostState();
}

class _TabbedListHostState extends State<_TabbedListHost> {
  int _index = 0;
  int? _total;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tasks'),
              if (_total != null) Text('$_total total'),
            ],
          ),
        ),
        body: PageView.builder(
          onPageChanged: (i) => setState(() => _index = i),
          itemCount: widget.totals.length,
          itemBuilder: (context, index) {
            final active = index == _index;
            return PagedListView<String>(
              refreshKey: 'view$index',
              // Only the visible page feeds the app-bar total.
              onTotalChanged: active
                  ? (t) {
                      if (t != _total) setState(() => _total = t);
                    }
                  : null,
              fetch: (page) async => Paginated<String>(
                items: ['view$index row'],
                page: page,
                limit: 25,
                total: widget.totals[index],
              ),
              itemBuilder: (context, row) => ListTile(title: Text(row)),
            );
          },
        ),
      ),
    );
  }
}

void main() {
  testWidgets('the first view announces its total', (tester) async {
    await tester.pumpWidget(const _TabbedListHost(totals: [12, 7]));
    await tester.pumpAndSettle();

    expect(find.text('12 total'), findsOneWidget);
  });

  testWidgets('swiping to the next view retotals the header', (tester) async {
    await tester.pumpWidget(const _TabbedListHost(totals: [12, 7]));
    await tester.pumpAndSettle();
    expect(find.text('12 total'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('view1 row'), findsOneWidget);
    expect(find.text('7 total'), findsOneWidget);
    expect(find.text('12 total'), findsNothing);
  });

  testWidgets('swiping back restores the first view\'s total', (tester) async {
    await tester.pumpWidget(const _TabbedListHost(totals: [12, 7]));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(-500, 0), 1200);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(PageView), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();

    expect(find.text('view0 row'), findsOneWidget);
    expect(find.text('12 total'), findsOneWidget);
  });
}
